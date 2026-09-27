import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/tts_result.dart';

/// Unified TTS API service that calls all 3 Gradio-based HF Spaces
/// using the correct Gradio API format discovered from /info endpoints:
///
/// - Fish Speech Single: POST /api/synthesize  (named endpoint)
/// - VITS:               POST /run/predict     (unnamed, fn_index=1)
/// - Fish Speech Multi:  POST /api/synthesize  (named endpoint)
class TtsApiService {
  static const String _fishSingleBaseUrl =
      'https://hnde-afaan-oromoo-tts-single-speeker.hf.space';
  static const String _vitsBaseUrl =
      'https://hnde-afaan-oromoo-vits.hf.space';
  static const String _fishMultiBaseUrl =
      'https://hnde-afaan-oromoo-tts-multispeeker.hf.space';

  final Dio _dio;

  TtsApiService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(minutes: 3),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        )) {
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: false,
      error: true,
      logPrint: (obj) => debugPrint('[TTS-API] $obj'),
    ));
  }

  String _getBaseUrl(TtsModel model) {
    switch (model) {
      case TtsModel.fishSpeechSingle:
        return _fishSingleBaseUrl;
      case TtsModel.vits:
        return _vitsBaseUrl;
      case TtsModel.fishSpeechMulti:
        return _fishMultiBaseUrl;
    }
  }

  /// Check if a TTS Space is online
  Future<bool> checkHealth(TtsModel model) async {
    try {
      final response = await _dio.get('${_getBaseUrl(model)}/').timeout(
        const Duration(seconds: 30),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[TTS-API] Health check failed for ${model.displayName}: $e');
      return false;
    }
  }

  /// Wake up a sleeping HF Space
  Future<bool> wakeUpSpace(TtsModel model) async {
    debugPrint('[TTS-API] Waking up ${model.displayName}...');
    try {
      try {
        await _dio.get('${_getBaseUrl(model)}/').timeout(const Duration(seconds: 60));
        return true;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 5));
        final resp = await _dio.get('${_getBaseUrl(model)}/').timeout(const Duration(seconds: 90));
        return resp.statusCode == 200;
      }
    } catch (e) {
      debugPrint('[TTS-API] Wake-up failed: $e');
      return false;
    }
  }

  /// Synthesize speech — routes to the correct Gradio API for each model
  Future<TtsResult> synthesize({
    required TtsModel model,
    required String text,
    required String speaker,
    int pitchShift = 0,
    double temperature = 0.7,
    double repetitionPenalty = 1.2,
  }) async {
    final baseUrl = _getBaseUrl(model);
    debugPrint('[TTS-API] Synthesizing with ${model.displayName}');
    debugPrint('[TTS-API] Speaker: $speaker, Pitch: $pitchShift');

    try {
      Response response;

      if (model == TtsModel.vits) {
        // VITS: POST /run/predict with fn_index=2
        // fn_index=0 → load_example, fn_index=1 → get_speaker_description, fn_index=2 → synthesize
        // Params: [text, speaker_name, pitch_shift]
        response = await _dio.post(
          '$baseUrl/run/predict',
          data: jsonEncode({
            'data': [text, speaker, pitchShift],
            'fn_index': 2,
          }),
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
      } else if (model == TtsModel.fishSpeechMulti) {
        // Fish Multi uses Gradio 5 SSE v3 protocol:
        // Step 1: POST /gradio_api/call/synthesize → get event_id
        // Step 2: GET  /gradio_api/call/synthesize/{event_id} → SSE stream with result
        // Params: [text, dialect, temperature, repetition_penalty]
        final callResponse = await _dio.post(
          '$baseUrl/gradio_api/call/synthesize',
          data: jsonEncode({
            'data': [text, speaker, temperature, repetitionPenalty],
          }),
          options: Options(headers: {'Content-Type': 'application/json'}),
        );

        final eventId = callResponse.data is Map
            ? callResponse.data['event_id']
            : jsonDecode(callResponse.data.toString())['event_id'];
        debugPrint('[TTS-API] Fish Multi event_id: $eventId');

        // Poll for result via SSE endpoint
        final resultResponse = await _dio.get(
          '$baseUrl/gradio_api/call/synthesize/$eventId',
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(minutes: 5),
          ),
        );

        // Parse SSE response — look for "data:" lines with JSON
        final sseBody = resultResponse.data.toString();
        debugPrint('[TTS-API] SSE response length: ${sseBody.length}');
        final dataLines = sseBody.split('\n')
            .where((line) => line.startsWith('data: '))
            .map((line) => line.substring(6).trim())
            .toList();

        // The last data line with JSON array is the result
        Map<String, dynamic>? resultData;
        for (final line in dataLines.reversed) {
          try {
            final parsed = jsonDecode(line);
            if (parsed is List) {
              resultData = {'data': parsed};
              break;
            }
          } catch (_) {}
        }

        if (resultData == null) {
          // Check for error in SSE
          for (final line in dataLines) {
            if (line.contains('error') || line.contains('Error')) {
              throw Exception('Fish Multi synthesis failed: $line');
            }
          }
          throw Exception('No result received from Fish Multi server');
        }

        return await _parseGradioResponse(
          responseData: resultData,
          text: text,
          model: model,
          speaker: speaker,
          baseUrl: baseUrl,
        );
      } else {
        // Fish Speech Single uses named endpoint → POST /api/synthesize
        // Params: [text, speaker_name, pitch_shift, temperature, repetition_penalty]
        response = await _dio.post(
          '$baseUrl/api/synthesize',
          data: jsonEncode({
            'data': [text, speaker, pitchShift, temperature, repetitionPenalty],
          }),
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
      }

      debugPrint('[TTS-API] Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('TTS API returned status ${response.statusCode}');
      }

      return await _parseGradioResponse(
        responseData: response.data,
        text: text,
        model: model,
        speaker: speaker,
        baseUrl: baseUrl,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception(
            'The ${model.displayName} server is taking too long. '
            'It may be waking up from sleep. Please try again in 30 seconds.');
      }
      if (e.response?.statusCode == 503) {
        throw Exception(
            '${model.displayName} is currently starting up. '
            'Please wait a moment and try again.');
      }
      if (e.response?.statusCode == 500) {
        throw Exception(
            '${model.displayName} returned a server error. '
            'The model may still be loading. Please try again.');
      }
      throw Exception('Network error: ${e.message ?? 'Connection failed'}');
    }
  }

  /// Parse the Gradio API response and save audio to local file
  /// Gradio returns: {"data": [{"url": "...", "path": "..."}, ...]}
  Future<TtsResult> _parseGradioResponse({
    required dynamic responseData,
    required String text,
    required TtsModel model,
    required String speaker,
    required String baseUrl,
  }) async {
    String? audioPath;
    String? originalAudioPath;

    if (responseData is Map<String, dynamic>) {
      final data = responseData['data'];
      if (data is List && data.isNotEmpty) {
        // Gradio returns audio components as objects with url/path
        for (int i = 0; i < data.length; i++) {
          final item = data[i];
          String? filePath;

          if (item is Map<String, dynamic>) {
            if (item.containsKey('path') && item['path'] != null) {
              // Gradio 5 SSE often returns proxy paths in 'url' (e.g. /grad/gradio_api/) which cause 308 redirects.
              // We construct the direct /file= URL using the absolute path on the server.
              String path = item['path'] as String;
              String url = '$baseUrl/file=$path';
              
              if (kIsWeb) {
                filePath = url; // On web, use URL directly for just_audio
              } else {
                filePath = await _downloadAudioFile(url, i);
              }
            } else if (item.containsKey('url') && item['url'] != null) {
              // Fallback for older Gradio versions
              String url = item['url'] as String;
              if (!url.startsWith('http')) {
                url = '$baseUrl$url';
              }
              // Clean up known buggy proxy paths
              url = url.replaceAll('/grad/gradio_api/', '/').replaceAll('/gradio_api/', '/');
              if (kIsWeb) {
                filePath = url; // On web, use URL directly for just_audio
              } else {
                filePath = await _downloadAudioFile(url, i);
              }
            } else if (item.containsKey('path') && item['path'] != null) {
              // Audio returned as server-side path — download via /file=
              final serverPath = item['path'] as String;
              final fullUrl = '$baseUrl/file=$serverPath';
              if (kIsWeb) {
                filePath = fullUrl; // On web, use URL directly
              } else {
                filePath = await _downloadAudioFile(fullUrl, i);
              }
            } else if (item.containsKey('data') && item['data'] is String) {
              // Base64 encoded audio
              if (kIsWeb) {
                // On web, create a data URI for just_audio
                final audioData = item['data'] as String;
                if (audioData.startsWith('data:')) {
                  filePath = audioData;
                } else {
                  filePath = 'data:audio/wav;base64,$audioData';
                }
              } else {
                final audioData = item['data'] as String;
                final base64Str = audioData.contains(',')
                    ? audioData.split(',').last
                    : audioData;
                final bytes = base64Decode(base64Str);
                final dir = await _getTempDir();
                filePath = '$dir/tts_${DateTime.now().millisecondsSinceEpoch}_$i.wav';
                await File(filePath).writeAsBytes(bytes);
              }
            }
          } else if (item is List && item.length >= 2) {
            // Numpy audio format: [sample_rate, [samples...]]
            // VITS returns this format — convert to WAV for playback
            try {
              final sampleRate = (item[0] is int) ? item[0] as int : (item[0] as num).toInt();
              final samplesRaw = item[1];
              if (samplesRaw is List) {
                final samples = samplesRaw.map((s) => (s as num).toDouble()).toList();
                debugPrint('[TTS-API] Numpy audio: ${samples.length} samples @ ${sampleRate}Hz');
                
                if (kIsWeb) {
                  // On web, encode as WAV data URI
                  final wavBytes = _encodeWav(samples, sampleRate);
                  final b64 = base64Encode(wavBytes);
                  filePath = 'data:audio/wav;base64,$b64';
                } else {
                  // On native, save as WAV file
                  final wavBytes = _encodeWav(samples, sampleRate);
                  final dir = await _getTempDir();
                  filePath = '$dir/tts_${DateTime.now().millisecondsSinceEpoch}_$i.wav';
                  await File(filePath!).writeAsBytes(wavBytes);
                }
              }
            } catch (e) {
              debugPrint('[TTS-API] Numpy parse error: $e');
            }
          } else if (item is String && item.isNotEmpty) {
            // Pipeline status text — ignore for audio
            debugPrint('[TTS-API] Pipeline status: $item');
          }

          if (filePath != null) {
            if (audioPath == null) {
              audioPath = filePath;
            } else if (originalAudioPath == null) {
              originalAudioPath = filePath;
            }
          }
        }
      }
    }

    if (audioPath == null) {
      throw Exception(
          'Could not extract audio from ${model.displayName} response. '
          'The server may have returned an unexpected format.');
    }

    return TtsResult(
      audioPath: audioPath,
      originalAudioPath: originalAudioPath,
      text: text,
      modelName: model.displayName,
      speaker: speaker,
    );
  }

  /// Download an audio file from URL
  Future<String> _downloadAudioFile(String url, int index) async {
    debugPrint('[TTS-API] Downloading audio from: $url');
    final dir = await _getTempDir();
    final savePath = '$dir/tts_${DateTime.now().millisecondsSinceEpoch}_$index.wav';

    try {
      final response = await _dio.download(url, savePath);
      if (response.statusCode == 200) {
        debugPrint('[TTS-API] Audio saved: $savePath');
        return savePath;
      }
      throw Exception('Download failed: status ${response.statusCode}');
    } catch (e) {
      debugPrint('[TTS-API] Download error: $e');
      throw Exception('Failed to download audio file');
    }
  }

  Future<String> _getTempDir() async {
    if (kIsWeb) {
      return '/tmp';
    }
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  /// Encode float audio samples as a 16-bit PCM WAV file
  List<int> _encodeWav(List<double> samples, int sampleRate) {
    final numSamples = samples.length;
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final fileSize = 44 + dataSize;
    
    final buffer = ByteData(fileSize);
    
    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize - 8, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E
    
    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // chunk size
    buffer.setUint16(20, 1, Endian.little);  // PCM format
    buffer.setUint16(22, 1, Endian.little);  // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little);  // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    
    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);
    
    // Write samples as 16-bit signed integers
    for (int i = 0; i < numSamples; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final intVal = (clamped * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, intVal, Endian.little);
    }
    
    return buffer.buffer.asUint8List();
  }

  /// Cleanup old TTS temp files
  Future<void> cleanupTempFiles() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('tts_')) {
          final age = DateTime.now().difference(file.lastModifiedSync());
          if (age.inHours > 1) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('[TTS-API] Cleanup error: $e');
    }
  }
}
