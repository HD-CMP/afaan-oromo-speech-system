import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';

class ConnectionProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  bool _isConnected = false;
  bool _isChecking = false;
  bool _isWakingUp = false;
  DateTime? _lastCheckedTime;
  Timer? _periodicCheckTimer;
  
  // Check interval: every 2 minutes (less frequent to avoid spam)
  static const Duration _checkInterval = Duration(minutes: 2);
  
  bool get isConnected => _isConnected;
  bool get isChecking => _isChecking;
  bool get isWakingUp => _isWakingUp;
  DateTime? get lastCheckedTime => _lastCheckedTime;
  
  ConnectionProvider() {
    _initialize();
  }
  
  void _initialize() {
    // Check immediately on startup
    checkConnection();
    
    // Start periodic checks
    _startPeriodicChecks();
  }
  
  void _startPeriodicChecks() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(_checkInterval, (timer) {
      checkConnection();
    });
  }
  
  void stopPeriodicChecks() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }
  
  Future<void> checkConnection() async {
    if (_isChecking) return; // Prevent multiple simultaneous checks
    
    _isChecking = true;
    _isWakingUp = false;
    notifyListeners();
    
    try {
      debugPrint('[ConnectionProvider] Checking API connection...');
      
      // First quick check (longer timeout for HuggingFace Spaces)
      final testDio = Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));
      
      try {
        final response = await testDio.get('/health').timeout(
          const Duration(seconds: 40),
        );
        
        _isConnected = response.statusCode == 200;
        _lastCheckedTime = DateTime.now();
        _isWakingUp = false;
        
        debugPrint('[ConnectionProvider] Connection status: ${_isConnected ? "CONNECTED" : "DISCONNECTED"}');
      } on TimeoutException {
        // Server might be sleeping, show wake-up state
        debugPrint('[ConnectionProvider] Server might be sleeping, attempting wake-up...');
        _isWakingUp = true;
        notifyListeners();
        
        // Try again with longer timeout
        final result = await _apiService.testConnection();
        _isConnected = result;
        _lastCheckedTime = DateTime.now();
        _isWakingUp = false;
        
        debugPrint('[ConnectionProvider] Connection status after wake-up: ${result ? "CONNECTED" : "DISCONNECTED"}');
      }
    } catch (e) {
      debugPrint('[ConnectionProvider] Connection check failed: $e');
      _isConnected = false;
      _lastCheckedTime = DateTime.now();
      _isWakingUp = false;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
  
  /// Force an immediate connection check (called by user action)
  Future<void> forceCheck() async {
    await checkConnection();
  }

  /// Update API service configuration (called when server settings change)
  Future<void> updateConfiguration() async {
    debugPrint('[ConnectionProvider] Updating API service configuration...');
    _apiService.updateBaseUrl();
    await forceCheck();
  }
  
  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    super.dispose();
  }
}
