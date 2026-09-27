import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:typed_data';
import '../services/live_transcription_service.dart';
import '../providers/transcription_provider.dart';
import '../providers/localization_provider.dart';
import '../models/transcription_history.dart';
import '../widgets/connection_status_indicator.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../widgets/custom_snackbar.dart';

class LiveTranscriptionScreen extends StatefulWidget {
  const LiveTranscriptionScreen({super.key});

  @override
  State<LiveTranscriptionScreen> createState() => _LiveTranscriptionScreenState();
}

class _LiveTranscriptionScreenState extends State<LiveTranscriptionScreen>
    with SingleTickerProviderStateMixin {
  final LiveTranscriptionService _liveService = LiveTranscriptionService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isStreaming = false;
  String _currentTranscription = '';
  Duration _streamingDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _audioStreamTimer;
  late AnimationController _pulseController;
  LiveTranscriptionStatus _connectionStatus = LiveTranscriptionStatus.idle;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _liveService.transcriptionStream.listen((result) {
      if (mounted) {
        setState(() {
          _currentTranscription = result.text;
        });
      }
    });

    _liveService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
        });
      }
    });
  }

  @override
  void dispose() {
    _stopStreaming();
    _liveService.dispose();
    _audioRecorder.dispose();
    _pulseController.dispose();
    _durationTimer?.cancel();
    _audioStreamTimer?.cancel();
    super.dispose();
  }

  Future<bool> _checkPermissions() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('microphone_permission_required'),
          type: SnackBarType.error,
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _startStreaming() async {
    if (!await _checkPermissions()) return;

    try {
      final connected = await _liveService.connect();
      if (!connected) {
        if (mounted) {
          final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
          CustomSnackBar.show(
            context,
            message: localizationProvider.getString('failed_to_connect'),
            type: SnackBarType.error,
          );
        }
        return;
      }

      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      setState(() {
        _isStreaming = true;
        _currentTranscription = '';
        _streamingDuration = Duration.zero;
      });

      _startDurationTimer();

      stream.listen(
        (audioChunk) {
          if (_isStreaming) {
            final bytes = Uint8List.fromList(audioChunk);
            _liveService.sendAudioChunk(bytes);
          }
        },
        onError: (error) {
          debugPrint('[LiveTranscription] Stream error: $error');
          _stopStreaming();
        },
        onDone: () {
          debugPrint('[LiveTranscription] Stream done');
        },
      );

      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('live_transcription_started'),
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      debugPrint('[LiveTranscription] Error starting: $e');
      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: '${localizationProvider.getString('failed_to_start')}: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isStreaming) {
        setState(() {
          _streamingDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> _stopStreaming() async {
    if (!_isStreaming) return;

    try {
      await _audioRecorder.stop();
      _liveService.sendEndSignal();
      _durationTimer?.cancel();

      setState(() {
        _isStreaming = false;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (_currentTranscription.isNotEmpty) {
        await _saveToHistory();
      }

      await _liveService.disconnect();

      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('live_transcription_stopped'),
          type: SnackBarType.info,
        );
      }
    } catch (e) {
      debugPrint('[LiveTranscription] Error stopping: $e');
    }
  }

  Future<void> _saveToHistory() async {
    try {
      final provider = Provider.of<TranscriptionProvider>(context, listen: false);

      final historyItem = TranscriptionHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fileName: 'Live Session ${DateTime.now().toString().substring(0, 19)}',
        text: _currentTranscription,
        wordCount: _currentTranscription.split(' ').length,
        characterCount: _currentTranscription.length,
        timestamp: DateTime.now(),
        duration: _streamingDuration.inSeconds.toDouble(),
        type: TranscriptionType.live,
      );

      await provider.historyService.addToHistory(historyItem);
      await provider.loadHistory();

      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('saved_to_history'),
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      debugPrint('[LiveTranscription] Error saving to history: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Color _getStatusColor() {
    switch (_connectionStatus) {
      case LiveTranscriptionStatus.connected:
      case LiveTranscriptionStatus.transcribing:
        return Colors.green;
      case LiveTranscriptionStatus.connecting:
        return Colors.orange;
      case LiveTranscriptionStatus.error:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (_connectionStatus) {
      case LiveTranscriptionStatus.connected:
        return 'Connected';
      case LiveTranscriptionStatus.connecting:
        return 'Connecting...';
      case LiveTranscriptionStatus.transcribing:
        return 'Transcribing...';
      case LiveTranscriptionStatus.error:
        return 'Connection Error';
      case LiveTranscriptionStatus.disconnected:
        return 'Disconnected';
      default:
        return 'Idle';
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizationProvider = Provider.of<LocalizationProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(localizationProvider.getString('live_transcription')),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: ConnectionStatusIndicator(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: _getStatusColor().withOpacity(0.1),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingLG),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getStatusColor(),
                        boxShadow: [
                          BoxShadow(
                            color: _getStatusColor().withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _getStatusText(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: AppColors.primaryColor.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingLG),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isStreaming
                            ? 'Speak now - your speech is being transcribed in real-time'
                            : 'Tap the microphone to start real-time transcription',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return GestureDetector(
                        onTap: _isStreaming ? _stopStreaming : _startStreaming,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _isStreaming
                                ? LinearGradient(
                                    colors: [Colors.red.shade400, Colors.red.shade700],
                                  )
                                : AppColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: (_isStreaming ? Colors.red : AppColors.primaryColor)
                                    .withOpacity(0.4 + (0.2 * _pulseController.value)),
                                blurRadius: 30 + (15 * _pulseController.value),
                                spreadRadius: 8 + (8 * _pulseController.value),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isStreaming ? Icons.stop : Icons.mic,
                            size: 70,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isStreaming 
                      ? Provider.of<LocalizationProvider>(context, listen: false).getString('tap_to_stop')
                      : Provider.of<LocalizationProvider>(context, listen: false).getString('tap_to_start'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isStreaming) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatDuration(_streamingDuration),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),
            if (_currentTranscription.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingXL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: AppColors.successGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.record_voice_over,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            Provider.of<LocalizationProvider>(context, listen: false).getString('live_transcription_title'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.red.shade200, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  Provider.of<LocalizationProvider>(context, listen: false).getString('live_badge'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.successGradient.colors.first.withOpacity(0.1),
                              AppColors.successGradient.colors.first.withOpacity(0.3),
                              AppColors.successGradient.colors.first.withOpacity(0.1),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        constraints: const BoxConstraints(minHeight: 120),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: SelectableText(
                          _currentTranscription,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.9,
                            color: Color(0xFF2C2C2C),
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildInfoChip(
                            Icons.text_fields,
                            '${_currentTranscription.split(' ').length} words',
                          ),
                          const SizedBox(width: 8),
                          _buildInfoChip(
                            Icons.abc,
                            '${_currentTranscription.length} chars',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
