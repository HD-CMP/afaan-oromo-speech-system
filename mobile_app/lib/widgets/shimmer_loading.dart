import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';

class ShimmerLoading extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  
  const ShimmerLoading({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.cardDark : Colors.grey[300]!,
      highlightColor: isDark ? AppColors.dividerDark : Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? 
              BorderRadius.circular(AppConstants.borderRadiusSmall),
        ),
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerLoading(
              width: double.infinity,
              height: 20,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: AppConstants.paddingSM),
            ShimmerLoading(
              width: 200,
              height: 16,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: AppConstants.paddingSM),
            ShimmerLoading(
              width: 150,
              height: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}
