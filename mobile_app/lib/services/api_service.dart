import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/transcription_result.dart';
import '../models/subtitle_result.dart';
import '../config/api_config.dart';

class ApiService {
  // API Configuration - Edit lib/config/api_config.dart to change server IP
  static String get baseUrl => ApiConfig.baseUrl;
  
  final Dio _dio;
  CancelToken? _currentCancelToken;
  
  ApiService() : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(minutes: 2),
    receiveTimeout: const Duration(hours: 1),
    sendTimeout: const Duration(hours: 1),
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  )) {
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      error: true,
      logPrint: (obj) => debugPrint('[API] $obj'),
    ));
    
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (_shouldRetry(error)) {
          debugPrint('[API] Retrying request...');
          try {
            final response = await _retry(error.requestOptions);
            handler.resolve(response);
          } catch (e) {
            handler.next(error);
          }
        } else {
          handler.next(error);
        }
      },
    ));
  }

  int _retryCount = 0;
  static const int maxRetries = 3;
  static const int baseDelayMs = 1000;

  bool _shouldRetry(DioException error) {
    if (_retryCount >= maxRetries) {
      return false;
    }
    
    return error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.sendTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           error.type == DioExceptionType.connectionError ||
           (error.response?.statusCode ?? 0) >= 500;
  }

  Future<Response> _retry(RequestOptions requestOptions) async {
    _retryCount++;
    
    final delay = baseDelayMs * (1 << (_retryCount - 1));
    debugPrint('[API] Retry attempt $_retryCount/$maxRetries after ${delay}ms');
    
    await Future.delayed(Duration(milliseconds: delay));
    
    final options = Options(
      method: requestOptions.method,
      headers: requestOptions.headers,
    );
    
    try {
      final response = await _dio.request(
        requestOptions.path,
        data: requestOptions.data,
        queryParameters: requestOptions.queryParameters,
        options: options,
      );
      
      _retryCount = 0;
      return response;
    } catch (e) {
      if (_retryCount >= maxRetries) {
        debugPrint('[API] Max retries reached, giving up');
        _retryCount = 0;
      }
      rethrow;
    }
  }
  
  void cancelCurrentRequest() {
    _currentCancelToken?.cancel('User cancelled');
    _currentCancelToken = null;
  }

  void updateBaseUrl() {
    final newBaseUrl = ApiConfig.baseUrl;
    debugPrint('[API] Updating base URL to: $newBaseUrl');
    _dio.options.baseUrl = newBaseUrl;
  }

  /// Check API health
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.data;
    } catch (e) {
      debugPrint('Health check error: $e');
      rethrow;
    }
  }

  /// Transcribe audio file with progress callback
  /// [fileBytes] is required on web since dart:io File is not available.
  Future<TranscriptionResult> transcribeAudio(
    String filePath, {
    List<int>? fileBytes,
    Function(int, int)? onUploadProgress,
    Function(String, int, String)? onProcessProgress,
  }) async {
    _currentCancelToken = CancelToken();
    
    try {
      final fileName = filePath.split('/').last.split('\\').last;
      
      late FormData formData;
      if (kIsWeb && fileBytes != null) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            fileBytes,
            filename: fileName,
          ),
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            filePath,
            filename: fileName,
          ),
        });
      }

      final response = await _dio.post(
        '/transcribe',
        data: formData,
        cancelToken: _currentCancelToken,
        onSendProgress: (sent, total) {
          debugPrint('Upload progress: ${(sent / total * 100).toStringAsFixed(0)}%');
          if (onUploadProgress != null) {
            onUploadProgress(sent, total);
          }
        },
      );

      debugPrint('[API] Transcription response type: ${response.data.runtimeType}');
      debugPrint('[API] Transcription response: ${response.data}');
      
      if (response.data is! Map<String, dynamic>) {
        debugPrint('[API] ERROR: Response data is not a Map, it is ${response.data.runtimeType}');
        throw Exception('Invalid response format from server');
      }

      final result = TranscriptionResult.fromJson(response.data as Map<String, dynamic>);
      
      // If processing progress callback provided and we have a job_id, poll for progress
      if (onProcessProgress != null && response.data['job_id'] != null) {
        final jobId = response.data['job_id'];
        debugPrint('Job ID: $jobId');
      }
      
      _currentCancelToken = null;
      return result;
    } on DioException catch (e) {
      _currentCancelToken = null;
      
      if (CancelToken.isCancel(e)) {
        throw Exception('Transcription cancelled by user');
      }
      
      debugPrint('Transcription error: ${e.message}');
      
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('Connection timeout. Please check your internet connection.');
      } else if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Server took too long to respond. Please try again.');
      } else if (e.response != null) {
        final detail = e.response!.data['detail'] ?? 'Transcription failed';
        throw Exception(detail);
      }
      
      throw Exception('Network error: ${e.message ?? 'Unknown error'}');
    } catch (e) {
      _currentCancelToken = null;
      throw Exception('Unexpected error: $e');
    }
  }

  /// Get transcription progress
  Future<Map<String, dynamic>> getProgress(String jobId) async {
    try {
      final response = await _dio.get('/progress/$jobId');
      return response.data;
    } catch (e) {
      debugPrint('Progress fetch error: $e');
      return {
        'status': 'unknown',
        'progress': 0,
        'message': 'Could not fetch progress'
      };
    }
  }

  /// Stream transcription progress updates
  Stream<Map<String, dynamic>> streamProgress(String jobId) async* {
    while (true) {
      try {
        final progress = await getProgress(jobId);
        yield progress;
        
        // Stop polling if completed or errored
        if (progress['status'] == 'completed' || progress['status'] == 'error') {
          break;
        }
        
        // Poll every 500ms
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('Progress stream error: $e');
        yield {
          'status': 'error',
          'progress': 0,
          'message': 'Connection lost'
        };
        break;
      }
    }
  }

  /// Generate subtitles (JSON response)
  Future<SubtitleResult> generateSubtitles(String filePath, {List<int>? fileBytes}) async {
    try {
      final fileName = filePath.split('/').last.split('\\').last;
      
      late FormData formData;
      if (kIsWeb && fileBytes != null) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: fileName),
        });
      }

      final response = await _dio.post(
        '/generate-subtitles-json',
        data: formData,
        onSendProgress: (sent, total) {
          debugPrint('Upload progress: ${(sent / total * 100).toStringAsFixed(0)}%');
        },
      );

      return SubtitleResult.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('Subtitle generation error: ${e.message}');
      if (e.response != null) {
        throw Exception(e.response!.data['detail'] ?? 'Subtitle generation failed');
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Download subtitle file (SRT or TXT)
  Future<void> downloadSubtitleFile(
    String filePath,
    String format,
    String savePath,
  ) async {
    try {
      final fileName = filePath.split('/').last.split('\\').last;
      
      late FormData formData;
      if (kIsWeb) {
        // On web, subtitle download isn't fully supported
        throw Exception('Subtitle file download is not supported on web');
      }
      formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'format': format,
      });

      await _dio.post(
        '/generate-subtitles',
        data: formData,
        options: Options(
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint('Download progress: ${(received / total * 100).toStringAsFixed(0)}%');
          }
        },
      ).then((response) {
        if (!kIsWeb) {
          final file = File(savePath);
          file.writeAsBytesSync(response.data);
          debugPrint('File saved to: $savePath');
        }
      });
    } on DioException catch (e) {
      debugPrint('Download error: ${e.message}');
      throw Exception('Failed to download subtitle file');
    }
  }

  /// Test connection to API (with wake-up handling for HuggingFace Spaces)
  Future<bool> testConnection() async {
    try {
      debugPrint('[API] Testing connection to: $baseUrl');
      
      final testDio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ));
      
      final response = await testDio.get('/health').timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          debugPrint('[API] Server might be sleeping, waking up...');
          throw TimeoutException('Server waking up');
        },
      );
      
      debugPrint('[API] Connection test response: ${response.statusCode}');
      return response.statusCode == 200;
    } on TimeoutException {
      // Server is likely sleeping, try one more time with longer timeout
      debugPrint('[API] Retrying connection (server may be waking up)...');
      try {
        final retryDio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 90),
        ));
        
        final response = await retryDio.get('/health').timeout(
          const Duration(seconds: 100),
        );
        
        debugPrint('[API] Server is now awake! ${response.statusCode}');
        return response.statusCode == 200;
      } catch (e) {
        debugPrint('[API] Connection failed after wake-up attempt: $e');
        return false;
      }
    } catch (e) {
      debugPrint('[API] Connection test failed: $e');
      return false;
    }
  }
  
  /// Wake up the server if it's sleeping (HuggingFace Spaces)
  Future<void> wakeUpServer() async {
    debugPrint('[API] Waking up server...');
    await testConnection();
  }
}
