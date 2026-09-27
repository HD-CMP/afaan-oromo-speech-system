import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class GlassmorphismCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final double blurSigma;
  final Border? border;

  const GlassmorphismCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.blurSigma = 12,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface.withOpacity(0.7),
            borderRadius: radius,
            border: border ?? Border.all(color: AppColors.borderDefault, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
