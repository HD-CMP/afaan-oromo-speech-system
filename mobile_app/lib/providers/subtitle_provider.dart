import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'dart:io';
import '../models/subtitle_result.dart';
import '../models/transcription_history.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';
import '../services/notification_service.dart';

enum SubtitleStatus {
  idle,
  uploading,
  processing,
  completed,
  error,
}

class SubtitleProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final HistoryService _historyService = HistoryService();
  
  SubtitleStatus _status = SubtitleStatus.idle;
  SubtitleResult? _result;
  String? _errorMessage;
  String? _currentFilePath;
  int? _fileSize;
  double? _fileDuration;

  SubtitleStatus get status => _status;
  SubtitleResult? get result => _result;
  String? get errorMessage => _errorMessage;
  String? get currentFilePath => _currentFilePath;

  bool get isProcessing =>
      _status == SubtitleStatus.uploading ||
      _status == SubtitleStatus.processing;

  /// Generate subtitles from audio/video file
  Future<void> generateSubtitles(String filePath, {List<int>? fileBytes}) async {
    try {
      _status = SubtitleStatus.uploading;
      _currentFilePath = filePath;
      _errorMessage = null;
      
      // Get file information
      if (!kIsWeb) {
        final file = File(filePath);
        if (await file.exists()) {
          _fileSize = await file.length();
        }
      } else {
        _fileSize = fileBytes?.length;
      }
      
      notifyListeners();

      // Simulate upload phase
      await Future.delayed(const Duration(milliseconds: 500));
      
      _status = SubtitleStatus.processing;
      notifyListeners();

      // Call API
      _result = await _apiService.generateSubtitles(filePath, fileBytes: fileBytes);
      
      _status = SubtitleStatus.completed;
      notifyListeners();

      // 🔔 Notify user — works even if they left the screen
      final fileName = _currentFilePath?.split('/').last;
      await NotificationService.subtitleDone(fileName);

      // Save to history
      await saveToHistory();
    } catch (e) {
      _status = SubtitleStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      debugPrint('Subtitle generation error: $e');

      // 🔔 Notify on error
      await NotificationService.taskError('Subtitle Generation', _errorMessage ?? 'Unknown error');
    }
  }
  
  /// Save subtitle to history
  Future<void> saveToHistory() async {
    if (_result == null || _currentFilePath == null) return;
    
    try {
      final fileName = _result!.metadata.filename.isNotEmpty
          ? _result!.metadata.filename
          : _currentFilePath!.split('/').last;
      
      final wordCount = _result!.fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final characterCount = _result!.fullText.length;
      
      // Calculate duration from last segment
      double? duration;
      if (_result!.segments.isNotEmpty) {
        duration = _result!.segments.last.end;
      }
      
      final historyItem = TranscriptionHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: fileName,
        text: _result!.fullText,
        wordCount: wordCount,
        characterCount: characterCount,
        timestamp: DateTime.now(),
        filePath: _currentFilePath,
        duration: duration,
        fileSize: _fileSize,
        type: TranscriptionType.subtitle,
      );
      
      await _historyService.addToHistory(historyItem);
      debugPrint('[SubtitleProvider] Saved to history: ${historyItem.id}');
    } catch (e) {
      debugPrint('[SubtitleProvider] Error saving to history: $e');
    }
  }

  /// Download subtitle file
  Future<void> downloadSubtitleFile(
    String filePath,
    String format,
    String savePath,
  ) async {
    try {
      await _apiService.downloadSubtitleFile(filePath, format, savePath);
    } catch (e) {
      debugPrint('Download error: $e');
      rethrow;
    }
  }

  /// Reset state
  void reset() {
    _status = SubtitleStatus.idle;
    _result = null;
    _errorMessage = null;
    _currentFilePath = null;
    notifyListeners();
  }

  void updateConfiguration() {
    debugPrint('[SubtitleProvider] Updating API service configuration...');
    _apiService.updateBaseUrl();
  }
}
