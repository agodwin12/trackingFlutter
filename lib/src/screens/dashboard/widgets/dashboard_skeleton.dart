import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/utility/app_theme.dart';

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header Skeleton
            _buildHeaderSkeleton(),

            // Map + Controls Skeleton
            Expanded(
              child: Stack(
                children: [
                  // Map placeholder
                  Container(
                    color: AppColors.border.withOpacity(0.3),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 80,
                        color: AppColors.border,
                      ),
                    ),
                  ),

                  // Floating Vehicle Selector Skeleton
                  _buildFloatingVehicleSkeleton(),

                  // Bottom Controls Skeleton
                  _buildBottomControlsSkeleton(),
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
        vertical: AppSizes.spacingS,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo skeleton
          _buildShimmerBox(120, 24),

          Row(
            children: [
              // Battery indicator skeleton
              _buildShimmerBox(60, 24),
              SizedBox(width: 12),
              // Notification icon skeleton
              _buildShimmerCircle(24),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingVehicleSkeleton() {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: _buildShimmerBox(180, 40, borderRadius: 20),
      ),
    );
  }

  Widget _buildBottomControlsSkeleton() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: AppColors.background,
        padding: EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Geofence + Safe Zone skeleton
            Row(
              children: [
                Expanded(
                  child: _buildShimmerBox(double.infinity, 80, borderRadius: 12),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _buildShimmerBox(double.infinity, 80, borderRadius: 12),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Quick Actions skeleton
            Row(
              children: [
                Expanded(
                  child: _buildShimmerBox(double.infinity, 56, borderRadius: 12),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _buildShimmerBox(double.infinity, 56, borderRadius: 12),
                ),
              ],
            ),
          ],
        ),
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

  Widget _buildShimmerCircle(double size) {
    return Shimmer.fromColors(
      baseColor: AppColors.border.withOpacity(0.3),
      highlightColor: AppColors.white,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}