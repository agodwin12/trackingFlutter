import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/biometric_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const LockScreen({
    Key? key,
    required this.onAuthenticated,
  }) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final BiometricService _biometricService = BiometricService();
  bool _isAuthenticating = false;
  String _authMethod = 'Authentication';
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _checkAuthMethod();
    // Automatically trigger authentication when screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language') ?? 'en';
    });
    debugPrint('✅ Lock screen loaded language preference: $_selectedLanguage');
  }

  Future<void> _checkAuthMethod() async {
    final biometrics = await _biometricService.getAvailableBiometrics();

    setState(() {
      if (biometrics.isNotEmpty) {
        _authMethod = _selectedLanguage == 'en' ? 'Biometric or PIN' : 'Biométrie ou PIN';
      } else {
        _authMethod = _selectedLanguage == 'en' ? 'PIN or Password' : 'PIN ou Mot de passe';
      }
    });
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final bool isAuthenticated = await _biometricService.authenticate();

      if (isAuthenticated) {
        _biometricService.resetTimer();
        widget.onAuthenticated();
      } else {
        setState(() {
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      print('Authentication error: $e');
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3B82F6),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo or Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'PROXYM TRACKING',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _selectedLanguage == 'en'
                      ? 'Please authenticate to continue'
                      : 'Veuillez vous authentifier pour continuer',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Auth method info
              Text(
                _authMethod,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white60,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 48),

              // Authenticate Button
              if (!_isAuthenticating)
                ElevatedButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.lock_open),
                  label: Text(_selectedLanguage == 'en' ? 'Unlock' : 'Déverrouiller'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF3B82F6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              else
                const CircularProgressIndicator(
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }
}