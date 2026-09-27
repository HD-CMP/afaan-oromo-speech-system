import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ErrorHandler {
  static void initialize() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logError(details.exception, details.stack, details.context);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _logError(error, stack, ErrorDescription('Platform error'));
      return true;
    };

    debugPrint('[ErrorHandler] Initialized');
  }

  static void _logError(dynamic error, StackTrace? stackTrace, DiagnosticsNode? context) {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('[ERROR] ${DateTime.now().toIso8601String()}');
    debugPrint('Error: $error');
    
    if (context != null) {
      debugPrint('Context: ${context.toDescription()}');
    }
    
    if (stackTrace != null) {
      debugPrint('Stack trace:\n$stackTrace');
    }
    
    debugPrint('═══════════════════════════════════════════');
  }

  static Future<T> catchErrors<T>({
    required Future<T> Function() operation,
    required String operationName,
    T? fallbackValue,
    Function(dynamic error)? onError,
  }) async {
    try {
      debugPrint('[ErrorHandler] Starting: $operationName');
      final result = await operation();
      debugPrint('[ErrorHandler] Completed: $operationName');
      return result;
    } catch (error, stackTrace) {
      debugPrint('[ErrorHandler] Failed: $operationName');
      _logError(error, stackTrace, ErrorDescription(operationName));
      
      onError?.call(error);
      
      if (fallbackValue != null) {
        return fallbackValue;
      }
      
      rethrow;
    }
  }

  static T catchSync<T>({
    required T Function() operation,
    required String operationName,
    T? fallbackValue,
    Function(dynamic error)? onError,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      _logError(error, stackTrace, ErrorDescription(operationName));
      
      onError?.call(error);
      
      if (fallbackValue != null) {
        return fallbackValue;
      }
      
      rethrow;
    }
  }
}

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(FlutterErrorDetails)? errorBuilder;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterErrorDetails? _errorDetails;

  @override
  void initState() {
    super.initState();
    
    FlutterError.onError = (details) {
      setState(() {
        _errorDetails = details;
      });
      FlutterError.presentError(details);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_errorDetails != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_errorDetails!);
      }
      
      return _DefaultErrorWidget(errorDetails: _errorDetails!);
    }

    return widget.child;
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final FlutterErrorDetails errorDetails;

  const _DefaultErrorWidget({required this.errorDetails});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 24),
              Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                errorDetails.exception.toString(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red.shade700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.home),
                label: const Text('Return to Home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
