import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/transcription_provider.dart';
import '../providers/localization_provider.dart';
import '../services/export_service.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../widgets/gradient_button.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/connection_status_indicator.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> with SingleTickerProviderStateMixin {
  final ExportService _exportService = ExportService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _textEditController = TextEditingController();
  bool _isRecording = false;
  String? _recordingPath;
  bool _isEditing = false;
  String _searchQuery = '';
  late AnimationController _recordingAnimController;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _recordingAnimController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _recordingAnimController.dispose();
    _searchController.dispose();
    _textEditController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }
  
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: kIsWeb, // load bytes on web
      );

      if (result != null && result.files.single.name.isNotEmpty) {
        final file = result.files.single;
        final filePath = file.path ?? file.name;
        if (!context.mounted) return;
        
        // Clear previous transcription before uploading new file
        final provider = Provider.of<TranscriptionProvider>(context, listen: false);
        provider.reset();
        
        await provider.transcribeAudio(filePath, fileBytes: file.bytes);
      }
    } catch (e) {
      if (!context.mounted) return;
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, '${localizationProvider.getString('error_picking_file')}: $e', Colors.red);
    }
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<bool> _checkPermissions() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        _showSnackBar(context, localizationProvider.getString('microphone_permission_required'), Colors.red);
      }
      return false;
    }
    return true;
  }

  Future<void> _toggleRecording(BuildContext context) async {
    if (_isRecording) {
      await _stopRecording(context);
    } else {
      await _startRecording(context);
    }
  }

  Future<void> _startRecording(BuildContext context) async {
    if (!await _checkPermissions()) return;

    try {
      // Clear previous transcription before starting new recording
      final provider = Provider.of<TranscriptionProvider>(context, listen: false);
      provider.reset();
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${directory.path}/recording_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
        ),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      
      // Start timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
      
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('recording_started'), Colors.green);
    } catch (e) {
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('failed_to_start_recording'), Colors.red);
    }
  }

  Future<void> _stopRecording(BuildContext context) async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      setState(() => _isRecording = false);

      if (path != null && mounted) {
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        _showSnackBar(context, localizationProvider.getString('processing_transcription'), Colors.blue);
        final provider = Provider.of<TranscriptionProvider>(context, listen: false);
        await provider.transcribeAudio(path);
      }
    } catch (e) {
      _recordingTimer?.cancel();
      setState(() => _isRecording = false);
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('failed_to_stop_recording'), Colors.red);
    }
  }

  void _toggleEditMode(String initialText) {
    setState(() {
      _isEditing = !_isEditing;
      if (_isEditing) {
        _textEditController.text = initialText;
      }
    });
  }

  void _saveEditedText() {
    final provider = Provider.of<TranscriptionProvider>(context, listen: false);
    if (provider.result != null) {
      provider.updateResultText(_textEditController.text);
      setState(() => _isEditing = false);
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('text_updated'), Colors.green);
    }
  }

  int _readingTime(String text) {
    final wordCount = text.split(' ').length;
    return (wordCount / 200).ceil(); // Average reading speed: 200 words/min
  }
  
  void _showExportOptions(String text) {
    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
    
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
                  localizationProvider.getString('export_btn'),
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
                await _exportToUserLocation(text);
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
                await _quickExport(text);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _exportToUserLocation(String text) async {
    try {
      final fileName = 'transcription_${DateTime.now().millisecondsSinceEpoch}.txt';
      final savedPath = await _exportService.saveFileWithPicker(text, fileName);
      
      if (savedPath == null) {
        // User cancelled
        _showSnackBar(context, 'Save cancelled', Colors.grey);
        return;
      }
      
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, '${localizationProvider.getString('saved_file')}: $savedPath', Colors.green);
    } catch (e) {
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('export_failed'), Colors.red);
    }
  }
  
  Future<void> _quickExport(String text) async {
    try {
      final fileName = 'transcription_${DateTime.now().millisecondsSinceEpoch}';
      final filePath = await _exportService.exportToText(text, fileName);
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, '${localizationProvider.getString('saved_file')}: $filePath', Colors.green);
    } catch (e) {
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      _showSnackBar(context, localizationProvider.getString('export_failed'), Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizationProvider = Provider.of<LocalizationProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(localizationProvider.getString('instant_transcription')),
        elevation: 0,
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: ConnectionStatusIndicator(),
          ),
          Consumer<TranscriptionProvider>(
            builder: (context, provider, _) {
              if (provider.status == TranscriptionStatus.completed) {
                return IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    provider.reset();
                    setState(() {
                      _isEditing = false;
                      _searchQuery = '';
                      _textEditController.clear();
                      _searchController.clear();
                    });
                  },
                  tooltip: 'Start New',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<TranscriptionProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              const ConnectionStatusBanner(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.paddingLG),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUploadRecordCard(provider),
                const SizedBox(height: AppConstants.paddingLG),
                
                if (provider.isProcessing || provider.fileName != null)
                  _buildProcessingCard(provider),
                
                if (provider.status == TranscriptionStatus.error)
                  _buildErrorCard(provider),
                
                if (provider.hasQueuedRequests)
                  ...[
                    const SizedBox(height: AppConstants.paddingLG),
                    _buildQueueCard(provider),
                  ],
                
                if (provider.status == TranscriptionStatus.completed && provider.result != null)
                  ..._buildResultSection(provider),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadRecordCard(TranscriptionProvider provider) {
    final locProv = Provider.of<LocalizationProvider>(context, listen: false);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _recordingAnimController,
              builder: (context, child) {
                return Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isRecording
                        ? const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)])
                        : AppColors.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording
                                ? AppColors.error
                                : AppColors.primary)
                            .withOpacity(
                                0.25 + (0.2 * _recordingAnimController.value)),
                        blurRadius:
                            18 + (10 * _recordingAnimController.value),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic_rounded : Icons.upload_file_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              _isRecording
                  ? locProv.getString('recording_in_progress_title')
                  : locProv.getString('upload_or_record_audio'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_isRecording)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: AppColors.error.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.error,
                      ),
                    )
                        .animate(
                            onPlay: (c) => c.repeat(reverse: true))
                        .fade(begin: 1.0, end: 0.2, duration: 600.ms),
                    const SizedBox(width: 10),
                    Text(
                      _formatDuration(_recordingSeconds),
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                locProv.getString('choose_existing_file'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 22),
            if (!_isRecording) ...
              [
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        onPressed: provider.isProcessing
                            ? null
                            : () => _pickFile(context),
                        gradient: AppColors.primaryGradient,
                        icon: Icons.folder_open_rounded,
                        label: locProv.getString('choose_file_btn'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GradientButton(
                        onPressed: provider.isProcessing
                            ? null
                            : () => _toggleRecording(context),
                        gradient: AppColors.emeraldGradient,
                        icon: Icons.mic_rounded,
                        label: locProv.getString('record_btn'),
                      ),
                    ),
                  ],
                ),
              ]
            else ...
              [
                GradientButton(
                  onPressed: () => _stopRecording(context),
                  gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                  icon: Icons.stop_rounded,
                  label: locProv.getString('stop_recording_btn'),
                ),
              ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.08, end: 0);
  }

  Widget _buildProcessingCard(TranscriptionProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (provider.fileName != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentIndigo.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.audio_file_rounded,
                        color: AppColors.accentIndigo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.fileName!,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (provider.fileSize != null)
                              _buildMetaChip(
                                '${(provider.fileSize! / 1024).toStringAsFixed(1)} KB',
                                Icons.storage_rounded,
                              ),
                            if (provider.fileDuration != null) ...[
                              const SizedBox(width: 8),
                              _buildMetaChip(
                                '${provider.fileDuration!.toStringAsFixed(1)}s',
                                Icons.timer_rounded,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.borderSubtle, height: 1),
              const SizedBox(height: 16),
            ],

            if (provider.isProcessing) ...[
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.progressMessage.isEmpty
                              ? (provider.status ==
                                      TranscriptionStatus.uploading
                                  ? 'Uploading audio…'
                                  : 'Processing transcription…')
                              : provider.progressMessage,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        if (provider.status ==
                                TranscriptionStatus.uploading &&
                            provider.uploadProgress > 0)
                          _buildProgressBar(
                              provider.uploadProgress / 100,
                              '${provider.uploadProgress}% uploaded',
                              AppColors.primary)
                        else if (provider.status ==
                                TranscriptionStatus.processing &&
                            provider.processingProgress > 0)
                          _buildProgressBar(
                              provider.processingProgress / 100,
                              '${provider.processingProgress}% processed',
                              AppColors.accentIndigo),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.accentIndigo.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accentIndigo.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.accentIndigo),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Processing may take a few moments. Please be patient.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.canCancel) ...[
                const SizedBox(height: 12),
                GradientButton(
                  onPressed: () => provider.cancelTranscription(),
                  gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                  icon: Icons.cancel_rounded,
                  label: 'Cancel',
                ),
              ],
            ],
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).scale(
        begin: const Offset(0.97, 0.97), end: const Offset(1, 1));
  }

  Widget _buildProgressBar(double value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: AppColors.surface3,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildMetaChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(TranscriptionProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.errorGlow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 52),
            const SizedBox(height: 12),
            Text(
              Provider.of<LocalizationProvider>(context, listen: false)
                  .getString('transcription_failed_title'),
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text(
              provider.errorMessage ?? 'Unknown error occurred',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GradientButton(
              onPressed: () => provider.reset(),
              gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
              icon: Icons.refresh_rounded,
              label: 'Try Again',
            ),
          ],
        ),
      ),
    ).animate().shake(duration: 500.ms);
  }

  List<Widget> _buildResultSection(TranscriptionProvider provider) {
    final result = provider.result!;
    final text = result.text;
    final wordCount = text.split(' ').length;
    final charCount = text.length;
    final readingTime = _readingTime(text);

    return [
      // Audio player
      if (provider.currentFilePath != null) ...[
        AudioPlayerWidget(filePath: provider.currentFilePath!).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
        const SizedBox(height: AppConstants.paddingLG),
      ],
      
      // Warning message for long audio
      if (result.warning != null) ...[
        Container(
          padding: const EdgeInsets.all(AppConstants.paddingLG),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
            border: Border.all(color: Colors.orange.shade300, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.warning!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: AppConstants.paddingLG),
      ],
      
      _buildStatsCard(wordCount, charCount, readingTime, provider),
      const SizedBox(height: AppConstants.paddingLG),
      _buildActionsCard(text),
      const SizedBox(height: AppConstants.paddingLG),
      _buildTranscriptionCard(text),
    ];
  }

  Widget _buildStatsCard(int words, int chars, int readTime, TranscriptionProvider provider) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingXL),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 32),
                const SizedBox(width: 8),
                Text(
                  Provider.of<LocalizationProvider>(context, listen: false).getString('transcription_complete_title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingLG),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem(Icons.text_fields, '$words', 'Words', Colors.white),
                _buildStatItem(Icons.format_size, '$chars', 'Characters', Colors.white),
                _buildStatItem(Icons.schedule, '$readTime min', 'Read Time', Colors.white),
              ],
            ),
            const SizedBox(height: AppConstants.paddingMD),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Processed in ${(provider.result!.processingTime ?? 0).toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsCard(String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Provider.of<LocalizationProvider>(context, listen: false).getString('actions'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppConstants.paddingMD),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionChip(
                  icon: Icons.copy,
                  label: Provider.of<LocalizationProvider>(context, listen: false).getString('copy_btn'),
                  color: Colors.blue,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
                    _showSnackBar(context, localizationProvider.getString('copied_to_clipboard'), Colors.green);
                  },
                ),
                _buildActionChip(
                  icon: Icons.share,
                  label: Provider.of<LocalizationProvider>(context, listen: false).getString('share_btn'),
                  color: Colors.purple,
                  onTap: () async {
                    try {
                      await _exportService.shareText(text, subject: 'Afaan Oromo Transcription');
                    } catch (e) {
                      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
                      _showSnackBar(context, localizationProvider.getString('share_failed'), Colors.red);
                    }
                  },
                ),
                _buildActionChip(
                  icon: Icons.download,
                  label: Provider.of<LocalizationProvider>(context, listen: false).getString('export_btn'),
                  color: Colors.orange,
                  onTap: () => _showExportOptions(text),
                ),
                _buildActionChip(
                  icon: _isEditing ? Icons.save : Icons.edit,
                  label: _isEditing 
                    ? Provider.of<LocalizationProvider>(context, listen: false).getString('save_btn')
                    : Provider.of<LocalizationProvider>(context, listen: false).getString('edit_btn'),
                  color: Colors.teal,
                  onTap: () {
                    if (_isEditing) {
                      _saveEditedText();
                    } else {
                      _toggleEditMode(text);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.1, end: 0);
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.8), color],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptionCard(String text) {
    return Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.article_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Provider.of<LocalizationProvider>(context, listen: false).getString('transcription_header'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                if (!_isEditing)
                  IconButton(
                    icon: Icon(
                      _searchQuery.isEmpty ? Icons.search : Icons.close,
                      color: AppColors.primaryColor,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_searchQuery.isNotEmpty) {
                          _searchQuery = '';
                          _searchController.clear();
                        }
                      });
                    },
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor.withOpacity(0.1),
                    AppColors.primaryColor.withOpacity(0.3),
                    AppColors.primaryColor.withOpacity(0.1),
                  ],
                ),
              ),
            ),
            
            if (_searchQuery.isNotEmpty && !_isEditing) ...[
              const SizedBox(height: AppConstants.paddingMD),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search in transcription...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ],
            
            const SizedBox(height: 20),
            
            if (_isEditing)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryColor.withOpacity(0.3), width: 2),
                ),
                child: TextField(
                  controller: _textEditController,
                  maxLines: null,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: Color(0xFF2C2C2C),
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(20),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(minHeight: 200, maxHeight: 600),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.blue.shade50.withOpacity(0.3),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryColor.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryColor.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 8,
                      offset: const Offset(-4, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SelectableText(
                    _highlightSearchQuery(text),
                    style: const TextStyle(
                      fontSize: 17,
                      height: 2.0,
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1, end: 0);
  }

  String _highlightSearchQuery(String text) {
    if (_searchQuery.isEmpty) return text;
    return text; // In a real implementation, you'd use RichText to highlight matches
  }
  
  Widget _buildQueueCard(TranscriptionProvider provider) {
    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.orange.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.queue, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Queued Files',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${provider.queuedRequests.length} file(s) waiting',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(localizationProvider.getString('clear_queue_title')),
                      content: Text(localizationProvider.getString('clear_queue_message')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(localizationProvider.getString('cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(localizationProvider.getString('clear')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await provider.clearQueue();
                  }
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(localizationProvider.getString('clear')),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...provider.queuedRequests.map((request) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.pending, color: Colors.orange.shade600, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.fileName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Queued ${_formatQueueTime(request.timestamp)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.primaryColor),
                  tooltip: 'Retry Now',
                  onPressed: provider.isProcessing 
                    ? null 
                    : () => provider.retryQueuedItem(request.id),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red.shade400),
                  tooltip: 'Remove',
                  onPressed: () => provider.removeFromQueue(request.id),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
  
  String _formatQueueTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
