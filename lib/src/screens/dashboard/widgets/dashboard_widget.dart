// lib/screens/dashboard/widgets/dashboard_widgets.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utility/app_theme.dart';
import '../services/dashboard_controller.dart';


// ==================== COMPACT GEOFENCE CARD ====================
class CompactGeofenceCard extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback onTap;

  const CompactGeofenceCard({
    Key? key,
    required this.controller,
    required this.onTap, required String selectedLanguage,
  }) : super(key: key);

  @override
  State<CompactGeofenceCard> createState() => _CompactGeofenceCardState();
}

class _CompactGeofenceCardState extends State<CompactGeofenceCard> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.controller.isTogglingGeofence ? null : widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.controller.geofenceEnabled
                ? [Color(0xFF10B981), Color(0xFF059669)]
                : [Color(0xFFEF4444), Color(0xFFDC2626)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (widget.controller.geofenceEnabled ? Color(0xFF10B981) : Color(0xFFEF4444))
                  .withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.controller.geofenceEnabled
                  ? Icons.location_on_rounded
                  : Icons.location_off_rounded,
              color: AppColors.white,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              _selectedLanguage == 'en' ? 'Geofence' : 'Géofence',
              style: AppTypography.body1.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            SizedBox(width: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.controller.geofenceEnabled ? 'ON' : 'OFF',
                style: AppTypography.caption.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== COMPACT SAFE ZONE CARD ====================
class CompactSafeZoneCard extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback onTap;

  const CompactSafeZoneCard({
    Key? key,
    required this.controller,
    required this.onTap, required String selectedLanguage,
  }) : super(key: key);

  @override
  State<CompactSafeZoneCard> createState() => _CompactSafeZoneCardState();
}

class _CompactSafeZoneCardState extends State<CompactSafeZoneCard> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.controller.isTogglingSafeZone ? null : widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.controller.safeZoneEnabled
                ? [Color(0xFF10B981), Color(0xFF059669)]
                : [Color(0xFFEF4444), Color(0xFFDC2626)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (widget.controller.safeZoneEnabled ? Color(0xFF10B981) : Color(0xFFEF4444))
                  .withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.controller.safeZoneEnabled ? Icons.shield_rounded : Icons.shield_outlined,
              color: AppColors.white,
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              _selectedLanguage == 'en' ? 'Safe Zone' : 'zone de sécurité',
              style: AppTypography.body1.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            SizedBox(width: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),

              child: Text(
                widget.controller.safeZoneEnabled ? 'ON' : 'OFF',
                style: AppTypography.caption.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== QUICK ACTION BUTTON ====================
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 16),
            SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.body1.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== VEHICLE SELECTOR MODAL ====================
class VehicleSelectorModal extends StatefulWidget {
  final DashboardController controller;
  final Function(int) onVehicleSelected;

  const VehicleSelectorModal({
    Key? key,
    required this.controller,
    required this.onVehicleSelected, required String selectedLanguage,
  }) : super(key: key);

  @override
  State<VehicleSelectorModal> createState() => _VehicleSelectorModalState();
}

class _VehicleSelectorModalState extends State<VehicleSelectorModal> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.radiusXL),
          topRight: Radius.circular(AppSizes.radiusXL),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: AppSizes.spacingM),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: AppSizes.spacingL),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSizes.spacingL),
            child: Text(
              _selectedLanguage == 'en' ? 'Select Vehicle' : 'Choisir un véhicule',
              style: AppTypography.h3,
            ),
          ),
          SizedBox(height: AppSizes.spacingL),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.controller.vehicles.length,
              itemBuilder: (context, index) {
                final vehicle = widget.controller.vehicles[index];
                final isSelected = vehicle.id == widget.controller.selectedVehicleId;
                final hasNickname = vehicle.nickname.isNotEmpty;

                return InkWell(
                  onTap: () {
                    widget.onVehicleSelected(vehicle.id);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: AppSizes.spacingL,
                      vertical: AppSizes.spacingXS,
                    ),
                    padding: EdgeInsets.all(AppSizes.spacingM),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Car Icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.controller.hexToColor(vehicle.color).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: widget.controller.hexToColor(vehicle.color),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.directions_car_rounded,
                            color: widget.controller.hexToColor(vehicle.color),
                            size: 20,
                          ),
                        ),
                        SizedBox(width: AppSizes.spacingM),

                        // Vehicle Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Nickname or "Add nickname" prompt
                              if (hasNickname)
                                Text(
                                  vehicle.nickname,
                                  style: AppTypography.body1.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.black,
                                    fontSize: 15,
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(context, '/my-cars');
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline,
                                        size: 14,
                                        color: AppColors.primary,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        _selectedLanguage == 'en' ? 'Add nickname' : 'Ajouter un surnom',
                                        style: AppTypography.body2.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              SizedBox(height: 3),

                              // Brand + Model
                              Text(
                                '${vehicle.brand} ${vehicle.model}',
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),

                              SizedBox(height: 2),

                              // Immatriculation
                              Text(
                                vehicle.immatriculation,
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: AppColors.textSecondary.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Online Status Badge
                        if (vehicle.isOnline)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _selectedLanguage == 'en' ? 'Online' : 'En ligne',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Selected Check
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: AppSizes.spacingL),
        ],
      ),
    );
  }
}

// ==================== ENGINE CONFIRM DIALOG ====================
class EngineConfirmDialog extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback onConfirm;

  const EngineConfirmDialog({
    Key? key,
    required this.controller,
    required this.onConfirm, required String selectedLanguage,
  }) : super(key: key);

  @override
  State<EngineConfirmDialog> createState() => _EngineConfirmDialogState();
}

class _EngineConfirmDialogState extends State<EngineConfirmDialog> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool willTurnOn = !widget.controller.engineOn;
    final vehicle = widget.controller.selectedVehicle;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
      ),
      contentPadding: EdgeInsets.all(AppSizes.spacingL),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (willTurnOn ? AppColors.success : AppColors.error)
                  .withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              willTurnOn ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: willTurnOn ? AppColors.success : AppColors.error,
              size: 20,
            ),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              willTurnOn
                  ? (_selectedLanguage == 'en' ? 'Unlock Engine' : 'Déverrouiller le moteur')
                  : (_selectedLanguage == 'en' ? 'Lock Engine' : 'Verrouiller le moteur'),
              style: AppTypography.subtitle1.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        willTurnOn
            ? (_selectedLanguage == 'en'
            ? 'Unlock ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "vehicle"}\'s engine?'
            : 'Déverrouiller le moteur de ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "véhicule"} ?')
            : (_selectedLanguage == 'en'
            ? 'Lock ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "vehicle"}\'s engine?'
            : 'Verrouiller le moteur de ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "véhicule"} ?'),
        style: AppTypography.body2.copyWith(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
            style: AppTypography.body2.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: willTurnOn ? AppColors.success : AppColors.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(
            _selectedLanguage == 'en' ? 'Confirm' : 'Confirmer',
            style: AppTypography.body2.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== REPORT STOLEN DIALOG ====================
class ReportStolenDialog extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback onConfirm;

  const ReportStolenDialog({
    Key? key,
    required this.controller,
    required this.onConfirm, required String selectedLanguage,
  }) : super(key: key);

  @override
  State<ReportStolenDialog> createState() => _ReportStolenDialogState();
}

class _ReportStolenDialogState extends State<ReportStolenDialog> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.controller.selectedVehicle;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
      ),
      contentPadding: EdgeInsets.all(AppSizes.spacingL),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_rounded,
                color: AppColors.error, size: 20),
          ),
          SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: Text(
              _selectedLanguage == 'en' ? 'Report Stolen' : 'Signaler le vol',
              style: AppTypography.subtitle1.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedLanguage == 'en'
                ? 'Report ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "vehicle"} as stolen?'
                : 'Signaler ${vehicle?.nickname.isNotEmpty == true ? vehicle!.nickname : "véhicule"} comme volé ?',
            style: AppTypography.body2.copyWith(fontSize: 13),
          ),
          SizedBox(height: AppSizes.spacingM),
          Container(
            padding: EdgeInsets.all(AppSizes.spacingS),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(
                color: AppColors.error.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.error,
                  size: 16,
                ),
                SizedBox(width: AppSizes.spacingS),
                Expanded(
                  child: Text(
                    _selectedLanguage == 'en'
                        ? 'Engine will be cut off immediately'
                        : 'Le moteur sera coupé immédiatement',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
            style: AppTypography.body2.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(
            _selectedLanguage == 'en' ? 'Report' : 'Signaler',
            style: AppTypography.body2.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}