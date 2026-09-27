import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/subtitle_provider.dart';
import '../providers/localization_provider.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/subtitle_player_widget.dart';

class SubtitleScreen extends StatelessWidget {
  const SubtitleScreen({super.key});

  Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'mp4', 'mov', 'avi'],
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.single.name.isNotEmpty) {
        final file = result.files.single;
        final filePath = file.path ?? file.name;
        if (!context.mounted) return;
        
        // Clear previous subtitle before generating new one
        final provider = Provider.of<SubtitleProvider>(context, listen: false);
        provider.reset();
        
        await provider.generateSubtitles(filePath, fileBytes: file.bytes);
      }
    } catch (e) {
      if (!context.mounted) return;
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localizationProvider.getString('error_picking_file')}: $e'), backgroundColor: Colors.red),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    final localizationProvider = Provider.of<LocalizationProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(localizationProvider.getString('subtitle_generation')),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: ConnectionStatusIndicator(),
          ),
          Consumer<SubtitleProvider>(
            builder: (context, provider, _) {
              if (provider.status == SubtitleStatus.completed) {
                return IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => provider.reset(),
                  tooltip: 'Start New',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<SubtitleProvider>(
        builder: (context, provider, _) {
          if (provider.status == SubtitleStatus.completed &&
              provider.result != null &&
              provider.currentFilePath != null) {
            return Column(
              children: [
                const ConnectionStatusBanner(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: SubtitlePlayerWidget(
                      filePath: provider.currentFilePath!,
                      segments: provider.result!.segments,
                      fullText: provider.result!.fullText,
                      srtContent: provider.result!.srt,
                    ),
                  ),
                ),
              ],
            );
          }
          
          return Column(
            children: [
              const ConnectionStatusBanner(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Upload Section
                      Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.video_library,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          localizationProvider.getString('select_audio_video'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${localizationProvider.getString('audio_formats')}\n${localizationProvider.getString('video_formats')}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: provider.isProcessing
                              ? null
                              : () => _pickFile(context),
                          icon: const Icon(Icons.file_upload),
                          label: Text(localizationProvider.getString('choose_file')),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Status Section
                if (provider.isProcessing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            provider.status == SubtitleStatus.uploading
                                ? localizationProvider.getString('uploading_file')
                                : localizationProvider.getString('generating_subtitles'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            localizationProvider.getString('may_take_moments'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Error Section
                if (provider.status == SubtitleStatus.error)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            localizationProvider.getString('generation_failed'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.errorMessage ?? 'Unknown error',
                            style: const TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => provider.reset(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: Text(localizationProvider.getString('try_again')),
                          ),
                        ],
                      ),
                    ),
                  ),


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
}
