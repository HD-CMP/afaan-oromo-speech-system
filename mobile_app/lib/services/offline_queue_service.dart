import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import '../models/transcription_result.dart';

enum QueueItemStatus {
  pending,
  processing,
  completed,
  failed,
}

enum QueueItemType {
  transcription,
  subtitle,
}

class QueueItem {
  final String id;
  final String filePath;
  final QueueItemType type;
  QueueItemStatus status;
  DateTime createdAt;
  DateTime? processedAt;
  String? errorMessage;
  dynamic result;
  int retryCount;

  QueueItem({
    required this.id,
    required this.filePath,
    required this.type,
    this.status = QueueItemStatus.pending,
    DateTime? createdAt,
    this.processedAt,
    this.errorMessage,
    this.result,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'type': type.toString(),
        'status': status.toString(),
        'createdAt': createdAt.toIso8601String(),
        'processedAt': processedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'retryCount': retryCount,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'],
      filePath: json['filePath'],
      type: QueueItemType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => QueueItemType.transcription,
      ),
      status: QueueItemStatus.values.firstWhere(
        (e) => e.toString() == json['status'],
        orElse: () => QueueItemStatus.pending,
      ),
      createdAt: DateTime.parse(json['createdAt']),
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'])
          : null,
      errorMessage: json['errorMessage'],
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

class OfflineQueueService {
  static const String _queueKey = 'offline_queue';
  static const String _queueDirKey = 'queue_files';
  static const int maxQueueSize = 50;
  static const int maxRetries = 3;
  static const Duration processingInterval = Duration(seconds: 30);

  final ApiService _apiService;
  final List<QueueItem> _queue = [];
  Timer? _processingTimer;
  bool _isProcessing = false;
  bool _isOnline = false;

  final _queueUpdateController = StreamController<List<QueueItem>>.broadcast();
  Stream<List<QueueItem>> get queueUpdates => _queueUpdateController.stream;

  OfflineQueueService(this._apiService) {
    _loadQueue();
    _startProcessingTimer();
  }

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_queueKey);

      if (queueJson != null) {
        final List<dynamic> decoded = jsonDecode(queueJson);
        _queue.clear();
        _queue.addAll(decoded.map((item) => QueueItem.fromJson(item)));
        debugPrint('[Queue] Loaded ${_queue.length} items from storage');
        _queueUpdateController.add(_queue);
      }
    } catch (e) {
      debugPrint('[Queue] Error loading queue: $e');
    }
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = jsonEncode(_queue.map((item) => item.toJson()).toList());
      await prefs.setString(_queueKey, queueJson);
      _queueUpdateController.add(_queue);
    } catch (e) {
      debugPrint('[Queue] Error saving queue: $e');
    }
  }

  void _startProcessingTimer() {
    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(processingInterval, (_) {
      if (!_isProcessing) {
        _processQueue();
      }
    });
  }

  Future<String> _copyFileToQueue(String originalPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final queueDir = Directory('${directory.path}/$_queueDirKey');
      
      if (!await queueDir.exists()) {
        await queueDir.create(recursive: true);
      }

      final originalFile = File(originalPath);
      final fileName = originalPath.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${queueDir.path}/${timestamp}_$fileName';
      
      await originalFile.copy(newPath);
      return newPath;
    } catch (e) {
      debugPrint('[Queue] Error copying file: $e');
      return originalPath;
    }
  }

  Future<bool> addToQueue({
    required String filePath,
    required QueueItemType type,
  }) async {
    if (_queue.length >= maxQueueSize) {
      debugPrint('[Queue] Queue is full (max $maxQueueSize items)');
      return false;
    }

    try {
      final queuedFilePath = await _copyFileToQueue(filePath);
      
      final item = QueueItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: queuedFilePath,
        type: type,
      );

      _queue.add(item);
      await _saveQueue();

      debugPrint('[Queue] Added item ${item.id} to queue (${_queue.length} total)');
      
      if (_isOnline && !_isProcessing) {
        _processQueue();
      }

      return true;
    } catch (e) {
      debugPrint('[Queue] Error adding to queue: $e');
      return false;
    }
  }

  Future<void> setOnlineStatus(bool isOnline) async {
    final wasOffline = !_isOnline;
    _isOnline = isOnline;

    debugPrint('[Queue] Network status: ${isOnline ? 'ONLINE' : 'OFFLINE'}');

    if (isOnline && wasOffline && _queue.isNotEmpty && !_isProcessing) {
      debugPrint('[Queue] Back online, processing queue...');
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || !_isOnline || _queue.isEmpty) {
      return;
    }

    _isProcessing = true;
    debugPrint('[Queue] Processing queue (${_queue.length} items)');

    final pendingItems = _queue
        .where((item) =>
            item.status == QueueItemStatus.pending ||
            (item.status == QueueItemStatus.failed && item.retryCount < maxRetries))
        .toList();

    for (final item in pendingItems) {
      if (!_isOnline) {
        debugPrint('[Queue] Lost connection, stopping queue processing');
        break;
      }

      await _processItem(item);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessing = false;
    debugPrint('[Queue] Queue processing completed');
  }

  Future<void> _processItem(QueueItem item) async {
    try {
      item.status = QueueItemStatus.processing;
      await _saveQueue();

      debugPrint('[Queue] Processing item ${item.id} (${item.type})');

      if (item.type == QueueItemType.transcription) {
        final result = await _apiService.transcribeAudio(item.filePath);
        item.result = result;
        item.status = QueueItemStatus.completed;
      } else if (item.type == QueueItemType.subtitle) {
        final result = await _apiService.generateSubtitles(item.filePath);
        item.result = result;
        item.status = QueueItemStatus.completed;
      }

      item.processedAt = DateTime.now();
      item.errorMessage = null;
      
      await _deleteQueuedFile(item.filePath);

      debugPrint('[Queue] Item ${item.id} completed successfully');
    } catch (e) {
      item.retryCount++;
      
      if (item.retryCount >= maxRetries) {
        item.status = QueueItemStatus.failed;
        item.errorMessage = 'Max retries exceeded: ${e.toString()}';
        debugPrint('[Queue] Item ${item.id} failed after $maxRetries retries');
      } else {
        item.status = QueueItemStatus.pending;
        item.errorMessage = e.toString();
        debugPrint('[Queue] Item ${item.id} failed, will retry (${item.retryCount}/$maxRetries)');
      }
    }

    await _saveQueue();
  }

  Future<void> _deleteQueuedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[Queue] Deleted queued file: $filePath');
      }
    } catch (e) {
      debugPrint('[Queue] Error deleting file: $e');
    }
  }

  Future<void> removeItem(String itemId) async {
    final item = _queue.firstWhere((item) => item.id == itemId);
    await _deleteQueuedFile(item.filePath);
    _queue.removeWhere((item) => item.id == itemId);
    await _saveQueue();
    debugPrint('[Queue] Removed item $itemId');
  }

  Future<void> clearCompleted() async {
    final completedItems = _queue.where((item) => item.status == QueueItemStatus.completed).toList();
    
    for (final item in completedItems) {
      await _deleteQueuedFile(item.filePath);
    }
    
    _queue.removeWhere((item) => item.status == QueueItemStatus.completed);
    await _saveQueue();
    debugPrint('[Queue] Cleared ${completedItems.length} completed items');
  }

  Future<void> retryFailed() async {
    final failedItems = _queue.where((item) => item.status == QueueItemStatus.failed).toList();
    
    for (final item in failedItems) {
      item.status = QueueItemStatus.pending;
      item.retryCount = 0;
      item.errorMessage = null;
    }

    await _saveQueue();
    debugPrint('[Queue] Retrying ${failedItems.length} failed items');
    
    if (_isOnline && !_isProcessing) {
      _processQueue();
    }
  }

  List<QueueItem> getQueueItems() => List.unmodifiable(_queue);

  int get pendingCount =>
      _queue.where((item) => item.status == QueueItemStatus.pending).length;

  int get completedCount =>
      _queue.where((item) => item.status == QueueItemStatus.completed).length;

  int get failedCount =>
      _queue.where((item) => item.status == QueueItemStatus.failed).length;

  void dispose() {
    _processingTimer?.cancel();
    _queueUpdateController.close();
  }
}
