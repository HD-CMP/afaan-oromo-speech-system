import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

enum ServerStatus {
  running,
  stopped,
  unknown,
}

class ServerInfo {
  final ServerStatus status;
  final int? pid;
  final double? cpuPercent;
  final double? memoryMb;
  final double? uptimeSeconds;

  ServerInfo({
    required this.status,
    this.pid,
    this.cpuPercent,
    this.memoryMb,
    this.uptimeSeconds,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    ServerStatus status;
    
    switch (statusStr) {
      case 'running':
        status = ServerStatus.running;
        break;
      case 'stopped':
      case 'not_running':
        status = ServerStatus.stopped;
        break;
      default:
        status = ServerStatus.unknown;
    }

    return ServerInfo(
      status: status,
      pid: json['pid'] as int?,
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble(),
      memoryMb: (json['memory_mb'] as num?)?.toDouble(),
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toDouble(),
    );
  }
}

class ServerControlService {
  static const int controlPort = 8001;
  final Dio _dio;

  ServerControlService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        )) {
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      error: true,
      logPrint: (obj) => debugPrint('[ServerControl] $obj'),
    ));
  }

  String get _baseUrl => 'http://${ApiConfig.serverIp}:$controlPort';

  void updateBaseUrl() {
    _dio.options.baseUrl = _baseUrl;
    debugPrint('[ServerControl] Updated base URL to: $_baseUrl');
  }

  Future<bool> testConnection() async {
    try {
      debugPrint('[ServerControl] Testing connection to: $_baseUrl');
      final response = await _dio.get(
        '$_baseUrl/',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ServerControl] Connection test failed: $e');
      return false;
    }
  }

  Future<ServerInfo> getStatus() async {
    try {
      debugPrint('[ServerControl] Getting server status...');
      final response = await _dio.get('$_baseUrl/status');
      
      if (response.statusCode == 200) {
        return ServerInfo.fromJson(response.data);
      }
      
      return ServerInfo(status: ServerStatus.unknown);
    } catch (e) {
      debugPrint('[ServerControl] Failed to get status: $e');
      return ServerInfo(status: ServerStatus.unknown);
    }
  }

  Future<Map<String, dynamic>> startServer() async {
    try {
      debugPrint('[ServerControl] Starting API server...');
      final response = await _dio.post('$_baseUrl/start');
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      
      throw Exception('Failed to start server: ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('[ServerControl] Error starting server: ${e.message}');
      throw Exception('Failed to start server: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> stopServer() async {
    try {
      debugPrint('[ServerControl] Stopping API server...');
      final response = await _dio.post('$_baseUrl/stop');
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      
      throw Exception('Failed to stop server: ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('[ServerControl] Error stopping server: ${e.message}');
      throw Exception('Failed to stop server: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> restartServer() async {
    try {
      debugPrint('[ServerControl] Restarting API server...');
      final response = await _dio.post('$_baseUrl/restart');
      
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      
      throw Exception('Failed to restart server: ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('[ServerControl] Error restarting server: ${e.message}');
      throw Exception('Failed to restart server: ${e.message}');
    }
  }

  Future<String?> getLogs({int lines = 50}) async {
    try {
      debugPrint('[ServerControl] Fetching server logs...');
      final response = await _dio.get('$_baseUrl/logs', queryParameters: {
        'lines': lines,
      });
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return data['logs'] as String?;
      }
      
      return null;
    } catch (e) {
      debugPrint('[ServerControl] Failed to fetch logs: $e');
      return null;
    }
  }
}
