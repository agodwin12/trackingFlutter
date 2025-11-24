// lib/src/screens/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';

class ProfileScreen extends StatefulWidget {
  final int vehicleId;

  const ProfileScreen({Key? key, required this.vehicleId}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> userData = {};
  bool isLoading = true;
  String _selectedLanguage = 'en';

  // Edit Profile Controllers
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Change Password Controllers
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  String get baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _loadLanguagePreference();
    fetchUserData();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Profile screen loaded language preference: $_selectedLanguage');
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> fetchUserData() async {
    final String url = "$baseUrl/users/vehicle/${widget.vehicleId}";

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["success"] == true) {
          setState(() {
            userData = data["user"];
            isLoading = false;
          });

          // Initialize edit controllers
          _prenomController.text = userData['prenom'] ?? '';
          _nomController.text = userData['nom'] ?? '';
          _phoneController.text = userData['phone'] ?? '';
          _emailController.text = userData['email'] ?? '';
        }
      }
    } catch (e) {
      debugPrint("🔥 Fetch user error: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');

      final response = await http.put(
        Uri.parse('$baseUrl/users/${userData["id"]}'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'prenom': _prenomController.text,
          'nom': _nomController.text,
          'phone': _phoneController.text,
          'email': _emailController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            userData = data['user'];
          });

          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.white, size: 20),
                  SizedBox(width: AppSizes.spacingM),
                  Text(_selectedLanguage == 'en'
                      ? 'Profile updated successfully!'
                      : 'Profil mis à jour avec succès !'),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              margin: EdgeInsets.all(AppSizes.spacingM),
            ),
          );
        }
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (error) {
      debugPrint('🔥 Error updating profile: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedLanguage == 'en'
              ? 'Failed to update profile'
              : 'Échec de la mise à jour du profil'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedLanguage == 'en'
              ? 'Passwords do not match'
              : 'Les mots de passe ne correspondent pas'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedLanguage == 'en'
              ? 'Password must be at least 6 characters'
              : 'Le mot de passe doit contenir au moins 6 caractères'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken');

      final response = await http.post(
        Uri.parse('$baseUrl/users/change-password'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userData['id'],
          'oldPassword': _oldPasswordController.text,
          'newPassword': _newPasswordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Navigator.pop(context);

          // Clear password fields
          _oldPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.white, size: 20),
                  SizedBox(width: AppSizes.spacingM),
                  Text(_selectedLanguage == 'en'
                      ? 'Password changed successfully!'
                      : 'Mot de passe changé avec succès !'),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              margin: EdgeInsets.all(AppSizes.spacingM),
            ),
          );
        }
      } else {
        throw Exception('Failed to change password');
      }
    } catch (error) {
      debugPrint('🔥 Error changing password: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedLanguage == 'en'
              ? 'Failed to change password. Check old password.'
              : 'Échec du changement de mot de passe. Vérifiez l\'ancien mot de passe.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              child: Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
                style: AppTypography.subtitle1.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          _selectedLanguage == 'en'
              ? 'Are you sure you want to logout?'
              : 'Êtes-vous sûr de vouloir vous déconnecter ?',
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
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
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
              _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
              style: AppTypography.body2.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
        contentPadding: EdgeInsets.all(AppSizes.spacingL),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                _selectedLanguage == 'en' ? 'Edit Profile' : 'Modifier le profil',
                style: AppTypography.subtitle1.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(
                controller: _prenomController,
                label: _selectedLanguage == 'en' ? 'First Name' : 'Prénom',
                icon: Icons.person_outline,
              ),
              SizedBox(height: AppSizes.spacingM),
              _buildTextField(
                controller: _nomController,
                label: _selectedLanguage == 'en' ? 'Last Name' : 'Nom',
                icon: Icons.person_outline,
              ),
              SizedBox(height: AppSizes.spacingM),
              _buildTextField(
                controller: _phoneController,
                label: _selectedLanguage == 'en' ? 'Phone' : 'Téléphone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: AppSizes.spacingM),
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
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
            onPressed: _updateProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Save' : 'Enregistrer',
              style: AppTypography.body2.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
        ),
        contentPadding: EdgeInsets.all(AppSizes.spacingL),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline, color: AppColors.primary, size: 20),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                _selectedLanguage == 'en' ? 'Change Password' : 'Changer le mot de passe',
                style: AppTypography.subtitle1.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(
                controller: _oldPasswordController,
                label: _selectedLanguage == 'en' ? 'Old Password' : 'Ancien mot de passe',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              SizedBox(height: AppSizes.spacingM),
              _buildTextField(
                controller: _newPasswordController,
                label: _selectedLanguage == 'en' ? 'New Password' : 'Nouveau mot de passe',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              SizedBox(height: AppSizes.spacingM),
              _buildTextField(
                controller: _confirmPasswordController,
                label: _selectedLanguage == 'en' ? 'Confirm Password' : 'Confirmer le mot de passe',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _oldPasswordController.clear();
              _newPasswordController.clear();
              _confirmPasswordController.clear();
            },
            child: Text(
              _selectedLanguage == 'en' ? 'Cancel' : 'Annuler',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              _selectedLanguage == 'en' ? 'Change' : 'Changer',
              style: AppTypography.body2.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: AppTypography.body1.copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.body2.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Compact Header
            Container(
              color: AppColors.white,
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.spacingL,
                vertical: AppSizes.spacingM,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en' ? 'Profile' : 'Profil',
                      style: AppTypography.h3.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: _showEditProfileDialog,
                    icon: Icon(Icons.edit_rounded, size: 20),
                    color: AppColors.primary,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Profile Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: Column(
                  children: [
                    // Profile Avatar & Name
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingL),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppSizes.radiusL),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withOpacity(0.7),
                                ],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.white,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                "${(userData['prenom'] ?? 'U')[0]}${(userData['nom'] ?? 'S')[0]}",
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: AppSizes.spacingM),
                          // Name
                          Text(
                            "${userData['prenom'] ?? ''} ${userData['nom'] ?? ''}",
                            style: AppTypography.h3.copyWith(fontSize: 20),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: AppSizes.spacingXS),
                          // User ID
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSizes.spacingM,
                              vertical: AppSizes.spacingXS,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'ID: ${userData['user_unique_id'] ?? 'N/A'}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: AppSizes.spacingL),

                    // Contact Information
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingL),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppSizes.radiusL),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedLanguage == 'en'
                                ? 'Contact Information'
                                : 'Informations de contact',
                            style: AppTypography.subtitle1.copyWith(fontSize: 15),
                          ),
                          SizedBox(height: AppSizes.spacingM),
                          _buildInfoRow(
                            icon: Icons.phone_outlined,
                            label: _selectedLanguage == 'en' ? 'Phone' : 'Téléphone',
                            value: userData['phone'] ?? (_selectedLanguage == 'en' ? 'Not provided' : 'Non fourni'),
                          ),
                          SizedBox(height: AppSizes.spacingM),
                          _buildInfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: userData['email'] ?? (_selectedLanguage == 'en' ? 'Not provided' : 'Non fourni'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: AppSizes.spacingL),

                    // Action Buttons
                    Column(
                      children: [
                        // Edit Profile Button
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          label: _selectedLanguage == 'en' ? 'Edit Profile' : 'Modifier le profil',
                          color: AppColors.primary,
                          onTap: _showEditProfileDialog,
                        ),
                        SizedBox(height: AppSizes.spacingM),
                        // Change Password Button
                        _buildActionButton(
                          icon: Icons.lock_outline,
                          label: _selectedLanguage == 'en' ? 'Change Password' : 'Changer le mot de passe',
                          color: AppColors.primary,
                          onTap: _showChangePasswordDialog,
                        ),
                        SizedBox(height: AppSizes.spacingM),
                        // Logout Button
                        _buildActionButton(
                          icon: Icons.logout_rounded,
                          label: _selectedLanguage == 'en' ? 'Logout' : 'Déconnexion',
                          color: AppColors.error,
                          onTap: _logout,
                        ),
                      ],
                    ),

                    SizedBox(height: AppSizes.spacingXL),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        SizedBox(width: AppSizes.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.body1.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.spacingL,
          vertical: AppSizes.spacingM,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusL),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}