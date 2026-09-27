import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';

class ResearchPaperScreen extends StatefulWidget {
  const ResearchPaperScreen({super.key});

  @override
  State<ResearchPaperScreen> createState() => _ResearchPaperScreenState();
}

class _ResearchPaperScreenState extends State<ResearchPaperScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _paperData;
  bool _isLoading = true;
  bool _abstractExpanded = false;
  late AnimationController _headerController;
  late Animation<double> _headerAnimation;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerAnimation = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutCubic,
    );
    _loadPaperData();
    _headerController.forward();
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  Future<void> _loadPaperData() async {
    try {
      final json = await rootBundle.loadString('assets/paper/paper_info.json');
      setState(() {
        _paperData = jsonDecode(json) as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open link'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
            const SizedBox(width: 8),
            Text('$label copied to clipboard'),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? _buildLoading()
          : _paperData == null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildError() {
    return const Center(
      child: Text('Failed to load paper data', style: TextStyle(color: AppColors.textMuted)),
    );
  }

  Widget _buildContent() {
    final data = _paperData!;
    final authors = (data['authors'] as List).cast<String>();
    final keywords = (data['keywords'] as List).cast<String>();
    final results = (data['key_results'] as List).cast<Map<String, dynamic>>();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Hero App Bar ──────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: 'Download PDF',
              icon: const Icon(Icons.download_rounded, color: AppColors.primary),
              onPressed: () => _openUrl(data['pdf_download_url'] ?? ''),
            ),
            const SizedBox(width: 4),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0D1B3E),
                    AppColors.surface,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
                child: FadeTransition(
                  opacity: _headerAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Badge row
                      Row(
                        children: [
                          _smallBadge('B.Sc. Thesis', AppColors.primary),
                          const SizedBox(width: 8),
                          _smallBadge('May 2026', AppColors.accentCyan),
                          const SizedBox(width: 8),
                          _smallBadge('Open Access', AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data['title'],
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.35,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        authors.join(' • '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Body Content ─────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Action Buttons
              _buildActionButtons(data),
              const SizedBox(height: 20),

              // Key Results
              _buildSectionLabel('KEY RESULTS'),
              const SizedBox(height: 10),
              _buildResultsGrid(results),
              const SizedBox(height: 20),

              // Abstract
              _buildSectionLabel('ABSTRACT'),
              const SizedBox(height: 10),
              _buildAbstractCard(data['abstract']),
              const SizedBox(height: 20),

              // Authors & Institution
              _buildSectionLabel('AUTHORS & INSTITUTION'),
              const SizedBox(height: 10),
              _buildAuthorsCard(data, authors),
              const SizedBox(height: 20),

              // Keywords
              _buildSectionLabel('KEYWORDS'),
              const SizedBox(height: 10),
              _buildKeywordsWrap(keywords),
              const SizedBox(height: 20),

              // Citations
              _buildSectionLabel('CITE THIS PAPER'),
              const SizedBox(height: 10),
              _buildCitationCard(data, 'APA', data['citation_apa']),
              const SizedBox(height: 10),
              _buildCitationCard(data, 'BibTeX', data['citation_bibtex']),
              const SizedBox(height: 20),

              // Links
              _buildSectionLabel('LINKS & RESOURCES'),
              const SizedBox(height: 10),
              _buildLinksCard(data),
              const SizedBox(height: 32),

              // Footer
              _buildFooter(),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Action Buttons ──────────────────────────────────────────────
  Widget _buildActionButtons(Map<String, dynamic> data) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.picture_as_pdf_rounded,
            label: 'Read PDF',
            color: AppColors.error,
            onTap: () => _openUrl(data['pdf_download_url'] ?? ''),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            icon: Icons.hub_rounded,
            label: 'Hugging Face',
            color: const Color(0xFFFF9D00),
            onTap: () => _openUrl(data['huggingface_url'] ?? ''),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            icon: Icons.code_rounded,
            label: 'GitHub',
            color: AppColors.textSecondary,
            onTap: () => _openUrl(data['github_url'] ?? ''),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Key Results Grid ────────────────────────────────────────────
  Widget _buildResultsGrid(List<Map<String, dynamic>> results) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.6,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final r = results[i];
        final colors = [
          AppColors.primary,
          AppColors.success,
          AppColors.accentCyan,
          const Color(0xFF8B5CF6),
          AppColors.warning,
        ];
        final c = colors[i % colors.length];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: c, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r['metric'],
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                r['value'],
                style: TextStyle(
                  fontSize: 18,
                  color: c,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                r['detail'],
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Abstract ────────────────────────────────────────────────────
  Widget _buildAbstractCard(String abstract) {
    const previewLength = 300;
    final isLong = abstract.length > previewLength;
    final displayText = (!_abstractExpanded && isLong)
        ? '${abstract.substring(0, previewLength)}...'
        : abstract;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
              height: 1.7,
            ),
          ),
          if (isLong) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _abstractExpanded = !_abstractExpanded),
              child: Text(
                _abstractExpanded ? '▲ Show less' : '▼ Read full abstract',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Authors ─────────────────────────────────────────────────────
  Widget _buildAuthorsCard(Map<String, dynamic> data, List<String> authors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Authors
          ...authors.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGlow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          e.value[0],
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.value,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Co-Author',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const Divider(color: AppColors.borderSubtle, height: 20),
          // Institution
          _infoRow(Icons.school_rounded, data['institution']),
          const SizedBox(height: 6),
          _infoRow(Icons.electrical_services_rounded, data['department']),
          const SizedBox(height: 6),
          _infoRow(Icons.person_outline_rounded, 'Advisor: ${data['advisor']}'),
          const SizedBox(height: 6),
          _infoRow(Icons.location_on_rounded, data['location']),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  // ── Keywords ────────────────────────────────────────────────────
  Widget _buildKeywordsWrap(List<String> keywords) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywords.map((kw) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryGlow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Text(
            kw,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Citation Cards ───────────────────────────────────────────────
  Widget _buildCitationCard(Map<String, dynamic> data, String format, String citation) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  format,
                  style: const TextStyle(
                    color: AppColors.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _copyToClipboard(citation, '$format citation'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
                      const SizedBox(width: 5),
                      const Text(
                        'Copy',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              citation,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.6,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Links Card ───────────────────────────────────────────────────
  Widget _buildLinksCard(Map<String, dynamic> data) {
    final links = [
      {
        'icon': Icons.picture_as_pdf_rounded,
        'label': 'Full Thesis PDF',
        'subtitle': 'Read or download the complete paper',
        'color': AppColors.error,
        'url': data['pdf_download_url'],
      },
      {
        'icon': Icons.hub_rounded,
        'label': 'Live Demo — Hugging Face',
        'subtitle': 'Try the ASR & TTS models online',
        'color': const Color(0xFFFF9D00),
        'url': data['huggingface_url'],
      },
      {
        'icon': Icons.code_rounded,
        'label': 'Source Code — GitHub',
        'subtitle': 'Full backend, mobile app, and training scripts',
        'color': AppColors.textSecondary,
        'url': data['github_url'],
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: links.asMap().entries.map((entry) {
          final link = entry.value;
          final isLast = entry.key == links.length - 1;
          return Column(
            children: [
              ListTile(
                onTap: () => _openUrl(link['url'] as String),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (link['color'] as Color).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(link['icon'] as IconData, color: link['color'] as Color, size: 20),
                ),
                title: Text(
                  link['label'] as String,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  link['subtitle'] as String,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              ),
              if (!isLast)
                Divider(height: 1, indent: 72, color: AppColors.borderSubtle),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open_rounded, color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Open Access Research',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'This research is freely available to all readers. If you use this work in your own research, please cite the authors using the citation formats provided above.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _smallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
