import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/connection_provider.dart';
import '../config/app_colors.dart';

class ConnectionStatusIndicator extends StatelessWidget {
  final bool compact;
  final bool showLabel;

  const ConnectionStatusIndicator({
    super.key,
    this.compact = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, provider, _) {
        final isConnected = provider.isConnected;
        final isChecking  = provider.isChecking || provider.isWakingUp;

        final dotColor = isConnected
            ? AppColors.success
            : (isChecking ? AppColors.warning : AppColors.error);

        final label = isConnected
            ? 'Connected'
            : (isChecking ? 'Connecting…' : 'Offline');

        Widget dot = Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        );

        if (isConnected) {
          dot = dot
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 1.0, end: 0.3, duration: 900.ms);
        } else if (isChecking) {
          dot = dot
              .animate(onPlay: (c) => c.repeat())
              .fade(begin: 1.0, end: 0.2, duration: 600.ms)
              .then()
              .fade(begin: 0.2, end: 1.0, duration: 600.ms);
        }

        if (compact) return dot;

        return GestureDetector(
          onTap: () => provider.checkConnection(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? AppColors.success.withOpacity(0.35)
                    : (isChecking
                        ? AppColors.warning.withOpacity(0.35)
                        : AppColors.error.withOpacity(0.35)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot,
                if (showLabel) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isConnected
                          ? AppColors.success
                          : (isChecking ? AppColors.warning : AppColors.textSecondary),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, provider, _) {
        if (provider.isConnected || provider.isChecking || provider.isWakingUp) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.08),
            border: Border(
              bottom: BorderSide(color: AppColors.error.withOpacity(0.2)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded,
                  color: AppColors.error.withOpacity(0.8), size: 15),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'API server unreachable',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => provider.checkConnection(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderDefault),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
