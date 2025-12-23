import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/utility/app_theme.dart';


class NotificationsSkeleton extends StatelessWidget {
  const NotificationsSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header Skeleton
            _buildHeaderSkeleton(),

            // Tabs Skeleton
            _buildTabsSkeleton(),

            // Notifications List Skeleton
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(AppSizes.spacingM),
                itemCount: 8, // Show 8 skeleton cards
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: AppSizes.spacingM),
                    child: _buildNotificationCardSkeleton(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL,
        vertical: AppSizes.spacingM,
      ),
      child: Row(
        children: [
          _buildShimmerBox(24, 24),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(140, 18, borderRadius: 4),
                SizedBox(height: 4),
                _buildShimmerBox(80, 12, borderRadius: 4),
              ],
            ),
          ),
          _buildShimmerBox(24, 24),
          SizedBox(width: AppSizes.spacingS),
          _buildShimmerBox(24, 24),
        ],
      ),
    );
  }

  Widget _buildTabsSkeleton() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingL,
        vertical: AppSizes.spacingM,
      ),
      child: Row(
        children: [
          _buildShimmerBox(60, 16, borderRadius: 4),
          SizedBox(width: AppSizes.spacingL),
          _buildShimmerBox(80, 16, borderRadius: 4),
          SizedBox(width: AppSizes.spacingL),
          _buildShimmerBox(70, 16, borderRadius: 4),
          SizedBox(width: AppSizes.spacingL),
          _buildShimmerBox(60, 16, borderRadius: 4),
        ],
      ),
    );
  }

  Widget _buildNotificationCardSkeleton() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingM),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon placeholder
          _buildShimmerBox(40, 40, borderRadius: 10),
          SizedBox(width: AppSizes.spacingM),

          // Content placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildShimmerBox(120, 14, borderRadius: 4)),
                    SizedBox(width: AppSizes.spacingS),
                    _buildShimmerBox(40, 12, borderRadius: 4),
                  ],
                ),
                SizedBox(height: 8),
                _buildShimmerBox(double.infinity, 12, borderRadius: 4),
                SizedBox(height: 4),
                _buildShimmerBox(200, 12, borderRadius: 4),
              ],
            ),
          ),

          SizedBox(width: AppSizes.spacingS),

          // Action button placeholder
          _buildShimmerBox(24, 24, borderRadius: 8),
        ],
      ),
    );
  }

  Widget _buildShimmerBox(double width, double height, {double borderRadius = 8}) {
    return Shimmer.fromColors(
      baseColor: AppColors.border.withOpacity(0.3),
      highlightColor: AppColors.white,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}