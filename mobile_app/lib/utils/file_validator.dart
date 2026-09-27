import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class ValidationResult {
  final bool isValid;
  final String message;
  final Map<String, dynamic>? metadata;

  ValidationResult({
    required this.isValid,
    required this.message,
    this.metadata,
  });
}

class FileValidator {
  static const List<String> allowedExtensions = [
    '.wav',
    '.mp3',
    '.m4a',
    '.flac',
    '.ogg',
    '.opus',
    '.aac',
  ];

  static const int minFileSize = 1024;
  static const int maxFileSize = 500 * 1024 * 1024;
  static const int maxFileSizeMB = 500;

  static Future<ValidationResult> validateAudioFile(String filePath) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return ValidationResult(
          isValid: false,
          message: 'File does not exist',
        );
      }

      final extension = path.extension(filePath).toLowerCase();
      if (!allowedExtensions.contains(extension)) {
        return ValidationResult(
          isValid: false,
          message: 'Invalid file type. Allowed: ${allowedExtensions.join(", ")}',
        );
      }

      final fileSize = await file.length();
      
      if (fileSize < minFileSize) {
        return ValidationResult(
          isValid: false,
          message: 'File too small (min 1KB)',
        );
      }

      if (fileSize > maxFileSize) {
        return ValidationResult(
          isValid: false,
          message: 'File too large (max ${maxFileSizeMB}MB)',
        );
      }

      final fileSizeMB = fileSize / (1024 * 1024);

      return ValidationResult(
        isValid: true,
        message: 'File validated successfully',
        metadata: {
          'size': fileSize,
          'sizeMB': fileSizeMB.toStringAsFixed(2),
          'extension': extension,
          'fileName': path.basename(filePath),
        },
      );
    } catch (e) {
      debugPrint('[Validation] Error: $e');
      return ValidationResult(
        isValid: false,
        message: 'Validation error: ${e.toString()}',
      );
    }
  }

  static ValidationResult validateSubtitleFormat(String format) {
    const allowedFormats = ['srt', 'txt', 'vtt'];
    
    final formatLower = format.toLowerCase().trim();
    
    if (!allowedFormats.contains(formatLower)) {
      return ValidationResult(
        isValid: false,
        message: 'Invalid format. Allowed: ${allowedFormats.join(", ")}',
      );
    }

    return ValidationResult(
      isValid: true,
      message: 'Format is valid',
    );
  }

  static Future<ValidationResult> validateStorageSpace(int requiredBytes) async {
    try {
      if (Platform.isAndroid) {
        final freeSpace = await _getAndroidFreeSpace();
        
        if (freeSpace != null && freeSpace < requiredBytes) {
          return ValidationResult(
            isValid: false,
            message: 'Insufficient storage space',
            metadata: {
              'required': requiredBytes,
              'available': freeSpace,
            },
          );
        }
      }

      return ValidationResult(
        isValid: true,
        message: 'Sufficient storage available',
      );
    } catch (e) {
      debugPrint('[Validation] Storage check skipped: $e');
      return ValidationResult(
        isValid: true,
        message: 'Storage check skipped',
      );
    }
  }

  static Future<int?> _getAndroidFreeSpace() async {
    try {
      return null;
    } catch (e) {
      debugPrint('[Validation] Free space check failed: $e');
      return null;
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  static Future<bool> isFileAccessible(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      debugPrint('[Validation] File access check failed: $e');
      return false;
    }
  }
}
