import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import 'dart:io' if (dart.library.html) 'dart:io';
import '../config/app_colors.dart';
import '../config/app_constants.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String filePath;
  final bool showWaveform;

  const AudioPlayerWidget({
    super.key,
    required this.filePath,
    this.showWaveform = true,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isInitialized = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _audioPlayer = AudioPlayer();
    try {
      if (kIsWeb || widget.filePath.startsWith('http://') || widget.filePath.startsWith('https://')) {
        // On web or for URLs, use setUrl
        await _audioPlayer.setUrl(widget.filePath);
      } else {
        // On native, check file exists and use setFilePath
        final file = File(widget.filePath);
        if (!await file.exists()) {
          debugPrint('[AudioPlayer] File does not exist: ${widget.filePath}');
          return;
        }
        await _audioPlayer.setFilePath(widget.filePath);
      }
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[AudioPlayer] Initialization error: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _changeSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed == 2.0) {
        _playbackSpeed = 0.5;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    _audioPlayer.setSpeed(_playbackSpeed);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.audiotrack, color: AppColors.primaryColor, size: 24),
              const SizedBox(width: AppConstants.paddingSM),
              Expanded(
                child: Text(
                  widget.filePath.split('/').last.split('\\').last,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.paddingMD),
          
          // Waveform visualization (simplified with progress bar)
          StreamBuilder<Duration>(
            stream: _audioPlayer.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = _audioPlayer.duration ?? Duration.zero;
              final progress = duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0;

              return Column(
                children: [
                  // Custom waveform-style progress
                  SizedBox(
                    height: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          // Background bars
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(50, (index) {
                              final height = 20.0 + (index % 7) * 5.0;
                              final isPlayed = (index / 50) <= progress;
                              return Container(
                                width: 3,
                                height: height,
                                decoration: BoxDecoration(
                                  gradient: isPlayed
                                      ? AppColors.primaryGradient
                                      : LinearGradient(
                                          colors: [
                                            Colors.grey.shade300,
                                            Colors.grey.shade400,
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.paddingSM),
                  
                  // Seek slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: AppColors.primaryColor,
                      inactiveTrackColor: Colors.grey.shade300,
                      thumbColor: AppColors.primaryColor,
                      overlayColor: AppColors.primaryColor.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: duration.inMilliseconds > 0
                          ? position.inMilliseconds.toDouble().clamp(
                              0.0,
                              duration.inMilliseconds.toDouble(),
                            )
                          : 0.0,
                      min: 0,
                      max: duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: (value) {
                        _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  
                  // Time labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          
          const SizedBox(height: AppConstants.paddingMD),
          
          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10 seconds
              IconButton(
                icon: const Icon(Icons.replay_10_rounded),
                iconSize: 32,
                color: AppColors.primaryColor,
                onPressed: () {
                  final newPosition = _audioPlayer.position - const Duration(seconds: 10);
                  _audioPlayer.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
                },
              ),
              
              const SizedBox(width: AppConstants.paddingMD),
              
              // Play/Pause button
              StreamBuilder<PlayerState>(
                stream: _audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final playerState = snapshot.data;
                  final isPlaying = playerState?.playing ?? false;
                  final processingState = playerState?.processingState;

                  return Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        processingState == ProcessingState.loading ||
                                processingState == ProcessingState.buffering
                            ? Icons.hourglass_empty_rounded
                            : isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                      ),
                      iconSize: 40,
                      color: Colors.white,
                      onPressed: () {
                        if (isPlaying) {
                          _audioPlayer.pause();
                        } else {
                          _audioPlayer.play();
                        }
                      },
                    ),
                  );
                },
              ),
              
              const SizedBox(width: AppConstants.paddingMD),
              
              // Forward 10 seconds
              IconButton(
                icon: const Icon(Icons.forward_10_rounded),
                iconSize: 32,
                color: AppColors.primaryColor,
                onPressed: () {
                  final duration = _audioPlayer.duration ?? Duration.zero;
                  final newPosition = _audioPlayer.position + const Duration(seconds: 10);
                  _audioPlayer.seek(newPosition > duration ? duration : newPosition);
                },
              ),
              
              const SizedBox(width: AppConstants.paddingLG),
              
              // Speed button
              InkWell(
                onTap: _changeSpeed,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 18,
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_playbackSpeed}x',
                        style: TextStyle(
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
