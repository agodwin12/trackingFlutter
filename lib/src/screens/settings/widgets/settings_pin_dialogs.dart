// lib/src/screens/settings/widgets/settings_pin_dialogs.dart
import 'package:flutter/material.dart';
import '../../../core/utility/app_theme.dart';
import '../services/settings_service.dart';

class PinDialogs {
  // ========== SHOW CREATE PIN DIALOG ==========
  static void showCreatePinDialog({
    required BuildContext context,
    required int userId,
    required String selectedLanguage,
    required VoidCallback onPinCreated,
  }) {
    final TextEditingController newPinController = TextEditingController();
    final TextEditingController confirmPinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool isNewPinVisible = false;
        bool isConfirmPinVisible = false;
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusL),
              ),
              contentPadding: EdgeInsets.all(AppSizes.spacingL),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Text(
                    selectedLanguage == 'en' ? 'Create PIN' : 'Créer un PIN',
                    style: AppTypography.subtitle1.copyWith(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedLanguage == 'en'
                          ? 'Set up a 4-digit PIN for app security'
                          : 'Configurez un code PIN à 4 chiffres pour la sécurité',
                      style: AppTypography.body2.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingL),

                    // New PIN Field
                    Text(
                      selectedLanguage == 'en' ? 'New PIN' : 'Nouveau PIN',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    TextField(
                      controller: newPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: !isNewPinVisible,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isNewPinVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setDialogState(
                                  () => isNewPinVisible = !isNewPinVisible),
                        ),
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // Confirm PIN Field
                    Text(
                      selectedLanguage == 'en'
                          ? 'Confirm PIN'
                          : 'Confirmer le PIN',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingS),
                    TextField(
                      controller: confirmPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: !isConfirmPinVisible,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusM),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSizes.spacingM,
                          vertical: AppSizes.spacingS,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isConfirmPinVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setDialogState(
                                  () => isConfirmPinVisible = !isConfirmPinVisible),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                  isLoading ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    if (newPinController.text.length != 4) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'PIN must be 4 digits'
                            : 'Le PIN doit contenir 4 chiffres',
                        AppColors.error,
                      );
                      return;
                    }
                    if (newPinController.text !=
                        confirmPinController.text) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'PINs do not match'
                            : 'Les PINs ne correspondent pas',
                        AppColors.error,
                      );
                      return;
                    }

                    setDialogState(() => isLoading = true);

                    try {
                      await SettingsService.createPin(
                          userId, newPinController.text);
                      Navigator.pop(dialogContext);
                      onPinCreated();
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'PIN created successfully'
                            : 'PIN créé avec succès',
                        AppColors.success,
                      );
                    } catch (e) {
                      setDialogState(() => isLoading = false);
                      _showSnack(context, e.toString(), AppColors.error);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : Text(
                    selectedLanguage == 'en' ? 'Create' : 'Créer',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========== SHOW CHANGE PIN DIALOG ==========
  static void showChangePinDialog({
    required BuildContext context,
    required int userId,
    required String selectedLanguage,
  }) {
    final TextEditingController currentPinController = TextEditingController();
    final TextEditingController newPinController = TextEditingController();
    final TextEditingController confirmPinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool isCurrentPinVisible = false;
        bool isNewPinVisible = false;
        bool isConfirmPinVisible = false;
        bool isLoading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusL),
              ),
              contentPadding: EdgeInsets.all(AppSizes.spacingL),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_reset,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Text(
                    selectedLanguage == 'en'
                        ? 'Change PIN'
                        : 'Changer le PIN',
                    style: AppTypography.subtitle1.copyWith(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedLanguage == 'en'
                          ? 'Enter your current PIN and choose a new one'
                          : 'Entrez votre PIN actuel et choisissez-en un nouveau',
                      style: AppTypography.body2.copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppSizes.spacingL),

                    // Current PIN
                    _buildPinField(
                      label: selectedLanguage == 'en'
                          ? 'Current PIN'
                          : 'PIN actuel',
                      controller: currentPinController,
                      isVisible: isCurrentPinVisible,
                      onToggle: () => setDialogState(
                              () => isCurrentPinVisible = !isCurrentPinVisible),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // New PIN
                    _buildPinField(
                      label: selectedLanguage == 'en'
                          ? 'New PIN'
                          : 'Nouveau PIN',
                      controller: newPinController,
                      isVisible: isNewPinVisible,
                      onToggle: () => setDialogState(
                              () => isNewPinVisible = !isNewPinVisible),
                    ),
                    SizedBox(height: AppSizes.spacingM),

                    // Confirm PIN
                    _buildPinField(
                      label: selectedLanguage == 'en'
                          ? 'Confirm New PIN'
                          : 'Confirmer le nouveau PIN',
                      controller: confirmPinController,
                      isVisible: isConfirmPinVisible,
                      onToggle: () => setDialogState(
                              () => isConfirmPinVisible = !isConfirmPinVisible),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                  isLoading ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    if (currentPinController.text.length != 4) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'Please enter your current PIN'
                            : 'Veuillez entrer votre PIN actuel',
                        AppColors.error,
                      );
                      return;
                    }
                    if (newPinController.text.length != 4) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'New PIN must be 4 digits'
                            : 'Le nouveau PIN doit contenir 4 chiffres',
                        AppColors.error,
                      );
                      return;
                    }
                    if (newPinController.text !=
                        confirmPinController.text) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'PINs do not match'
                            : 'Les PINs ne correspondent pas',
                        AppColors.error,
                      );
                      return;
                    }
                    if (currentPinController.text ==
                        newPinController.text) {
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'New PIN must be different from current PIN'
                            : 'Le nouveau PIN doit être différent du PIN actuel',
                        AppColors.error,
                      );
                      return;
                    }

                    setDialogState(() => isLoading = true);

                    try {
                      await SettingsService.changePin(
                        userId,
                        currentPinController.text,
                        newPinController.text,
                      );
                      Navigator.pop(dialogContext);
                      _showSnack(
                        context,
                        selectedLanguage == 'en'
                            ? 'PIN changed successfully'
                            : 'PIN changé avec succès',
                        AppColors.success,
                      );
                    } catch (e) {
                      setDialogState(() => isLoading = false);
                      _showSnack(context, e.toString(), AppColors.error);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : Text(
                    selectedLanguage == 'en' ? 'Change' : 'Changer',
                    style: AppTypography.body2.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========== HELPER: PIN TEXT FIELD ==========
  static Widget _buildPinField({
    required String label,
    required TextEditingController controller,
    required bool isVisible,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body2.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: !isVisible,
          decoration: InputDecoration(
            hintText: '••••',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  // ========== HELPER: SHOW SNACKBAR ==========
  static void _showSnack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.body2.copyWith(color: AppColors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
        ),
        margin: EdgeInsets.all(AppSizes.spacingM),
      ),
    );
  }
}