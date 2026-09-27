import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // Permanent production server (HuggingFace Spaces)
  static const String productionUrl = 'https://hnde-afaan-oromo-stt-api.hf.space';
  
  // Development/local server (for testing only - deprecated)
  static const String localServerIp = '192.168.137.1';
  static const int localServerPort = 8000;
  
  // Backward compatibility properties (deprecated, always return production values)
  static String get serverIp => 'hnde-afaan-oromo-stt-api.hf.space';
  static int get serverPort => 443;
  
  // Use production by default
  static String get baseUrl => productionUrl;
  
  // For Android emulator testing (optional)
  static String get emulatorUrl => 'http://10.0.2.2:$localServerPort';
  
  static Future<void> initialize() async {
    // No configuration needed - using permanent production server
  }
  
  // Deprecated methods for backward compatibility (do nothing)
  static void updateConfigTemporarily(String ip, int port) {
    // No-op: Always use production server
  }
  
  static Future<void> updateConfig(String ip, int port) async {
    // No-op: Always use production server
  }
}
