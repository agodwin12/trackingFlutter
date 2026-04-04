// lib/src/widgets/subscription_upgrade_sheet.dart

import 'package:flutter/material.dart';
import '../core/utility/app_theme.dart';

class _FeatureMeta {
  final String title;
  final String description;
  final IconData icon;

  const _FeatureMeta({
    required this.title,
    required this.description,
    required this.icon,
  });
}

const _featureMap = {
  'live_tracking': _FeatureMeta(
    title: 'Live Tracking',
    description:
    'See your vehicle\'s real-time position, speed, and status at any time.',
    icon: Icons.location_on_rounded,
  ),
  'geofence': _FeatureMeta(
    title: 'Geofencing',
    description:
    'Get alerted instantly when your vehicle enters or exits a defined zone.',
    icon: Icons.fence_rounded,
  ),
  'safe_zone': _FeatureMeta(
    title: 'Safe Zone',
    description:
    'Define a home zone and receive alerts when your vehicle leaves it.',
    icon: Icons.shield_rounded,
  ),
  'trip_history': _FeatureMeta(
    title: 'Trip History',
    description:
    'View past routes, distances, durations, and driving statistics.',
    icon: Icons.route_rounded,
  ),
  'engine_control': _FeatureMeta(
    title: 'Engine Control',
    description: 'Remotely turn your vehicle\'s engine on or off from the app.',
    icon: Icons.power_settings_new_rounded,
  ),
  'report_stolen': _FeatureMeta(
    title: 'Theft Report',
    description:
    'Report your vehicle stolen and automatically lock the engine.',
    icon: Icons.gpp_bad_rounded,
  ),
};

class SubscriptionUpgradeSheet extends StatelessWidget {
  final String feature;

  /// Named constructor used everywhere in the app.
  /// The old private `._()` constructor is replaced by this so callers
  /// can instantiate it directly (e.g. inside showModalBottomSheet).
  const SubscriptionUpgradeSheet.forFeature({
    Key? key,
    required this.feature,
  }) : super(key: key);

  /// Convenience static helper — shows the sheet and returns the Future from
  /// showModalBottomSheet so callers can attach .whenComplete() if needed.
  ///
  /// Usage (simple):
  ///   SubscriptionUpgradeSheet.show(context, feature: 'live_tracking');
  ///
  /// Usage (with dismiss callback):
  ///   SubscriptionUpgradeSheet.show(context, feature: 'geofence')
  ///     .whenComplete(() => controller.resetUpgradeSheet());
  static Future<void> show(
      BuildContext context, {
        required String feature,
      }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Prevent the sheet from being dismissed by tapping the barrier so
      // the user is forced to make an explicit choice (upgrade or not now).
      isDismissible: true,
      builder: (_) => SubscriptionUpgradeSheet.forFeature(feature: feature),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _featureMap[feature] ??
        const _FeatureMeta(
          title: 'This Feature',
          description:
          'This feature is not included in your current subscription.',
          icon: Icons.lock_rounded,
        );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // ── Lock icon ────────────────────────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              meta.icon,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ────────────────────────────────────────────────────────
          Text(
            '${meta.title} Not Included',
            style: AppTypography.body2.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // ── Description ──────────────────────────────────────────────────
          Text(
            meta.description,
            style: AppTypography.body2.copyWith(
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            'Upgrade your subscription plan to unlock this feature.',
            style: AppTypography.body2.copyWith(
              color: Colors.grey.shade500,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── Upgrade button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/subscription-plans');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                'View Subscription Plans',
                style: AppTypography.button.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Dismiss button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Not Now',
                style: AppTypography.button.copyWith(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}