import 'dart:async';
import 'package:flutter/foundation.dart';

class NetworkResilience {
  static const int maxRetries = 3;
  static const int baseDelayMs = 1000;
  static const int maxDelayMs = 10000;

  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    int? maxAttempts,
    bool Function(dynamic error)? shouldRetry,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    final attempts = maxAttempts ?? maxRetries;
    int currentAttempt = 0;
    dynamic lastError;

    while (currentAttempt < attempts) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        currentAttempt++;

        final isRetryable = shouldRetry?.call(error) ?? _defaultShouldRetry(error);

        if (currentAttempt >= attempts || !isRetryable) {
          debugPrint('[Retry] Max attempts reached or error not retryable');
          rethrow;
        }

        final delay = _calculateDelay(currentAttempt);
        debugPrint('[Retry] Attempt $currentAttempt/$attempts failed, retrying in ${delay}ms');
        debugPrint('[Retry] Error: $error');

        onRetry?.call(currentAttempt, error);

        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    throw lastError ?? Exception('Operation failed after $attempts attempts');
  }

  static int _calculateDelay(int attempt) {
    final delay = baseDelayMs * (1 << (attempt - 1));
    final jitter = (delay * 0.2 * (0.5 - (DateTime.now().millisecondsSinceEpoch % 100) / 100));
    final totalDelay = (delay + jitter).toInt();
    return totalDelay.clamp(baseDelayMs, maxDelayMs);
  }

  static bool _defaultShouldRetry(dynamic error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    
    final errorString = error.toString().toLowerCase();
    return errorString.contains('timeout') ||
           errorString.contains('connection') ||
           errorString.contains('network') ||
           errorString.contains('502') ||
           errorString.contains('503') ||
           errorString.contains('504');
  }

  static Future<T> executeWithCircuitBreaker<T>({
    required Future<T> Function() operation,
    required String operationName,
  }) async {
    return CircuitBreaker.execute(
      operation: operation,
      operationName: operationName,
    );
  }
}

class CircuitBreaker {
  static final Map<String, CircuitBreakerState> _states = {};
  static const int failureThreshold = 5;
  static const Duration resetTimeout = Duration(minutes: 1);

  static Future<T> execute<T>({
    required Future<T> Function() operation,
    required String operationName,
  }) async {
    final state = _states.putIfAbsent(
      operationName,
      () => CircuitBreakerState(),
    );

    if (state.isOpen) {
      if (DateTime.now().difference(state.lastFailureTime!) > resetTimeout) {
        debugPrint('[CircuitBreaker] $operationName: Half-open, attempting reset');
        state.halfOpen();
      } else {
        debugPrint('[CircuitBreaker] $operationName: Circuit open, rejecting request');
        throw CircuitBreakerOpenException(operationName);
      }
    }

    try {
      final result = await operation();
      state.recordSuccess();
      return result;
    } catch (error) {
      state.recordFailure();
      
      if (state.isOpen) {
        debugPrint('[CircuitBreaker] $operationName: Circuit opened after ${state.failureCount} failures');
      }
      
      rethrow;
    }
  }

  static void reset(String operationName) {
    _states[operationName]?.reset();
  }

  static void resetAll() {
    _states.forEach((_, state) => state.reset());
  }
}

class CircuitBreakerState {
  int failureCount = 0;
  DateTime? lastFailureTime;
  bool isOpen = false;
  bool isHalfOpen = false;

  void recordSuccess() {
    failureCount = 0;
    isOpen = false;
    isHalfOpen = false;
    lastFailureTime = null;
  }

  void recordFailure() {
    failureCount++;
    lastFailureTime = DateTime.now();

    if (failureCount >= CircuitBreaker.failureThreshold) {
      isOpen = true;
      isHalfOpen = false;
    }
  }

  void halfOpen() {
    isHalfOpen = true;
    isOpen = false;
  }

  void reset() {
    failureCount = 0;
    lastFailureTime = null;
    isOpen = false;
    isHalfOpen = false;
  }
}

class CircuitBreakerOpenException implements Exception {
  final String operationName;
  CircuitBreakerOpenException(this.operationName);

  @override
  String toString() => 'Circuit breaker is open for operation: $operationName';
}

class SocketException implements Exception {
  final String message;
  SocketException(this.message);

  @override
  String toString() => 'SocketException: $message';
}
