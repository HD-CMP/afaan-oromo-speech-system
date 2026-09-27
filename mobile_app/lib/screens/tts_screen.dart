import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../models/tts_result.dart';
import '../providers/tts_provider.dart';
import '../services/ocr_service.dart';

class TtsScreen extends StatefulWidget {
  final TtsModel initialModel;

  const TtsScreen({super.key, required this.initialModel});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _originalAudioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isPlayingOriginal = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _loadedAudioPath;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Set the model on the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TtsProvider>().selectModel(widget.initialModel);
    });

    _audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _audioPlayer.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
            _audioPlayer.seek(Duration.zero);
            _audioPlayer.pause();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    _originalAudioPlayer.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _buildAppBar(provider),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingLG),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildModelInfoBadge(provider),
                      const SizedBox(height: AppConstants.paddingLG),
                      _buildTextInput(provider),
                      const SizedBox(height: AppConstants.paddingLG),
                      _buildSpeakerSelector(provider),
                      const SizedBox(height: AppConstants.paddingMD),
                      if (provider.selectedModel == TtsModel.fishSpeechSingle) ...[
                        _buildPitchSlider(provider),
                        const SizedBox(height: AppConstants.paddingMD),
                        _buildTemperatureSlider(provider),
                        const SizedBox(height: AppConstants.paddingMD),
                        _buildRepetitionSlider(provider),
                      ] else if (provider.selectedModel == TtsModel.fishSpeechMulti) ...[
                        _buildTemperatureSlider(provider),
                        const SizedBox(height: AppConstants.paddingMD),
                        _buildRepetitionSlider(provider),
                      ] else ...[
                        _buildPitchSlider(provider),
                      ],
                      const SizedBox(height: AppConstants.paddingXL),
                      _buildSynthesizeButton(provider),
                      if (provider.errorMessage != null) ...[
                        const SizedBox(height: AppConstants.paddingMD),
                        _buildErrorCard(provider),
                      ],
                      if (provider.lastResult != null) ...[
                        const SizedBox(height: AppConstants.paddingXL),
                        _buildAudioPlayer(provider),
                        if (provider.lastResult!.originalAudioPath != null) ...[
                          const SizedBox(height: AppConstants.paddingMD),
                          _buildComparisonSection(provider),
                        ],
                      ],
                      const SizedBox(height: AppConstants.paddingXXL),
                      _buildResearchFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBar(TtsProvider provider) {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 0,
      toolbarHeight: 58,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        provider.selectedModel.displayName,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 17,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.borderSubtle),
      ),
    );
  }

  Widget _buildModelInfoBadge(TtsProvider provider) {
    final accentColor = _getModelGradient(provider.selectedModel).colors.first;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.spatial_audio_rounded, size: 20, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.selectedModel.shortName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  provider.selectedModel.engineDescription,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Text(
              'Research',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildTextInput(TtsProvider provider) {
    return Card(
      elevation: AppConstants.elevationMedium,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, color: AppColors.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Enter Afaan Oromoo Text',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingMD),
            TextField(
              controller: _textController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'Barreeffama Afaan Oromoo barreessi...\n'
                    'e.g., Baga nagaan dhuftan, ani sagalee uumuu barbaada.',
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.borderRadiusSmall),
                ),
                counterText:
                    '${_textController.text.length} characters',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppConstants.paddingMD),
            Row(
              children: [
                if (!kIsWeb) ...[
                  _buildActionChip(
                    icon: Icons.camera_alt_rounded,
                    label: 'OCR Camera',
                    onTap: () => _handleOcr(ImageSource.camera, provider),
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    icon: Icons.photo_library_rounded,
                    label: 'OCR Gallery',
                    onTap: () => _handleOcr(ImageSource.gallery, provider),
                  ),
                ],
                const Spacer(),
                _buildActionChip(
                  icon: Icons.content_paste_rounded,
                  label: 'Paste',
                  onTap: _handlePaste,
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  icon: Icons.clear,
                  label: 'Clear',
                  onTap: () {
                    _textController.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primaryColor.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primaryColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerSelector(TtsProvider provider) {
    return Card(
      elevation: AppConstants.elevationMedium,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  provider.selectedModel == TtsModel.fishSpeechMulti
                      ? Icons.map
                      : Icons.person,
                  color: AppColors.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  provider.selectedModel == TtsModel.fishSpeechMulti
                      ? 'Dialect'
                      : 'Speaker / Voice',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingMD),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryColor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SpeakerInfo>(
                  isExpanded: true,
                  value: provider.selectedSpeaker,
                  items: provider.availableSpeakers.map((speaker) {
                    return DropdownMenuItem<SpeakerInfo>(
                      value: speaker,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            speaker.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${speaker.dialect} • ${speaker.gender}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (speaker) {
                    if (speaker != null) provider.selectSpeaker(speaker);
                  },
                ),
              ),
            ),
            if (provider.selectedSpeaker != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: AppColors.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.selectedSpeaker!.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildPitchSlider(TtsProvider provider) {
    return _sliderCard(
      icon: Icons.tune_rounded,
      label: 'Pitch Shift',
      valueText: '${provider.pitchShift > 0 ? '+' : ''}${provider.pitchShift}',
      minLabel: 'Lower (-12)',
      midLabel: 'Default (0)',
      maxLabel: 'Higher (+12)',
      delay: 300,
      slider: Slider(
        value: provider.pitchShift.toDouble(),
        min: -12,
        max: 12,
        divisions: 24,
        label: '${provider.pitchShift > 0 ? '+' : ''}${provider.pitchShift}',
        onChanged: (v) => provider.setPitchShift(v.round()),
      ),
    );
  }

  Widget _buildTemperatureSlider(TtsProvider provider) {
    return _sliderCard(
      icon: Icons.device_thermostat_rounded,
      label: 'Temperature',
      valueText: provider.temperature.toStringAsFixed(2),
      minLabel: 'Conservative (0.3)',
      midLabel: 'Default (0.6)',
      maxLabel: 'Creative (1.0)',
      delay: 330,
      slider: Slider(
        value: provider.temperature,
        min: 0.3,
        max: 1.0,
        divisions: 14,
        label: provider.temperature.toStringAsFixed(2),
        onChanged: (v) => provider.setTemperature(double.parse(v.toStringAsFixed(2))),
      ),
    );
  }

  Widget _buildRepetitionSlider(TtsProvider provider) {
    return _sliderCard(
      icon: Icons.repeat_rounded,
      label: 'Repetition Penalty',
      valueText: provider.repetitionPenalty.toStringAsFixed(1),
      minLabel: 'Low (1.0)',
      midLabel: 'Default (1.1)',
      maxLabel: 'High (2.0)',
      delay: 360,
      slider: Slider(
        value: provider.repetitionPenalty,
        min: 1.0,
        max: 2.0,
        divisions: 10,
        label: provider.repetitionPenalty.toStringAsFixed(1),
        onChanged: (v) => provider.setRepetitionPenalty(double.parse(v.toStringAsFixed(1))),
      ),
    );
  }

  Widget _sliderCard({
    required IconData icon,
    required String label,
    required String valueText,
    required String minLabel,
    required String midLabel,
    required String maxLabel,
    required int delay,
    required Widget slider,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(valueText,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          slider,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              Text(midLabel, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              Text(maxLabel, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: delay));
  }

  Widget _buildSynthesizeButton(TtsProvider provider) {
    final isActive = !provider.isProcessing;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: isActive
            ? AppColors.primaryGradient
            : LinearGradient(
                colors: [AppColors.surface3, AppColors.surface3]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: provider.isProcessing
              ? null
              : () => provider.synthesize(_textController.text),
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withOpacity(0.1),
          child: Center(
            child: provider.isProcessing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        provider.statusMessage.isNotEmpty
                            ? provider.statusMessage
                            : 'Processing…',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.graphic_eq_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Synthesize Speech',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildErrorCard(TtsProvider provider) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      decoration: BoxDecoration(
        color: AppColors.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
        border: Border.all(color: AppColors.errorColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.errorColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.errorMessage ?? '',
              style: const TextStyle(color: AppColors.errorColor, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: provider.clearError,
          ),
        ],
      ),
    ).animate().fadeIn().shake(hz: 2, duration: 500.ms);
  }

  Widget _buildAudioPlayer(TtsProvider provider) {
    final gradient = _getModelGradient(provider.selectedModel);
    final accentColor = gradient.colors.first;
    final audioPath = provider.lastResult?.audioPath;

    if (audioPath != null && audioPath != _loadedAudioPath) {
      _loadedAudioPath = audioPath;
      _setAudioSource(_audioPlayer, audioPath);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1D2E), Color(0xFF0F1219)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Generated Audio',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.selectedModel.shortName,
                        style: TextStyle(
                          color: accentColor.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accentColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    '\u2713 Ready',
                    style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Waveform
            SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(40, (index) {
                  final progress = _duration.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0.0;
                  final isPlayed = (index / 40) <= progress;
                  final seed = (index * 7 + 3) % 13;
                  final height = 12.0 + seed * 2.8;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 3,
                    height: _isPlaying && isPlayed ? height + 4 : height,
                    decoration: BoxDecoration(
                      color: isPlayed ? accentColor : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),

            // Seek slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: accentColor,
                inactiveTrackColor: Colors.white.withOpacity(0.08),
                thumbColor: Colors.white,
                overlayColor: accentColor.withOpacity(0.15),
              ),
              child: Slider(
                value: _position.inMilliseconds.toDouble(),
                max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                onChanged: (v) => _audioPlayer.seek(Duration(milliseconds: v.round())),
              ),
            ),

            // Time
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position),
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w500)),
                  Text(_formatDuration(_duration),
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _playerBtn(Icons.replay_10_rounded, () {
                  final pos = _audioPlayer.position - const Duration(seconds: 10);
                  _audioPlayer.seek(pos < Duration.zero ? Duration.zero : pos);
                }),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () => _togglePlayback(provider.lastResult!.audioPath),
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [accentColor, accentColor.withOpacity(0.7)]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: accentColor.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 24),
                _playerBtn(Icons.forward_10_rounded, () {
                  final dur = _audioPlayer.duration ?? Duration.zero;
                  final pos = _audioPlayer.position + const Duration(seconds: 10);
                  _audioPlayer.seek(pos > dur ? dur : pos);
                }),
              ],
            ),
            const SizedBox(height: 20),

            // Actions
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionBtn(Icons.download_rounded, 'Save', () => _saveAudio(provider.lastResult!.audioPath)),
                  Container(width: 1, height: 20, color: Colors.white.withOpacity(0.08), margin: const EdgeInsets.symmetric(horizontal: 20)),
                  _actionBtn(Icons.share_rounded, 'Share', () => _shareAudio(provider.lastResult!.audioPath)),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0, duration: 500.ms);
  }

  Widget _playerBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 22),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.45), size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection(TtsProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E).withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final path = provider.lastResult!.originalAudioPath!;
              if (_isPlayingOriginal) {
                _originalAudioPlayer.pause();
              } else {
                await _setAudioSource(_originalAudioPlayer, path);
                _originalAudioPlayer.play();
              }
              setState(() => _isPlayingOriginal = !_isPlayingOriginal);
            },
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2D3E),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.warningColor.withOpacity(0.4), width: 1.5),
              ),
              child: Icon(
                _isPlayingOriginal ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.warningColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Base Audio (Pre-RVC)',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('Compare with voice-cloned output above',
                    style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('A/B',
                style: TextStyle(color: AppColors.warningColor.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }


  Widget _buildResearchFooter() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLG),
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
        border: Border.all(color: AppColors.primaryColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          const Text(
            '🔬 Built for BSc Thesis Research',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Afaan Oromoo Speech Synthesis • Comparative TTS Study',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  LinearGradient _getModelGradient(TtsModel model) {
    switch (model) {
      case TtsModel.fishSpeechSingle:
        return AppColors.ttsGradient;
      case TtsModel.vits:
        return AppColors.successGradient;
      case TtsModel.fishSpeechMulti:
        return AppColors.accentGradient;
    }
  }

  Future<void> _togglePlayback(String path) async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_loadedAudioPath != path) {
        _loadedAudioPath = path;
        await _setAudioSource(_audioPlayer, path);
      } else if (_audioPlayer.processingState == ProcessingState.completed) {
        await _audioPlayer.seek(Duration.zero);
      }
      await _audioPlayer.play();
    }
  }

  /// Sets the correct audio source based on platform and path type
  Future<void> _setAudioSource(AudioPlayer player, String path) async {
    if (kIsWeb || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      await player.setUrl(path);
    } else {
      await player.setFilePath(path);
    }
  }

  Future<void> _handleOcr(ImageSource source, TtsProvider provider) async {
    try {
      OcrResult result;
      if (source == ImageSource.camera) {
        result = await provider.ocrService.captureAndExtract();
      } else {
        result = await provider.ocrService.pickAndExtract();
      }

      if (!result.wasCancelled && result.text.isNotEmpty) {
        _textController.text = result.text;
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Extracted ${result.text.length} characters from image'),
              backgroundColor: AppColors.successColor,
            ),
          );
        }
      } else if (!result.wasCancelled && result.text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No text found in the image. Try a clearer image.'),
              backgroundColor: AppColors.warningColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OCR Error: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _textController.text = data!.text!;
      setState(() {});
    }
  }

  Future<void> _saveAudio(String path) async {
    // The file is already saved in temp — notify user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio saved at: ${path.split('/').last}'),
          backgroundColor: AppColors.successColor,
        ),
      );
    }
  }

  Future<void> _shareAudio(String path) async {
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Afaan Oromoo TTS - Synthesized Speech',
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
