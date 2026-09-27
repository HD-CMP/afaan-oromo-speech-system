import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'transcription_screen.dart';
import 'subtitle_screen.dart';
import 'live_transcription_screen.dart';
import 'tts_screen.dart';
import '../models/tts_result.dart';
import '../providers/transcription_provider.dart';
import '../providers/tts_provider.dart';

import '../config/app_colors.dart';
import '../widgets/connection_status_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final sttProvider = Provider.of<TranscriptionProvider>(context);
    final ttsProvider = Provider.of<TtsProvider>(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(child: _buildBody(sttProvider, ttsProvider)),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      expandedHeight: 0,
      toolbarHeight: 60,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Oromo Voice AI',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: ConnectionStatusIndicator(),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.borderSubtle),
      ),
    );
  }

  Widget _buildBody(TranscriptionProvider sttProvider, TtsProvider ttsProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(),
          const SizedBox(height: 24),
          _buildTabSelector(),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            child: _selectedTab == 0
                ? _buildSttContent(sttProvider)
                : _buildTtsContent(ttsProvider),
          ),
          const SizedBox(height: 24),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface2, AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.indigoGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.record_voice_over_rounded, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.successGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6,
                        decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    const Text('Research', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('AI Speech Platform',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          const Text('Bidirectional speech processing for Afaan Oromoo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroPill(Icons.language_rounded, 'Afaan Oromoo'),
              const SizedBox(width: 8),
              _heroPill(Icons.psychology_rounded, 'Fine-tuned Whisper'),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0, duration: 500.ms);
  }

  Widget _heroPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          _tabPill(0, Icons.mic_rounded, 'Speech → Text'),
          const SizedBox(width: 4),
          _tabPill(1, Icons.campaign_rounded, 'Text → Speech'),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _tabPill(int index, IconData icon, String label) {
    final isActive = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: isActive ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ── STT ──
  Widget _buildSttContent(TranscriptionProvider provider) {
    final total = provider.history.length;
    final words = provider.history.fold<int>(0, (s, i) => s + i.text.split(' ').length);
    return Column(
      key: const ValueKey('stt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('$total', 'Transcriptions', Icons.article_rounded, AppColors.accentIndigo)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('$words', 'Total Words', Icons.text_fields_rounded, AppColors.accentEmerald)),
          ],
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 20),
        _sectionLabel('FEATURES'),
        const SizedBox(height: 12),
        _featureCard(
          icon: Icons.description_rounded,
          accentColor: AppColors.accentIndigo,
          title: 'Audio Transcription',
          subtitle: 'Convert speech to text with timestamps',
          trailing: _featureBadge('Whisper', AppColors.accentIndigo),
          index: 0,
          onTap: () => Navigator.push(context, _route(const TranscriptionScreen())),
        ),
        const SizedBox(height: 10),
        _featureCard(
          icon: Icons.subtitles_rounded,
          accentColor: AppColors.primary,
          title: 'Subtitle Generation',
          subtitle: 'Export SRT files with word-level timing',
          trailing: _featureBadge('SRT • VTT', AppColors.primary),
          index: 1,
          onTap: () => Navigator.push(context, _route(const SubtitleScreen())),
        ),
        const SizedBox(height: 10),
        _featureCard(
          icon: Icons.sensors_rounded,
          accentColor: AppColors.accentEmerald,
          title: 'Live Transcription',
          subtitle: 'Real-time speech recognition via WebSocket',
          trailing: _featureBadge('Live', AppColors.accentEmerald),
          index: 2,
          onTap: () => Navigator.push(context, _route(const LiveTranscriptionScreen())),
        ),
      ],
    );
  }

  // ── TTS ──
  Widget _buildTtsContent(TtsProvider ttsProvider) {
    return Column(
      key: const ValueKey('tts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('${ttsProvider.synthesisCount}', 'Syntheses', Icons.graphic_eq_rounded, AppColors.accentViolet)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('5', 'Speakers', Icons.people_alt_rounded, AppColors.primary)),
          ],
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 20),
        _sectionLabel('TTS MODELS'),
        const SizedBox(height: 12),
        _featureCard(
          icon: Icons.spatial_audio_off_rounded,
          accentColor: AppColors.accentViolet,
          title: 'Fish Speech (Single Speaker)',
          subtitle: 'Fish Speech 1.5 + RVC v2 • LoRA r=32',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _featureBadge('LoRA', AppColors.accentViolet),
            const SizedBox(width: 4),
            _featureBadge('RVC v2', AppColors.accentIndigo),
          ]),
          index: 0,
          onTap: () => Navigator.push(context, _route(TtsScreen(initialModel: TtsModel.fishSpeechSingle))),
        ),
        const SizedBox(height: 10),
        _featureCard(
          icon: Icons.bolt_rounded,
          accentColor: AppColors.accentEmerald,
          title: 'VITS (Fast Inference)',
          subtitle: 'Meta MMS-TTS + RVC v2 • Sentence chunking',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _featureBadge('Fast', AppColors.accentEmerald),
            const SizedBox(width: 4),
            _featureBadge('RVC', AppColors.accentCyan),
          ]),
          index: 1,
          onTap: () => Navigator.push(context, _route(TtsScreen(initialModel: TtsModel.vits))),
        ),
        const SizedBox(height: 10),
        _featureCard(
          icon: Icons.record_voice_over_rounded,
          accentColor: AppColors.accentRose,
          title: 'Fish Speech (Multi-Speaker)',
          subtitle: 'Multi-Dialect • Voice cloning folders',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _featureBadge('Multi', AppColors.accentRose),
            const SizedBox(width: 4),
            _featureBadge('Dialect', AppColors.accentViolet),
          ]),
          index: 2,
          onTap: () => Navigator.push(context, _route(TtsScreen(initialModel: TtsModel.fishSpeechMulti))),
        ),
        const SizedBox(height: 10),
        _featureCard(
          icon: Icons.document_scanner_rounded,
          accentColor: AppColors.accentCyan,
          title: 'OCR → Speech',
          subtitle: 'Extract text from images & synthesize',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _featureBadge('Camera', AppColors.accentCyan),
            const SizedBox(width: 4),
            _featureBadge('Gallery', AppColors.primary),
          ]),
          index: 3,
          onTap: _showOcrSheet,
        ),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 20)),
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ));
  }

  Widget _featureCard({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String subtitle,
    required int index,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    if (trailing != null) ...[
                      const SizedBox(height: 8),
                      trailing,
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 80 * index)).slideY(begin: 0.05, end: 0, delay: Duration(milliseconds: 80 * index));
  }

  Widget _featureBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_rounded, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          const Text('BSc Thesis Research • Hawassa University',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  void _showOcrSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OcrSheet(),
    );
  }

  Route _route(Widget page) {
    return MaterialPageRoute(builder: (_) => page);
  }
}

class _OcrSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('OCR → Speech',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Choose a TTS model to synthesize extracted text',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          _ocrOption(context, Icons.spatial_audio_off_rounded, 'Fish Speech (Single)', AppColors.accentViolet, TtsModel.fishSpeechSingle),
          const SizedBox(height: 10),
          _ocrOption(context, Icons.bolt_rounded, 'VITS (Fast Inference)', AppColors.accentEmerald, TtsModel.vits),
          const SizedBox(height: 10),
          _ocrOption(context, Icons.record_voice_over_rounded, 'Fish Speech (Multi)', AppColors.accentRose, TtsModel.fishSpeechMulti),
        ],
      ),
    );
  }

  Widget _ocrOption(BuildContext context, IconData icon, String title, Color color, TtsModel model) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => TtsScreen(initialModel: model)));
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(title,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500))),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
