import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/transcription_provider.dart';
import '../providers/localization_provider.dart';
import '../models/transcription_history.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../widgets/custom_snackbar.dart';
import '../services/export_service.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  String _sortBy = 'date';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TranscriptionProvider>(context, listen: false);
      provider.markAllAsRead();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalizationProvider>(
      builder: (context, localizationProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(localizationProvider.getString('history')),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _showSearchDialog(),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                onSelected: (value) {
                  setState(() {
                    _sortBy = value;
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'date',
                    child: Text(localizationProvider.getString('sort_by_date')),
                  ),
                  PopupMenuItem(
                    value: 'duration',
                    child: Text(localizationProvider.getString('sort_by_duration')),
                  ),
                  PopupMenuItem(
                    value: 'name',
                    child: Text(localizationProvider.getString('sort_by_name')),
                  ),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2.5,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.description_rounded, size: 18),
                      text: localizationProvider.getString('transcription'),
                    ),
                    Tab(
                      icon: const Icon(Icons.subtitles_rounded, size: 18),
                      text: localizationProvider.getString('subtitle'),
                    ),
                    Tab(
                      icon: const Icon(Icons.sensors_rounded, size: 18),
                      text: localizationProvider.getString('live'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildHistoryTab(TranscriptionType.transcription),
              _buildHistoryTab(TranscriptionType.subtitle),
              _buildHistoryTab(TranscriptionType.live),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab(TranscriptionType type) {
    return Consumer<TranscriptionProvider>(
      builder: (context, provider, child) {
        final filteredHistory = _filterAndSortHistory(
          provider.getHistoryByType(type),
        );

        if (filteredHistory.isEmpty) {
          return _buildEmptyState(type);
        }

        return RefreshIndicator(
          onRefresh: () async {
            await provider.loadHistory();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppConstants.paddingLG),
            itemCount: filteredHistory.length,
            itemBuilder: (context, index) {
              return _buildHistoryCard(
                context,
                filteredHistory[index],
                index,
                provider,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(TranscriptionType type) {
    final localizationProvider = Provider.of<LocalizationProvider>(context);
    String title;
    String subtitle;
    IconData icon;

    switch (type) {
      case TranscriptionType.transcription:
        title = localizationProvider.getString('no_transcription_history');
        subtitle = localizationProvider.getString('transcriptions_appear_here');
        icon = Icons.description;
        break;
      case TranscriptionType.subtitle:
        title = localizationProvider.getString('no_subtitle_history');
        subtitle = localizationProvider.getString('subtitles_appear_here');
        icon = Icons.subtitles;
        break;
      case TranscriptionType.live:
        title = localizationProvider.getString('no_live_history');
        subtitle = localizationProvider.getString('live_appear_here');
        icon = Icons.mic_none;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: AppConstants.paddingLG),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
          ),
          const SizedBox(height: AppConstants.paddingSM),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    BuildContext context,
    TranscriptionHistory item,
    int index,
    TranscriptionProvider provider,
  ) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.paddingXL),
        decoration: BoxDecoration(
          color: AppColors.errorColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        provider.deleteHistoryItem(item.id);
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('transcription_deleted'),
          type: SnackBarType.success,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: InkWell(
          onTap: () => _showTranscriptionDetail(context, item),
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.paddingLG),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accentIndigo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: AppColors.accentIndigo,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatDate(item.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Consumer<LocalizationProvider>(
                      builder: (context, localizationProvider, _) {
                        return PopupMenuButton<String>(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 8,
                          onSelected: (value) =>
                              _handleMenuAction(value, item, provider),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 20, color: Colors.orange.shade700),
                                  const SizedBox(width: 12),
                                  Text(localizationProvider.getString('export_btn')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share, size: 20, color: AppColors.primaryColor),
                                  const SizedBox(width: 12),
                                  Text(localizationProvider.getString('share')),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete, size: 20, color: AppColors.errorColor),
                                  const SizedBox(width: 12),
                                  Text(
                                    localizationProvider.getString('delete'),
                                    style: const TextStyle(color: AppColors.errorColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.grey.shade200,
                        Colors.grey.shade100,
                        Colors.grey.shade200,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    item.text,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildInfoChip(
                      Icons.timer,
                      _formatDuration(item.duration ?? 0.0),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.text_fields,
                      '${item.text.split(' ').length} words',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      )
          .animate()
          .fadeIn(
            duration: AppConstants.animationDurationNormal,
            delay: Duration(milliseconds: 50 * index),
          )
          .slideY(
            begin: 0.2,
            end: 0,
            duration: AppConstants.animationDurationNormal,
            delay: Duration(milliseconds: 50 * index),
          ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<TranscriptionHistory> _filterAndSortHistory(
    List<TranscriptionHistory> history,
  ) {
    var filtered = history.where((item) {
      return item.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.text.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    switch (_sortBy) {
      case 'date':
        filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case 'duration':
        filtered.sort((a, b) => (b.duration ?? 0.0).compareTo(a.duration ?? 0.0));
        break;
      case 'name':
        filtered.sort((a, b) => a.fileName.compareTo(b.fileName));
        break;
    }

    return filtered;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat('HH:mm').format(date)}';
    } else {
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    }
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  void _showSearchDialog() {
    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizationProvider.getString('search')),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: '${localizationProvider.getString('search')}...',
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showTranscriptionDetail(
    BuildContext context,
    TranscriptionHistory item,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDefault,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentIndigo.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.article_rounded,
                          color: AppColors.accentIndigo,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.fileName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(item.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.timer_rounded,
                        _formatDuration(item.duration ?? 0.0),
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        Icons.text_fields_rounded,
                        '${item.text.split(' ').length} words',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: SelectableText(
                    item.text,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.8,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(
    String action,
    TranscriptionHistory item,
    TranscriptionProvider provider,
  ) async {
    switch (action) {
      case 'export':
        await _exportHistoryItem(item);
        break;
      case 'share':
        Share.share(item.text);
        break;
      case 'delete':
        provider.deleteHistoryItem(item.id);
        final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
        CustomSnackBar.show(
          context,
          message: localizationProvider.getString('transcription_deleted'),
          type: SnackBarType.success,
        );
        break;
    }
  }
  
  Future<void> _exportHistoryItem(TranscriptionHistory item) async {
    try {
      final exportService = ExportService();
      final fileName = '${item.fileName}_${DateTime.now().millisecondsSinceEpoch}.txt';
      final savedPath = await exportService.saveFileWithPicker(item.text, fileName);
      
      if (savedPath == null) {
        // User cancelled
        if (!mounted) return;
        CustomSnackBar.show(
          context,
          message: 'Save cancelled',
          type: SnackBarType.info,
        );
        return;
      }
      
      if (!mounted) return;
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      CustomSnackBar.show(
        context,
        message: '${localizationProvider.getString('saved_file')}: $savedPath',
        type: SnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('export_failed'),
        type: SnackBarType.error,
      );
    }
  }
}
