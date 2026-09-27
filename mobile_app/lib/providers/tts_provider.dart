import 'package:flutter/foundation.dart';
import '../models/tts_result.dart';
import '../services/tts_api_service.dart';
import '../services/ocr_service.dart';
import '../services/notification_service.dart';

/// State management for TTS operations
class TtsProvider extends ChangeNotifier {
  final TtsApiService _apiService = TtsApiService();
  final OcrService _ocrService = OcrService();

  // ── State ──
  TtsModel _selectedModel = TtsModel.fishSpeechSingle;
  SpeakerInfo? _selectedSpeaker;
  int _pitchShift = 0;
  double _temperature = 0.6;
  double _repetitionPenalty = 1.1;
  bool _isProcessing = false;
  bool _isWakingUp = false;
  String _statusMessage = '';
  TtsResult? _lastResult;
  String? _errorMessage;
  final List<TtsResult> _history = [];

  // ── Getters ──
  TtsModel get selectedModel => _selectedModel;
  SpeakerInfo? get selectedSpeaker => _selectedSpeaker;
  int get pitchShift => _pitchShift;
  double get temperature => _temperature;
  double get repetitionPenalty => _repetitionPenalty;
  bool get isProcessing => _isProcessing;
  bool get isWakingUp => _isWakingUp;
  String get statusMessage => _statusMessage;
  TtsResult? get lastResult => _lastResult;
  String? get errorMessage => _errorMessage;
  List<TtsResult> get history => List.unmodifiable(_history);
  int get synthesisCount => _history.length;
  OcrService get ocrService => _ocrService;

  List<SpeakerInfo> get availableSpeakers => _selectedModel.speakers;

  TtsProvider() {
    _selectedSpeaker = _selectedModel.speakers.first;
  }

  /// Select a TTS model
  void selectModel(TtsModel model) {
    _selectedModel = model;
    _selectedSpeaker = model.speakers.first;
    _pitchShift = _selectedSpeaker?.defaultPitch ?? 0;
    _temperature = 0.6;
    _repetitionPenalty = 1.1;
    _lastResult = null;
    _statusMessage = '';
    _errorMessage = null;
    notifyListeners();
  }

  /// Select a speaker
  void selectSpeaker(SpeakerInfo speaker) {
    _selectedSpeaker = speaker;
    _pitchShift = speaker.defaultPitch;
    notifyListeners();
  }

  /// Set pitch shift
  void setPitchShift(int pitch) {
    _pitchShift = pitch;
    notifyListeners();
  }

  /// Set temperature (Fish Multi only)
  void setTemperature(double temp) {
    _temperature = temp;
    notifyListeners();
  }

  /// Set repetition penalty (Fish Multi only)
  void setRepetitionPenalty(double penalty) {
    _repetitionPenalty = penalty;
    notifyListeners();
  }

  /// Synthesize speech
  Future<void> synthesize(String text) async {
    if (text.trim().isEmpty) {
      _errorMessage = 'Please enter some text to synthesize';
      notifyListeners();
      return;
    }

    if (_selectedSpeaker == null) {
      _errorMessage = 'Please select a speaker';
      notifyListeners();
      return;
    }

    _isProcessing = true;
    _errorMessage = null;
    _statusMessage = 'Connecting to ${_selectedModel.shortName} server...';
    notifyListeners();

    try {
      // Check if space is awake
      _statusMessage = 'Checking server status...';
      notifyListeners();

      final isAlive = await _apiService.checkHealth(_selectedModel);
      if (!isAlive) {
        _isWakingUp = true;
        _statusMessage = 'Server is sleeping. Waking up (this may take 30-60s)...';
        notifyListeners();

        final woke = await _apiService.wakeUpSpace(_selectedModel);
        _isWakingUp = false;
        if (!woke) {
          throw Exception(
              '${_selectedModel.displayName} server could not be reached. '
              'Please try again in a moment.');
        }
      }

      _statusMessage = 'Generating speech with ${_selectedModel.shortName}...';
      notifyListeners();

      final result = await _apiService.synthesize(
        model: _selectedModel,
        text: text,
        speaker: _selectedSpeaker!.name,
        pitchShift: _pitchShift,
        temperature: _temperature,
        repetitionPenalty: _repetitionPenalty,
      );

      _lastResult = result;
      _history.insert(0, result);
      _statusMessage = 'Speech generated successfully!';
      _errorMessage = null;

      // 🔔 Notify user — works even if they left the screen
      await NotificationService.ttsDone();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _statusMessage = '';
      debugPrint('[TTS] Synthesis error: $e');

      // 🔔 Notify on error
      await NotificationService.taskError('Speech Generation', _errorMessage ?? 'Unknown error');
    } finally {
      _isProcessing = false;
      _isWakingUp = false;
      notifyListeners();
    }
  }

  /// Clear the last result
  void clearResult() {
    _lastResult = null;
    _statusMessage = '';
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    _apiService.cleanupTempFiles();
    super.dispose();
  }
}
