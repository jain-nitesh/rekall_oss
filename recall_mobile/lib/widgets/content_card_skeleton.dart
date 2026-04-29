import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/constants.dart';

/// Shimmer loading skeleton for content cards
/// Premium skeletal loading with glassmorphism aesthetic
class ContentCardSkeleton extends StatelessWidget {
  final bool compact;

  const ContentCardSkeleton({
    super.key,
    this.compact = false,
  });

  factory ContentCardSkeleton.compact() {
    return const ContentCardSkeleton(compact: true);
  }

  factory ContentCardSkeleton.full() {
    return const ContentCardSkeleton(compact: false);
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactSkeleton();
    } else {
      return _buildFullSkeleton();
    }
  }

  Widget _buildCompactSkeleton() {
    return Container(
      width: 250,
      margin: const EdgeInsets.only(right: AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: AppConstants.borderColor,
          width: AppConstants.borderWidthThin,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        period: const Duration(milliseconds: 1500),
        direction: ShimmerDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail placeholder
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),

              // Source icon placeholder
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppConstants.dividerColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),

              // Title placeholder
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXS),
              Container(
                height: 14,
                width: 150,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),

              // Summary placeholder
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXS),
              Container(
                height: 12,
                width: 180,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),

              // Time placeholder
              Container(
                height: 11,
                width: 80,
                decoration: BoxDecoration(
                  color: AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: AppConstants.borderColor,
          width: AppConstants.borderWidthThin,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        period: const Duration(milliseconds: 1500),
        direction: ShimmerDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail placeholder
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppConstants.dividerColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusL),
                  topRight: Radius.circular(AppConstants.radiusL),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header placeholder
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: AppConstants.dividerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppConstants.dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 12,
                        width: 60,
                        decoration: BoxDecoration(
                          color: AppConstants.dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacingM),

                  // Title placeholder
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXS),
                  Container(
                    height: 16,
                    width: 200,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingS),

                  // Summary placeholder
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXS),
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXS),
                  Container(
                    height: 14,
                    width: 250,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingM),

                  // Tags placeholder
                  Row(
                    children: [
                      Container(
                        height: 24,
                        width: 60,
                        decoration: BoxDecoration(
                          color: AppConstants.dividerColor,
                          borderRadius: BorderRadius.circular(AppConstants.radiusM),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      Container(
                        height: 24,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppConstants.dividerColor,
                          borderRadius: BorderRadius.circular(AppConstants.radiusM),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
