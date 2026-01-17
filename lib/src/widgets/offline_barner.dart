import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connectivity_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({Key? key}) : super(key: key);

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> with SingleTickerProviderStateMixin {
  final ConnectivityService _connectivityService = ConnectivityService();
  String _selectedLanguage = 'en';
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();

    // Setup slide animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1), // Start above screen
      end: Offset.zero,           // Slide to normal position
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Listen to connectivity changes
    _connectivityService.addListener(_onConnectivityChanged);
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguage = prefs.getString('language') ?? 'en';
      });
    }
  }

  void _onConnectivityChanged() {
    if (mounted) {
      setState(() {});

      // Animate in/out based on connectivity
      if (_connectivityService.isOffline) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_onConnectivityChanged);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if online
    if (_connectivityService.isOnline) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF59E0B), // Amber/Orange
              const Color(0xFFF59E0B).withOpacity(0.85),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Offline icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedLanguage == 'en'
                        ? 'You\'re Offline'
                        : 'Vous êtes hors ligne',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedLanguage == 'en'
                        ? 'Showing cached data'
                        : 'Affichage des données en cache',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}