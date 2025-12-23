import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/utility/app_theme.dart';

class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header Skeleton
            _buildHeaderSkeleton(),

            // Content Skeleton
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(AppSizes.spacingL),
                children: [
                  // Alerts Section
                  _buildSectionHeaderSkeleton(),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingTileSkeleton(),
                  _buildSettingTileSkeleton(),
                  _buildSettingTileSkeleton(),

                  SizedBox(height: AppSizes.spacingXL),

                  // Security Section
                  _buildSectionHeaderSkeleton(),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingTileSkeleton(),

                  SizedBox(height: AppSizes.spacingXL),

                  // Account Section
                  _buildSectionHeaderSkeleton(),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingTileSkeleton(),
                  _buildSettingTileSkeleton(),

                  SizedBox(height: AppSizes.spacingXL),

                  // Support Section
                  _buildSectionHeaderSkeleton(),
                  SizedBox(height: AppSizes.spacingM),
                  _buildSettingTileSkeleton(),

                  SizedBox(height: AppSizes.spacingXL),

                  // Logout Button Skeleton
                  _buildLogoutButtonSkeleton(),
                ],
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
          Expanded(child: _buildShimmerBox(120, 24)),
          _buildShimmerBox(60, 40, borderRadius: 12),
        ],
      ),
    );
  }

  Widget _buildSectionHeaderSkeleton() {
    return _buildShimmerBox(80, 12, borderRadius: 4);
  }

  Widget _buildSettingTileSkeleton() {
    return Container(
      margin: EdgeInsets.only(bottom: AppSizes.spacingS),
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingM,
        vertical: AppSizes.spacingM,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon placeholder
          _buildShimmerBox(40, 40, borderRadius: 10),
          SizedBox(width: AppSizes.spacingM),

          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(120, 14, borderRadius: 4),
                SizedBox(height: 6),
                _buildShimmerBox(180, 12, borderRadius: 4),
              ],
            ),
          ),

          // Trailing placeholder
          _buildShimmerBox(24, 24, borderRadius: 4),
        ],
      ),
    );
  }

  Widget _buildLogoutButtonSkeleton() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.spacingM,
        vertical: AppSizes.spacingM,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _buildShimmerBox(40, 40, borderRadius: 10),
          SizedBox(width: AppSizes.spacingM),
          Expanded(child: _buildShimmerBox(80, 16, borderRadius: 4)),
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