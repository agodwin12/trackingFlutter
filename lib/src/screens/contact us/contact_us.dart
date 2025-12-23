// lib/src/screens/contact/contact_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utility/app_theme.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({Key? key}) : super(key: key);

  // PROXYM TRACKING Contact Details
  static const String phoneNumber = '+237694587675'; // Replace with actual number
  static const String email = 'accueil@proxymgroup.com'; // Replace with actual email
  static const String website = 'https://proxymtracking.com'; // Replace with actual website

  Future<void> _makePhoneCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showErrorSnackbar(context, 'Could not open phone dialer');
      }
    } catch (e) {
      _showErrorSnackbar(context, 'Error opening phone dialer');
    }
  }

  Future<void> _sendEmail(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Support Request - PROXYM TRACKING',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        _showErrorSnackbar(context, 'Could not open email app');
      }
    } catch (e) {
      _showErrorSnackbar(context, 'Error opening email app');
    }
  }

  Future<void> _openWebsite(BuildContext context) async {
    final Uri websiteUri = Uri.parse(website);

    try {
      if (await canLaunchUrl(websiteUri)) {
        await launchUrl(websiteUri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackbar(context, 'Could not open website');
      }
    } catch (e) {
      _showErrorSnackbar(context, 'Error opening website');
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      'Contact Us',
                      style: AppTypography.h3.copyWith(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppSizes.spacingL),
                child: Column(
                  children: [
                    // Header Card with Logo
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingXL),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppSizes.radiusXL),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Logo/Icon
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.support_agent_rounded,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: AppSizes.spacingL),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'PROXYM ',
                                  style: AppTypography.h2.copyWith(
                                    color: AppColors.white,
                                    fontSize: 24,
                                  ),
                                ),
                                TextSpan(
                                  text: 'TRACKING',
                                  style: AppTypography.h2.copyWith(
                                    color: AppColors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: AppSizes.spacingS),
                          Text(
                            'We\'re here to help you 24/7',
                            style: AppTypography.body1.copyWith(
                              color: AppColors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: AppSizes.spacingXL),

                    // Contact Options
                    Text(
                      'Get in Touch',
                      style: AppTypography.h3.copyWith(fontSize: 18),
                    ),
                    SizedBox(height: AppSizes.spacingM),
                    Text(
                      'Choose your preferred way to reach us',
                      style: AppTypography.body2.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: AppSizes.spacingL),

                    // Phone Card
                    _buildContactCard(
                      context: context,
                      icon: Icons.phone_rounded,
                      title: 'Call Us',
                      subtitle: phoneNumber,
                      description: 'Tap to call our support team',
                      color: AppColors.success,
                      onTap: () => _makePhoneCall(context),
                    ),

                    SizedBox(height: AppSizes.spacingM),

                    // Email Card
                    _buildContactCard(
                      context: context,
                      icon: Icons.email_rounded,
                      title: 'Email Us',
                      subtitle: email,
                      description: 'Send us your questions',
                      color: AppColors.primary,
                      onTap: () => _sendEmail(context),
                    ),

                    SizedBox(height: AppSizes.spacingM),

                    // Website Card
                    _buildContactCard(
                      context: context,
                      icon: Icons.language_rounded,
                      title: 'Visit Website',
                      subtitle: website,
                      description: 'Learn more about our services',
                      color: Color(0xFF8B5CF6),
                      onTap: () => _openWebsite(context),
                    ),

                    SizedBox(height: AppSizes.spacingXL),

                    // Additional Info
                    Container(
                      padding: EdgeInsets.all(AppSizes.spacingL),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppSizes.radiusL),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                          SizedBox(width: AppSizes.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Business Hours',
                                  style: AppTypography.subtitle1.copyWith(
                                    fontSize: 14,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Monday - Friday: 8:00 AM - 6:00 PM\nSaturday: 9:00 AM - 2:00 PM',
                                  style: AppTypography.body2.copyWith(
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusL),
      child: Container(
        padding: EdgeInsets.all(AppSizes.spacingL),
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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.subtitle1.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.body1.copyWith(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    description,
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
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