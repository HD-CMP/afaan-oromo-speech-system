import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../models/subtitle_result.dart';
import '../services/export_service.dart';

class SubtitlePlayerWidget extends StatefulWidget {
  final String filePath;
  final List<SubtitleSegment> segments;
  final String fullText;
  final String srtContent;

  const SubtitlePlayerWidget({
    super.key,
    required this.filePath,
    required this.segments,
    required this.fullText,
    required this.srtContent,
  });

  @override
  State<SubtitlePlayerWidget> createState() => _SubtitlePlayerWidgetState();
}

class _SubtitlePlayerWidgetState extends State<SubtitlePlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isInitialized = false;
  double _playbackSpeed = 1.0;
  int _activeSubtitleIndex = -1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _audioPlayer = AudioPlayer();
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        debugPrint('[SubtitlePlayer] File does not exist: ${widget.filePath}');
        return;
      }
      
      await _audioPlayer.setFilePath(widget.filePath);
      
      _audioPlayer.positionStream.listen((position) {
        _updateActiveSubtitle(position);
      });
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[SubtitlePlayer] Initialization error: $e');
    }
  }

  void _updateActiveSubtitle(Duration position) {
    final seconds = position.inMilliseconds / 1000.0;
    int newIndex = -1;
    
    for (int i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      if (seconds >= segment.start && seconds <= segment.end) {
        newIndex = i;
        break;
      }
    }
    
    if (newIndex != _activeSubtitleIndex) {
      setState(() {
        _activeSubtitleIndex = newIndex;
      });
      
      if (newIndex >= 0 && _scrollController.hasClients) {
        final itemHeight = 100.0;
        final targetPosition = newIndex * itemHeight;
        final screenHeight = _scrollController.position.viewportDimension;
        final currentScroll = _scrollController.offset;
        final itemTop = targetPosition;
        final itemBottom = targetPosition + itemHeight;
        
        if (itemBottom > currentScroll + screenHeight || itemTop < currentScroll) {
          _scrollController.animateTo(
            targetPosition - (screenHeight / 2) + (itemHeight / 2),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  void _seekToSubtitle(int index) {
    if (index >= 0 && index < widget.segments.length) {
      final segment = widget.segments[index];
      final position = Duration(milliseconds: (segment.start * 1000).round());
      _audioPlayer.seek(position);
      if (!_audioPlayer.playing) {
        _audioPlayer.play();
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
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

  Future<void> _downloadSrtFile() async {
    if (!mounted) return;
    
    final fileName = File(widget.filePath).path.split('/').last.split('.').first;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final suggestedFileName = 'subtitle_${fileName}_$timestamp.srt';
    
    await _showDownloadOptions(
      content: widget.srtContent,
      suggestedFileName: suggestedFileName,
      fileType: 'SRT',
    );
  }

  Future<void> _downloadTxtFile() async {
    if (!mounted) return;
    
    final fileName = File(widget.filePath).path.split('/').last.split('.').first;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final suggestedFileName = 'subtitle_${fileName}_$timestamp.txt';
    
    await _showDownloadOptions(
      content: widget.fullText,
      suggestedFileName: suggestedFileName,
      fileType: 'TXT',
    );
  }
  
  Future<void> _showDownloadOptions({
    required String content,
    required String suggestedFileName,
    required String fileType,
  }) async {
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_rounded, color: AppColors.primaryColor),
                const SizedBox(width: 12),
                Text(
                  'Download $fileType File',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.save_alt, color: Colors.blue.shade700),
              ),
              title: const Text('Save to Device'),
              subtitle: const Text('Choose where to save on your device'),
              onTap: () async {
                Navigator.pop(context);
                await _saveToUserLocation(content, suggestedFileName, fileType);
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.folder, color: Colors.green.shade700),
              ),
              title: const Text('Quick Save'),
              subtitle: const Text('Save to app folder'),
              onTap: () async {
                Navigator.pop(context);
                await _quickSave(content, suggestedFileName, fileType);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveToUserLocation(String content, String fileName, String fileType) async {
    try {
      // Use file picker to let user choose save location
      final exportService = ExportService();
      final savedPath = await exportService.saveFileWithPicker(content, fileName);
      
      if (savedPath == null) {
        // User cancelled
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save cancelled'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fileType saved successfully!'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => _shareFile(savedPath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _quickSave(String content, String fileName, String fileType) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fileType saved to app folder'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => _shareFile(file.path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareFile(String filePath) async {
    try {
      final file = XFile(filePath);
      await Share.shareXFiles([file], subject: 'Oromo Subtitle');
    } catch (e) {
      debugPrint('[Share] Error: $e');
    }
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.paddingLG,
            vertical: AppConstants.paddingMD,
          ),
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
                      File(widget.filePath).path.split('/').last,
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
                      SizedBox(
                        height: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(50, (index) {
                              final height = 12.0 + (index % 7) * 3.5;
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      
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
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
        ),
        
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.download_rounded, color: AppColors.primaryColor, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Download Subtitles',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _downloadSrtFile,
                      icon: const Icon(Icons.subtitles_outlined, size: 16),
                      label: const Text('SRT', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _downloadTxtFile,
                      icon: const Icon(Icons.text_snippet_outlined, size: 16),
                      label: const Text('TXT', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          builder: (context, snapshot) {
            SubtitleSegment? currentSubtitle;
            if (_activeSubtitleIndex >= 0 && _activeSubtitleIndex < widget.segments.length) {
              currentSubtitle = widget.segments[_activeSubtitleIndex];
            }
            
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor.withOpacity(0.1),
                    AppColors.primaryGradientEnd.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: currentSubtitle != null 
                      ? AppColors.primaryColor 
                      : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current Subtitle',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (currentSubtitle != null)
                        Text(
                          '#${_activeSubtitleIndex + 1}/${widget.segments.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    currentSubtitle?.text ?? 'Press play to start',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: currentSubtitle != null 
                          ? Colors.black87 
                          : Colors.grey.shade400,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (currentSubtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      currentSubtitle.timeRange,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        
        const SizedBox(height: 12),
        
        Container(
          constraints: const BoxConstraints(
            minHeight: 200,
            maxHeight: 500,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.subtitles, color: AppColors.primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      'All Subtitle Segments',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.segments.length} segments',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: widget.segments.length,
                  itemBuilder: (context, index) {
                      final segment = widget.segments[index];
                      final isActive = index == _activeSubtitleIndex;
                      
                      return InkWell(
                        onTap: () => _seekToSubtitle(index),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isActive 
                                ? AppColors.primaryColor.withOpacity(0.15)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive 
                                  ? AppColors.primaryColor 
                                  : Colors.grey.shade300,
                              width: isActive ? 2 : 1,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: AppColors.primaryColor.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive 
                                          ? AppColors.primaryColor 
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '#${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: isActive 
                                            ? Colors.white 
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (isActive)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: AppColors.primaryGradient,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'PLAYING',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        segment.timeRange,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isActive 
                                              ? AppColors.primaryColor 
                                              : Colors.grey.shade600,
                                          fontFamily: 'monospace',
                                          fontWeight: isActive 
                                              ? FontWeight.bold 
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                segment.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isActive 
                                      ? Colors.black87 
                                      : Colors.black54,
                                  fontWeight: isActive 
                                      ? FontWeight.w600 
                                      : FontWeight.normal,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
