import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// On-device OCR service using Google ML Kit
/// Extracts text from images for TTS input
class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _imagePicker = ImagePicker();

  /// Extract text from an image file path
  Future<String> extractTextFromImage(String imagePath) async {
    try {
      debugPrint('[OCR] Processing image: $imagePath');
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final extractedText = recognizedText.text.trim();
      debugPrint('[OCR] Extracted ${extractedText.length} characters');
      debugPrint('[OCR] Blocks: ${recognizedText.blocks.length}');

      return extractedText;
    } catch (e) {
      debugPrint('[OCR] Error extracting text: $e');
      throw Exception('Failed to extract text from image: $e');
    }
  }

  /// Open camera to capture and extract text
  Future<OcrResult> captureAndExtract() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        return OcrResult(text: '', imagePath: '', wasCancelled: true);
      }

      final text = await extractTextFromImage(photo.path);
      return OcrResult(
        text: text,
        imagePath: photo.path,
        wasCancelled: false,
      );
    } catch (e) {
      debugPrint('[OCR] Camera capture error: $e');
      throw Exception('Failed to capture image: $e');
    }
  }

  /// Pick image from gallery and extract text
  Future<OcrResult> pickAndExtract() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (image == null) {
        return OcrResult(text: '', imagePath: '', wasCancelled: true);
      }

      final text = await extractTextFromImage(image.path);
      return OcrResult(
        text: text,
        imagePath: image.path,
        wasCancelled: false,
      );
    } catch (e) {
      debugPrint('[OCR] Gallery pick error: $e');
      throw Exception('Failed to pick image: $e');
    }
  }

  /// Dispose the text recognizer
  void dispose() {
    _textRecognizer.close();
  }
}

/// Result of an OCR operation
class OcrResult {
  final String text;
  final String imagePath;
  final bool wasCancelled;

  const OcrResult({
    required this.text,
    required this.imagePath,
    required this.wasCancelled,
  });
}
