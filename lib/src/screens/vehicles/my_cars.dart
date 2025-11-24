// lib/src/screens/vehicles/my_cars_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/env_config.dart';
import '../profile/profile.dart';
import '../../core/utility/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyCarsScreen extends StatefulWidget {
  const MyCarsScreen({Key? key}) : super(key: key);

  @override
  State<MyCarsScreen> createState() => _MyCarsScreenState();
}

class _MyCarsScreenState extends State<MyCarsScreen> {
  List vehicles = [];
  bool isLoading = true;
  int? _userId;
  String _selectedLanguage = 'en';

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _loadUserId();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ My Cars screen loaded language preference: $_selectedLanguage');
  }

  Future<void> _loadUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        setState(() {
          _userId = userData['id'];
        });
        await fetchMyCars();
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('🔥 Error loading user ID: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchMyCars() async {
    if (_userId == null) {
      setState(() => isLoading = false);
      return;
    }

    final url = "$baseUrl/voitures/user/$_userId";

    try {
      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data["success"]) {
        setState(() {
          vehicles = data["vehicles"];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('🔥 Error fetching vehicles: $e');
      setState(() => isLoading = false);
    }
  }

  void _showEditNicknameDialog(Map<String, dynamic> vehicle) {
    showDialog(
      context: context,
      builder: (context) => _NicknameEditDialog(
        vehicle: vehicle,
        selectedLanguage: _selectedLanguage,
        onSave: (nickname) => _updateNickname(vehicle['id'], nickname),
      ),
    );
  }

  Future<void> _updateNickname(int vehicleId, String nickname) async {
    try {
      debugPrint('💾 Updating nickname for vehicle $vehicleId: "$nickname"');

      final response = await http.put(
        Uri.parse('$baseUrl/vehicles/$vehicleId/nickname'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': nickname.isEmpty ? null : nickname}),
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          debugPrint('✅ Nickname updated successfully');
          await fetchMyCars();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.white, size: 20),
                    SizedBox(width: AppSizes.spacingM),
                    Expanded(
                      child: Text(
                        nickname.isEmpty
                            ? (_selectedLanguage == 'en' ? 'Nickname removed' : 'Surnom supprimé')
                            : (_selectedLanguage == 'en' ? 'Nickname updated' : 'Surnom mis à jour'),
                        style: AppTypography.body2.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                ),
                margin: EdgeInsets.all(AppSizes.spacingM),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update nickname');
        }
      } else {
        throw Exception('Failed to update nickname: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('🔥 Error updating nickname: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.white, size: 20),
                SizedBox(width: AppSizes.spacingM),
                Text(
                  _selectedLanguage == 'en'
                      ? 'Failed to update nickname'
                      : 'Échec de la mise à jour du surnom',
                  style: AppTypography.body2.copyWith(color: AppColors.white),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            margin: EdgeInsets.all(AppSizes.spacingM),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.black),
        ),
        title: Text(
          _selectedLanguage == 'en' ? 'My Vehicles' : 'Mes Véhicules',
          style: AppTypography.h3.copyWith(fontSize: 18),
        ),
      ),
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      )
          : vehicles.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: fetchMyCars,
        color: AppColors.primary,
        child: ListView.builder(
          padding: EdgeInsets.all(AppSizes.spacingM),
          itemCount: vehicles.length,
          itemBuilder: (context, index) {
            final vehicle = vehicles[index];
            return _buildCleanCarCard(vehicle);
          },
        ),
      ),
    );
  }

  Widget _buildCleanCarCard(Map<String, dynamic> vehicle) {
    final hasNickname = vehicle['nickname'] != null &&
        vehicle['nickname'].toString().isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: AppSizes.spacingM),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(vehicleId: vehicle['id']),
              ),
            );
          },
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          child: Padding(
            padding: EdgeInsets.all(AppSizes.spacingM),
            child: Row(
              children: [
                // Car Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),

                SizedBox(width: AppSizes.spacingM),

                // Car Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nickname (if exists) or Brand/Model
                      Text(
                        hasNickname
                            ? vehicle['nickname']
                            : '${vehicle["marque"]} ${vehicle["model"]}',
                        style: AppTypography.subtitle1.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      SizedBox(height: 3),

                      // Brand/Model (if nickname exists) or Plate
                      Text(
                        hasNickname
                            ? '${vehicle["marque"]} ${vehicle["model"]}'
                            : vehicle["immatriculation"],
                        style: AppTypography.body2.copyWith(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),

                      // Plate (if nickname exists)
                      if (hasNickname) ...[
                        SizedBox(height: 2),
                        Text(
                          vehicle["immatriculation"],
                          style: AppTypography.caption.copyWith(
                            fontSize: 12,
                            color: AppColors.textSecondary.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Edit Button
                IconButton(
                  onPressed: () => _showEditNicknameDialog(vehicle),
                  icon: Icon(
                    Icons.edit_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSizes.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: AppSizes.spacingL),
            Text(
              _selectedLanguage == 'en' ? 'No Vehicles Found' : 'Aucun véhicule trouvé',
              style: AppTypography.h3.copyWith(fontSize: 18),
            ),
            SizedBox(height: AppSizes.spacingS),
            Text(
              _selectedLanguage == 'en'
                  ? 'You don\'t have any vehicles registered yet'
                  : 'Vous n\'avez aucun véhicule enregistré pour le moment',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Separate StatefulWidget for Dialog
class _NicknameEditDialog extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final String selectedLanguage;
  final Function(String) onSave;

  const _NicknameEditDialog({
    required this.vehicle,
    required this.selectedLanguage,
    required this.onSave,
  });

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.vehicle['nickname'] ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.edit_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          SizedBox(width: AppSizes.spacingM),
          Text(
            widget.selectedLanguage == 'en' ? 'Edit Nickname' : 'Modifier le surnom',
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
              '${widget.selectedLanguage == 'en' ? 'Vehicle' : 'Véhicule'}: ${widget.vehicle["marque"]} ${widget.vehicle["model"]}',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            SizedBox(height: AppSizes.spacingM),
            TextField(
              controller: _controller,
              maxLength: 50,
              autofocus: true,
              style: AppTypography.body1.copyWith(fontSize: 14),
              decoration: InputDecoration(
                labelText: widget.selectedLanguage == 'en' ? 'Nickname' : 'Surnom',
                hintText: widget.selectedLanguage == 'en'
                    ? 'e.g., Patrick, My Car'
                    : 'ex: Patrick, Ma voiture',
                labelStyle: AppTypography.body2.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                hintStyle: AppTypography.body2.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary.withOpacity(0.5),
                ),
                prefixIcon: Icon(
                  Icons.label_outline,
                  size: 18,
                  color: AppColors.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSizes.spacingM,
                  vertical: AppSizes.spacingS,
                ),
              ),
            ),
            SizedBox(height: AppSizes.spacingS),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: AppSizes.spacingXS),
                Expanded(
                  child: Text(
                    widget.selectedLanguage == 'en'
                        ? 'Leave empty to remove nickname'
                        : 'Laisser vide pour supprimer le surnom',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
            style: AppTypography.body2.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final nickname = _controller.text.trim();
            Navigator.pop(context);
            widget.onSave(nickname);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(
            widget.selectedLanguage == 'en' ? 'Save' : 'Enregistrer',
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