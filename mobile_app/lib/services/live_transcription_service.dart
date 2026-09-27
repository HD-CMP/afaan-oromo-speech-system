import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

enum LiveTranscriptionStatus {
  idle,
  connecting,
  connected,
  transcribing,
  error,
  disconnected,
}

class LiveTranscriptionResult {
  final String text;
  final bool isPartial;
  final int? chunkNumber;

  LiveTranscriptionResult({
    required this.text,
    required this.isPartial,
    this.chunkNumber,
  });
}

class LiveTranscriptionService {
  WebSocketChannel? _channel;
  final StreamController<LiveTranscriptionResult> _transcriptionController =
      StreamController<LiveTranscriptionResult>.broadcast();
  final StreamController<LiveTranscriptionStatus> _statusController =
      StreamController<LiveTranscriptionStatus>.broadcast();

  LiveTranscriptionStatus _status = LiveTranscriptionStatus.idle;
  String _fullTranscription = '';

  Stream<LiveTranscriptionResult> get transcriptionStream =>
      _transcriptionController.stream;
  Stream<LiveTranscriptionStatus> get statusStream => _statusController.stream;
  LiveTranscriptionStatus get status => _status;
  String get fullTranscription => _fullTranscription;

  void _updateStatus(LiveTranscriptionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  Future<bool> connect() async {
    try {
      _updateStatus(LiveTranscriptionStatus.connecting);
      debugPrint('[LiveTranscription] Connecting to WebSocket...');

      final wsUrl = 'ws://${ApiConfig.serverIp}:${ApiConfig.serverPort}/live-transcribe';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      await _channel!.ready;

      _updateStatus(LiveTranscriptionStatus.connected);
      debugPrint('[LiveTranscription] Connected successfully');

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          debugPrint('[LiveTranscription] WebSocket error: $error');
          _updateStatus(LiveTranscriptionStatus.error);
        },
        onDone: () {
          debugPrint('[LiveTranscription] WebSocket closed');
          _updateStatus(LiveTranscriptionStatus.disconnected);
        },
      );

      return true;
    } catch (e) {
      debugPrint('[LiveTranscription] Connection error: $e');
      _updateStatus(LiveTranscriptionStatus.error);
      return false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = json.decode(message);
      final type = data['type'];

      if (type == 'partial') {
        final text = data['text'] ?? '';
        _fullTranscription = text;
        _transcriptionController.add(LiveTranscriptionResult(
          text: text,
          isPartial: true,
          chunkNumber: data['chunk'],
        ));
        _updateStatus(LiveTranscriptionStatus.transcribing);
      } else if (type == 'final') {
        final text = data['text'] ?? '';
        _fullTranscription = text;
        _transcriptionController.add(LiveTranscriptionResult(
          text: text,
          isPartial: false,
        ));
      } else if (type == 'error') {
        debugPrint('[LiveTranscription] Server error: ${data['message']}');
        _updateStatus(LiveTranscriptionStatus.error);
      }
    } catch (e) {
      debugPrint('[LiveTranscription] Error handling message: $e');
    }
  }

  void sendAudioChunk(Uint8List audioData) {
    if (_channel != null && _status == LiveTranscriptionStatus.connected) {
      try {
        _channel!.sink.add(audioData);
        debugPrint('[LiveTranscription] Sent audio chunk: ${audioData.length} bytes');
      } catch (e) {
        debugPrint('[LiveTranscription] Error sending audio: $e');
        _updateStatus(LiveTranscriptionStatus.error);
      }
    }
  }

  void sendEndSignal() {
    if (_channel != null) {
      try {
        _channel!.sink.add('END');
        debugPrint('[LiveTranscription] Sent END signal');
      } catch (e) {
        debugPrint('[LiveTranscription] Error sending END: $e');
      }
    }
  }

  void resetTranscription() {
    _fullTranscription = '';
  }

  Future<void> disconnect() async {
    debugPrint('[LiveTranscription] Disconnecting...');
    await _channel?.sink.close();
    _channel = null;
    _updateStatus(LiveTranscriptionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _transcriptionController.close();
    _statusController.close();
  }
}
