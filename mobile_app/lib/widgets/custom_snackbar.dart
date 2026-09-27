import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';

enum SnackBarType { success, error, warning, info }

class CustomSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    Color backgroundColor;
    IconData icon;
    
    switch (type) {
      case SnackBarType.success:
        backgroundColor = AppColors.successColor;
        icon = Icons.check_circle;
        break;
      case SnackBarType.error:
        backgroundColor = AppColors.errorColor;
        icon = Icons.error;
        break;
      case SnackBarType.warning:
        backgroundColor = AppColors.warningColor;
        icon = Icons.warning;
        break;
      case SnackBarType.info:
        backgroundColor = AppColors.primaryColor;
        icon = Icons.info;
        break;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: AppConstants.paddingMD),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppConstants.fontSizeSM,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusSmall),
        ),
        action: onAction != null && actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
