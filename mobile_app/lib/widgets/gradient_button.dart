import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class GradientButton extends StatelessWidget {
  final String? text;
  final String? label;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final double? width;
  final double? height;
  final IconData? icon;
  final bool isLoading;

  const GradientButton({
    super.key,
    this.text,
    this.label,
    this.onPressed,
    this.gradient,
    this.width,
    this.height,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = (onPressed == null) && !isLoading;
    return AnimatedOpacity(
      opacity: isDisabled ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: width ?? double.infinity,
        height: height ?? 54,
        decoration: BoxDecoration(
          gradient: isDisabled
              ? const LinearGradient(
                  colors: [AppColors.surface3, AppColors.surface3])
              : (gradient ?? AppColors.primaryGradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDisabled
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(14),
            splashColor: Colors.white.withOpacity(0.1),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          text ?? label ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
