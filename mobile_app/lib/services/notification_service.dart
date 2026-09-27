import 'package:flutter/services.dart';

/// Shows native Android notifications via Kotlin MethodChannel.
/// No extra packages needed — uses Android NotificationManager directly.
class NotificationService {
  static const _channel = MethodChannel('com.afaanoromo.stt/notifications');

  // Notification IDs
  static const int _idTranscription = 1001;
  static const int _idTts          = 1002;
  static const int _idSubtitle     = 1003;
  static const int _idError        = 1004;

  /// Call once at app startup to create the notification channel on Android.
  static Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
    } catch (_) {
      // Graceful degradation — notifications just won't show if channel fails
    }
  }

  /// Notify that speech transcription completed successfully.
  static Future<void> transcriptionDone(String? fileName) async {
    await _show(
      id: _idTranscription,
      title: '🎙️ Transcription Complete',
      body: fileName != null
          ? '"$fileName" has been transcribed. Tap to view.'
          : 'Your Afaan Oromoo transcription is ready. Tap to view.',
    );
  }

  /// Notify that TTS speech generation completed.
  static Future<void> ttsDone() async {
    await _show(
      id: _idTts,
      title: '🔊 Speech Generated',
      body: 'Your Afaan Oromoo audio is ready to play.',
    );
  }

  /// Notify that subtitle generation completed.
  static Future<void> subtitleDone(String? fileName) async {
    await _show(
      id: _idSubtitle,
      title: '📝 Subtitles Ready',
      body: fileName != null
          ? 'Subtitles for "$fileName" are ready. Tap to view.'
          : 'Your subtitle file (SRT) is ready. Tap to view.',
    );
  }

  /// Notify on a processing error.
  static Future<void> taskError(String taskName, String message) async {
    await _show(
      id: _idError,
      title: '⚠️ $taskName Failed',
      body: message.length > 80 ? '${message.substring(0, 80)}...' : message,
    );
  }

  // ── Internal helper ────────────────────────────────────────────────────────
  static Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'id':    id,
        'title': title,
        'body':  body,
      });
    } catch (e) {
      // Notifications are optional — never crash the app for them
    }
  }
}
