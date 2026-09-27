import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ExportService {
  /// Save file using Storage Access Framework (direct folder picker)
  Future<String?> saveFileWithPicker(String content, String suggestedFileName) async {
    try {
      // Convert string content to bytes (required for Android/iOS)
      final bytes = utf8.encode(content);
      
      // Use SAF to let user pick save location
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Choose where to save',
        fileName: suggestedFileName,
        type: FileType.any,
        lockParentWindow: true,
        bytes: Uint8List.fromList(bytes),
      );
      
      if (outputPath == null) {
        debugPrint('[Export] User cancelled file picker');
        return null;
      }
      
      debugPrint('[Export] File saved to: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('[Export] Error in saveFileWithPicker: $e');
      rethrow;
    }
  }
  
  /// Save file to user-chosen location (legacy share sheet method)
  Future<String?> saveFileToUserLocation(String content, String suggestedFileName) async {
    try {
      // First save to temp location
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$suggestedFileName');
      await tempFile.writeAsString(content);
      
      // Share using system share sheet (allows user to save anywhere)
      final xFile = XFile(tempFile.path);
      await Share.shareXFiles(
        [xFile],
        subject: 'Save $suggestedFileName',
        text: 'Choose where to save this file',
      );
      
      debugPrint('[Export] File shared for user to save: $suggestedFileName');
      return tempFile.path;
    } catch (e) {
      debugPrint('[Export] Error in saveFileToUserLocation: $e');
      rethrow;
    }
  }
  
  /// Export to app's document directory (quick save)
  Future<String> exportToText(String text, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s-]'), '');
      final file = File('${directory.path}/transcription_${sanitizedFileName}_$timestamp.txt');
      
      await file.writeAsString(text);
      debugPrint('[Export] Saved to: ${file.path}');
      
      return file.path;
    } catch (e) {
      debugPrint('[Export] Error saving file: $e');
      rethrow;
    }
  }
  
  /// Save with custom extension and user-chosen location
  Future<String?> saveWithExtension(
    String content, 
    String suggestedFileName,
    String extension,
  ) async {
    try {
      final fileName = suggestedFileName.endsWith(extension) 
          ? suggestedFileName 
          : '$suggestedFileName$extension';
      
      return await saveFileToUserLocation(content, fileName);
    } catch (e) {
      debugPrint('[Export] Error in saveWithExtension: $e');
      rethrow;
    }
  }
  
  Future<void> shareText(String text, {String? subject}) async {
    try {
      await Share.share(
        text,
        subject: subject ?? 'Transcription',
      );
      debugPrint('[Export] Shared text');
    } catch (e) {
      debugPrint('[Export] Error sharing: $e');
      rethrow;
    }
  }
  
  Future<void> shareFile(String filePath) async {
    try {
      final file = XFile(filePath);
      await Share.shareXFiles([file], subject: 'Transcription');
      debugPrint('[Export] Shared file: $filePath');
    } catch (e) {
      debugPrint('[Export] Error sharing file: $e');
      rethrow;
    }
  }
  
  Future<void> exportAndShare(String text, String fileName) async {
    try {
      final filePath = await exportToText(text, fileName);
      await shareFile(filePath);
    } catch (e) {
      debugPrint('[Export] Error exporting and sharing: $e');
      rethrow;
    }
  }
}
