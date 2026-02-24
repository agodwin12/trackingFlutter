// lib/src/screens/settings/widgets/settings_widgets.dart
import 'package:flutter/material.dart';
import '../../../core/utility/app_theme.dart';

// ========== SECTION HEADER ==========
class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({Key? key, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ========== SETTINGS TILE ==========
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsTile({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSizes.spacingS),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
        title: Text(
          title,
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.caption.copyWith(fontSize: 12),
        ),
        trailing: trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS,
        ),
      ),
    );
  }
}

// ========== TOGGLE SETTINGS TILE ==========
class SettingsToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleTile({
    Key? key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.white,
          activeTrackColor: AppColors.success,
          inactiveThumbColor: AppColors.white,
          inactiveTrackColor: AppColors.error,
        ),
      ),
    );
  }
}

// ========== LOGOUT BUTTON ==========
class SettingsLogoutButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const SettingsLogoutButton({
    Key? key,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.error, width: 1),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.logout_rounded, color: AppColors.error, size: 22),
        ),
        title: Text(
          label,
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.error,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingM,
          vertical: AppSizes.spacingS,
        ),
      ),
    );
  }
}

// ========== LANGUAGE OPTION TILE ==========
class LanguageOptionTile extends StatelessWidget {
  final String languageCode;
  final String languageName;
  final String flagEmoji;
  final bool isSelected;
  final VoidCallback onTap;

  const LanguageOptionTile({
    Key? key,
    required this.languageCode,
    required this.languageName,
    required this.flagEmoji,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.all(AppSizes.spacingM),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(flagEmoji, style: const TextStyle(fontSize: 32)),
              ),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                languageName,
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isSelected ? AppColors.primary : AppColors.black,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: AppColors.primary, size: 24),
          ],
        ),
      ),
    );
  }
}