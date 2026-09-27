import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/transcription_result.dart';
import '../models/transcription_history.dart';
import '../services/api_service.dart';
import '../services/history_service.dart';

enum TranscriptionStatus {
  idle,
  uploading,
  processing,
  completed,
  error,
  queued,
}

class QueuedRequest {
  final String id;
  final String filePath;
  final String fileName;
  final DateTime timestamp;
  
  QueuedRequest({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'fileName': fileName,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory QueuedRequest.fromJson(Map<String, dynamic> json) => QueuedRequest(
    id: json['id'],
    filePath: json['filePath'],
    fileName: json['fileName'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class TranscriptionProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final HistoryService _historyService = HistoryService();
  
  TranscriptionStatus _status = TranscriptionStatus.idle;
  TranscriptionResult? _result;
  String? _errorMessage;
  String? _currentFilePath;
  List<QueuedRequest> _queuedRequests = [];
  
  // Progress tracking
  int _uploadProgress = 0;
  int _processingProgress = 0;
  String _progressMessage = '';
  
  // File metadata
  String? _fileName;
  int? _fileSize;
  double? _fileDuration;
  
  // History
  List<TranscriptionHistory> _history = [];

  TranscriptionStatus get status => _status;
  TranscriptionResult? get result => _result;
  String? get errorMessage => _errorMessage;
  String? get currentFilePath => _currentFilePath;
  List<QueuedRequest> get queuedRequests => _queuedRequests;
  int get uploadProgress => _uploadProgress;
  int get processingProgress => _processingProgress;
  String get progressMessage => _progressMessage;
  String? get fileName => _fileName;
  int? get fileSize => _fileSize;
  double? get fileDuration => _fileDuration;
  List<TranscriptionHistory> get history => _history;
  HistoryService get historyService => _historyService;

  bool get isProcessing =>
      _status == TranscriptionStatus.uploading ||
      _status == TranscriptionStatus.processing;
  
  bool get canCancel => isProcessing;
  bool get hasQueuedRequests => _queuedRequests.isNotEmpty;

  Future<void> initialize() async {
    await loadHistory();
    await _loadQueuedRequests();
  }

  void updateConfiguration() {
    debugPrint('[TranscriptionProvider] Updating API service configuration...');
    _apiService.updateBaseUrl();
  }
  
  Future<void> _loadQueuedRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('transcription_queue');
      if (queueJson != null) {
        final List<dynamic> queueList = json.decode(queueJson);
        _queuedRequests = queueList
            .map((item) => QueuedRequest.fromJson(item))
            .toList();
        notifyListeners();
        debugPrint('[Provider] Loaded ${_queuedRequests.length} queued requests');
      }
    } catch (e) {
      debugPrint('[Provider] Error loading queue: $e');
    }
  }
  
  Future<void> _saveQueuedRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = json.encode(_queuedRequests.map((r) => r.toJson()).toList());
      await prefs.setString('transcription_queue', queueJson);
    } catch (e) {
      debugPrint('[Provider] Error saving queue: $e');
    }
  }
  
  Future<void> loadHistory({TranscriptionType? type}) async {
    try {
      _history = await _historyService.getHistory(type: type);
      notifyListeners();
      debugPrint('[Provider] Loaded ${_history.length} history items');
    } catch (e) {
      debugPrint('[Provider] Error loading history: $e');
    }
  }
  
  Future<void> saveToHistory({TranscriptionType type = TranscriptionType.transcription}) async {
    if (_result == null || _fileName == null) return;
    
    try {
      final historyItem = TranscriptionHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: _fileName!,
        text: _result!.text,
        wordCount: _result!.metadata.wordCount,
        characterCount: _result!.metadata.characterCount,
        timestamp: DateTime.now(),
        filePath: _currentFilePath,
        duration: _fileDuration,
        fileSize: _fileSize,
        type: type,
      );
      
      await _historyService.addToHistory(historyItem);
      await loadHistory();
      debugPrint('[Provider] Saved to history: ${historyItem.id}');
    } catch (e) {
      debugPrint('[Provider] Error saving to history: $e');
    }
  }
  
  List<TranscriptionHistory> getHistoryByType(TranscriptionType type) {
    return _history.where((item) => item.type == type).toList();
  }
  
  int get unreadCount {
    return _history.where((item) => !item.isRead).length;
  }
  
  Future<void> markAsRead(String id) async {
    try {
      final index = _history.indexWhere((item) => item.id == id);
      if (index != -1 && !_history[index].isRead) {
        final updatedItem = _history[index].copyWith(isRead: true);
        _history[index] = updatedItem;
        await _historyService.updateHistoryItem(updatedItem);
        notifyListeners();
        debugPrint('[Provider] Marked history item as read: $id');
      }
    } catch (e) {
      debugPrint('[Provider] Error marking history item as read: $e');
    }
  }
  
  Future<void> markAllAsRead() async {
    try {
      for (var i = 0; i < _history.length; i++) {
        if (!_history[i].isRead) {
          _history[i] = _history[i].copyWith(isRead: true);
          await _historyService.updateHistoryItem(_history[i]);
        }
      }
      notifyListeners();
      debugPrint('[Provider] Marked all history items as read');
    } catch (e) {
      debugPrint('[Provider] Error marking all history items as read: $e');
    }
  }
  
  Future<void> deleteHistoryItem(String id) async {
    try {
      await _historyService.deleteHistoryItem(id);
      await loadHistory();
      debugPrint('[Provider] Deleted history item: $id');
    } catch (e) {
      debugPrint('[Provider] Error deleting history item: $e');
    }
  }
  
  Future<void> clearHistory() async {
    try {
      await _historyService.clearHistory();
      _history = [];
      notifyListeners();
      debugPrint('[Provider] Cleared history');
    } catch (e) {
      debugPrint('[Provider] Error clearing history: $e');
    }
  }
  
  void cancelTranscription() {
    if (!canCancel) return;
    
    debugPrint('[Provider] Cancelling transcription...');
    _apiService.cancelCurrentRequest();
    _status = TranscriptionStatus.error;
    _errorMessage = 'Transcription cancelled by user';
    _progressMessage = 'Cancelled';
    notifyListeners();
  }
  
  Future<void> _processQueue() async {
    if (_queuedRequests.isEmpty || isProcessing) return;
    
    final isConnected = await testConnection();
    if (!isConnected) {
      debugPrint('[Provider] No connection, queue processing postponed');
      return;
    }
    
    while (_queuedRequests.isNotEmpty && !isProcessing) {
      final request = _queuedRequests.first;
      debugPrint('[Provider] Processing queued request: ${request.fileName}');
      
      try {
        await transcribeAudio(request.filePath);
        _queuedRequests.removeAt(0);
        await _saveQueuedRequests();
      } catch (e) {
        debugPrint('[Provider] Failed to process queued request: $e');
        break;
      }
    }
  }
  
  Future<void> _addToQueue(String filePath, String fileName) async {
    // Check if file is already in queue to prevent duplicates
    final alreadyQueued = _queuedRequests.any((req) => req.filePath == filePath);
    if (alreadyQueued) {
      debugPrint('[Provider] File already in queue, skipping: $fileName');
      return;
    }
    
    final request = QueuedRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filePath: filePath,
      fileName: fileName,
      timestamp: DateTime.now(),
    );
    
    _queuedRequests.add(request);
    await _saveQueuedRequests();
    _status = TranscriptionStatus.queued;
    _progressMessage = 'Queued for processing (${_queuedRequests.length} in queue)';
    notifyListeners();
    debugPrint('[Provider] Added to queue: $fileName');
  }

  Future<void> transcribeAudio(String filePath, {List<int>? fileBytes}) async {
    // Prevent duplicate transcriptions
    if (isProcessing) {
      debugPrint('[Provider] Already processing, ignoring duplicate request');
      return;
    }
    
    try {
      _currentFilePath = filePath;
      _errorMessage = null;
      _uploadProgress = 0;
      _processingProgress = 0;
      
      if (kIsWeb) {
        _fileName = filePath.split('/').last.split('\\').last;
        _fileSize = fileBytes?.length;
      } else {
        final file = File(filePath);
        _fileName = file.path.split('/').last;
        _fileSize = await file.length();
      }
      
      debugPrint('[Provider] File: $_fileName (${((_fileSize ?? 0) / 1024).toStringAsFixed(2)} KB)');

      _status = TranscriptionStatus.uploading;
      _progressMessage = 'Uploading file...';
      notifyListeners();

      debugPrint('[Provider] Using API transcription');
      
      _result = await _apiService.transcribeAudio(
        filePath,
        fileBytes: fileBytes,
        onUploadProgress: (sent, total) {
          _uploadProgress = ((sent / total) * 100).round();
          _progressMessage = 'Uploading: $_uploadProgress%';
          notifyListeners();
        },
      );
      
      if (_result?.metadata.duration != null) {
        _fileDuration = _result!.metadata.duration;
      }
      
      if (_result?.jobId != null) {
        final jobId = _result!.jobId!;
        _status = TranscriptionStatus.processing;
        _progressMessage = 'Processing audio...';
        notifyListeners();
        
        await for (final progress in _apiService.streamProgress(jobId)) {
          _processingProgress = (progress['progress'] ?? 0).toInt();
          _progressMessage = progress['message'] ?? 'Processing...';
          debugPrint('[Provider] Progress: $_processingProgress% - $_progressMessage');
          
          if (progress['status'] == 'completed') {
            break;
          } else if (progress['status'] == 'error') {
            throw Exception(progress['message'] ?? 'Processing failed');
          }
          
          notifyListeners();
        }
      }
      
      _status = TranscriptionStatus.completed;
      _progressMessage = 'Completed!';
      _processingProgress = 100;
      notifyListeners();
      
      await saveToHistory();
    } catch (e) {
      _status = TranscriptionStatus.error;
      _errorMessage = e.toString();
      _progressMessage = 'Error occurred';
      notifyListeners();
      debugPrint('Transcription error: $e');
      
      // Add to queue for manual retry if connection error
      if (e.toString().contains('connection') || 
          e.toString().contains('timeout') || 
          e.toString().contains('network')) {
        await _addToQueue(filePath, _fileName!);
      }
    }
  }
  
  /// Retry a queued transcription
  Future<void> retryQueuedItem(String queueId) async {
    final request = _queuedRequests.firstWhere((r) => r.id == queueId);
    _queuedRequests.removeWhere((r) => r.id == queueId);
    await _saveQueuedRequests();
    await transcribeAudio(request.filePath);
  }
  
  /// Clear entire queue
  Future<void> clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('transcription_queue');
      _queuedRequests.clear();
      notifyListeners();
      debugPrint('[Provider] Cleared queue');
    } catch (e) {
      debugPrint('[Provider] Error clearing queue: $e');
    }
  }
  
  /// Remove single item from queue
  Future<void> removeFromQueue(String queueId) async {
    _queuedRequests.removeWhere((r) => r.id == queueId);
    await _saveQueuedRequests();
    notifyListeners();
  }

  /// Update result text
  void updateResultText(String newText) {
    if (_result != null) {
      final updatedMetadata = TranscriptionMetadata(
        wordCount: newText.trim().isEmpty ? 0 : newText.trim().split(RegExp(r'\s+')).length,
        characterCount: newText.length,
        filename: _result!.metadata.filename,
        timestamp: _result!.metadata.timestamp,
        processingTime: _result!.metadata.processingTime,
        duration: _result!.metadata.duration,
        fileSize: _result!.metadata.fileSize,
      );
      
      _result = _result!.copyWith(
        text: newText,
        metadata: updatedMetadata,
      );
      notifyListeners();
    }
  }

  /// Reset state
  void reset() {
    _status = TranscriptionStatus.idle;
    _result = null;
    _errorMessage = null;
    _currentFilePath = null;
    _uploadProgress = 0;
    _processingProgress = 0;
    _progressMessage = '';
    _fileName = null;
    _fileSize = null;
    _fileDuration = null;
    notifyListeners();
  }

  /// Test API connection
  Future<bool> testConnection() async {
    try {
      return await _apiService.testConnection();
    } catch (e) {
      debugPrint('Connection test error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
