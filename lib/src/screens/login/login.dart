// lib/src/screens/login/login_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/env_config.dart';
import '../../services/notification_service.dart';
import '../change password/change_password.dart';
import '../dashboard/dashboard.dart';
import '../forgot_password/forgot_password.dart';
import '../../../main.dart' show FCMService;

// ── Country model ─────────────────────────────────────────────────────────────
class Country {
  final String name;
  final String dialCode;
  final String isoCode;
  final String flag;

  const Country({
    required this.name,
    required this.dialCode,
    required this.isoCode,
    required this.flag,
  });
}

// ── Constants ─────────────────────────────────────────────────────────────────
const List<Country> _kCountries = [
  Country(name: 'Cameroon',    dialCode: '+237', isoCode: 'CM', flag: '🇨🇲'),
  Country(name: 'Nigeria',     dialCode: '+234', isoCode: 'NG', flag: '🇳🇬'),
  Country(name: 'Ghana',       dialCode: '+233', isoCode: 'GH', flag: '🇬🇭'),
  Country(name: 'Ivory Coast', dialCode: '+225', isoCode: 'CI', flag: '🇨🇮'),
  Country(name: 'Benin',       dialCode: '+229', isoCode: 'BJ', flag: '🇧🇯'),
  Country(name: 'Congo',       dialCode: '+242', isoCode: 'CG', flag: '🇨🇬'),
  Country(name: 'Togo',        dialCode: '+228', isoCode: 'TG', flag: '🇹🇬'),
  Country(name: 'USA',         dialCode: '+1',   isoCode: 'US', flag: '🇺🇸'),
  Country(name: 'France',      dialCode: '+33',  isoCode: 'FR', flag: '🇫🇷'),
];

const Color _kOrange    = Color(0xFFFF6B35);
const Color _kBlack     = Color(0xFF1A1A1A);
const Color _kGradStart = Color(0xFFFF8A5B);
const Color _kGradEnd   = Color(0xFFFF6B35);

// ── Screen ────────────────────────────────────────────────────────────────────
class ModernLoginScreen extends StatefulWidget {
  const ModernLoginScreen({Key? key}) : super(key: key);

  @override
  State<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen>
    with TickerProviderStateMixin {

  final _phoneCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  Country _selectedCountry = _kCountries.first;
  bool _obscurePassword    = true;
  bool _rememberMe         = false;
  bool _isLoading          = false;

  late final AnimationController _entryCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;
  late final Animation<double>   _scaleAnim;

  String get _baseUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _entryCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));

    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic)));

    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(
            parent: _entryCtrl,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)));

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _floatCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    final phone    = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      _showError('Phone and password are required.');
      return;
    }

    setState(() => _isLoading = true);

    final fullPhone = '${_selectedCountry.dialCode}$phone';
    final url       = Uri.parse('$_baseUrl/auth/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone':          fullPhone,
          'password':       password,
          'keepMeLoggedIn': _rememberMe,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // ── SUCCESS ────────────────────────────────────────────────────────────
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();

        // ── Tokens ────────────────────────────────────────────────────────
        final String accessToken  = body['accessToken']  as String;
        final String refreshToken = body['refreshToken'] as String;

        // Both keys saved — ApiService reads 'accessToken', legacy code reads

        await prefs.setString('accessToken',  accessToken);
        await prefs.setString('auth_token',   accessToken);   // legacy key
        await prefs.setString('refreshToken', refreshToken);  // ← was missing

        debugPrint(' Tokens saved — accessToken: ${accessToken.substring(0, 20)}...');
        debugPrint(' refreshToken saved: ${refreshToken.substring(0, 20)}...');

        // ── User ──────────────────────────────────────────────────────────
        await prefs.setString('user', jsonEncode(body['user']));

        final int userId = (body['user']['id'] as num).toInt();
        await prefs.setInt('user_id', userId);

        // Phone + country code (used by payment sheet pre-fill)
        await prefs.setString('user_phone',        fullPhone);
        await prefs.setString('user_country_code', _selectedCountry.isoCode);

        // User type
        final String userType = body['user_type'] as String? ?? 'regular';
        await prefs.setString('user_type', userType);

        // Partner id
        if (body['user']['partner_id'] != null) {
          await prefs.setInt(
              'partner_id', (body['user']['partner_id'] as num).toInt());
        }


        final List vehicles = (body['vehicles'] as List?) ?? [];

        if (vehicles.isEmpty) {
          setState(() => _isLoading = false);
          _showError('No vehicles found for this account.');
          return;
        }

        await prefs.setString('vehicles_list', jsonEncode(vehicles));

        final int firstVehicleId = (vehicles[0]['id'] as num).toInt();
        await prefs.setInt('current_vehicle_id', firstVehicleId);

        final firstVehicle = vehicles[0] as Map<String, dynamic>;
        final String firstName =
        (firstVehicle['nickname'] as String?)?.isNotEmpty == true
            ? firstVehicle['nickname'] as String
            : '${firstVehicle['marque'] ?? firstVehicle['brand'] ?? ''} ${firstVehicle['model'] ?? ''}'
            .trim();
        await prefs.setString('current_vehicle_name', firstName);

        // ── Notifications ─────────────────────────────────────────────────
        try {
          await NotificationService.registerToken();
        } catch (e) {
          debugPrint('⚠️ Notification error: $e');
        }

        try {
          await NotificationService.registerToken();
        } catch (e) {
          debugPrint('⚠️ FCM retry failed: $e');
        }

        final bool isFirstLogin = body['isFirstLogin'] as bool? ?? false;

        setState(() => _isLoading = false);
        if (!mounted) return;

        // ── First login → force password reset ────────────────────────────
        if (isFirstLogin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ResetPasswordScreen(userId: userId, isFirstLogin: true),
            ),
          );
          return;
        }

        // ── All good → dashboard ──────────────────────────────────────────
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ModernDashboard(vehicleId: firstVehicleId),
          ),
        );

        // ── FAILURE ────────────────────────────────────────────────────────────
      } else {
        setState(() => _isLoading = false);

        String msg = 'Login failed.';
        if (body['errors'] is List && (body['errors'] as List).isNotEmpty) {
          final first = (body['errors'] as List).first as Map;
          msg = first['msg'] as String?
              ?? first['message'] as String?
              ?? msg;
        } else if (body['message'] != null) {
          msg = body['message'] as String;
        }
        _showError(msg);
      }

    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Connection error. Please try again.');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  )),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CountryPickerSheet(
        countries: _kCountries,
        selected:  _selectedCountry,
        onSelect:  (c) => setState(() => _selectedCountry = c),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF5F0),
              Color(0xFFFFFFFF),
              Color(0xFFFFF8F5),
            ],
          ),
        ),
        child: Stack(
          children: [
            _FloatingPins(controller: _floatCtrl),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                          scale: _scaleAnim, child: const _LogoSection()),
                    ),
                    const SizedBox(height: 60),
                    SlideTransition(
                      position: _slideAnim,
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: _buildCard(),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome Back',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _kBlack,
                    height: 1.2,
                  )),
              const SizedBox(height: 8),
              Text('Sign in to track your vehicle',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  )),
              const SizedBox(height: 32),
              _buildPhoneField(),
              const SizedBox(height: 20),
              _buildPasswordField(),
              const SizedBox(height: 16),
              _buildOptionsRow(),
              const SizedBox(height: 28),
              _buildLoginButton(),
              const SizedBox(height: 20),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Phone Number',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _kBlack,
            )),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1.5),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _showCountryPicker,
                borderRadius: const BorderRadius.only(
                  topLeft:    Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Colors.grey[200]!, width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedCountry.flag,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(_selectedCountry.dialCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: _kBlack,
                          )),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded,
                          color: Colors.grey[600], size: 20),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _kBlack,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '612 345 678',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Password',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _kBlack,
            )),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1.5),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 16, right: 12),
                child: Icon(Icons.lock_outline_rounded,
                    color: _kOrange, size: 22),
              ),
              Expanded(
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _kBlack,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter your password',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.grey[600],
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                activeColor: _kOrange,
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                side: BorderSide(color: Colors.grey[300]!, width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Text('Remember me',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                )),
          ],
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ForgotPasswordScreen()),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Forgot password?',
              style: TextStyle(
                fontSize: 13,
                color: _kOrange,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kGradStart, _kGradEnd]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor:     Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                )),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        '© ${DateTime.now().year} All rights reserved to PROXYM GROUP',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[500],
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// COUNTRY PICKER SHEET
// ═══════════════════════════════════════════════════════════════════

class _CountryPickerSheet extends StatelessWidget {
  final List<Country> countries;
  final Country       selected;
  final ValueChanged<Country> onSelect;

  const _CountryPickerSheet({
    required this.countries,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Select Country',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kBlack,
                      )),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: countries.length,
              itemBuilder: (_, i) {
                final c          = countries[i];
                final isSelected = c.dialCode == selected.dialCode;

                return InkWell(
                  onTap: () {
                    onSelect(c);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    color: isSelected
                        ? _kOrange.withOpacity(0.08)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: TextStyle(
                                    color: isSelected ? _kOrange : _kBlack,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  )),
                              const SizedBox(height: 2),
                              Text(c.dialCode,
                                  style: TextStyle(
                                    color: isSelected
                                        ? _kOrange
                                        : Colors.grey[600],
                                    fontSize: 13,
                                  )),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 24, height: 24,
                            decoration: const BoxDecoration(
                              color: _kOrange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 16),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// LOGO SECTION
// ═══════════════════════════════════════════════════════════════════

class _LogoSection extends StatelessWidget {
  const _LogoSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _kOrange.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kGradStart, _kGradEnd],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gps_fixed_rounded,
                    size: 50, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('FLEETRA',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: _kOrange,
              letterSpacing: 1.5,
              height: 1.1,
            )),
        const SizedBox(height: 4),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'by ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              const TextSpan(
                text: 'PROXYM ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kBlack,
                  letterSpacing: 0.5,
                ),
              ),
              const TextSpan(
                text: 'GROUP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kOrange,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// FLOATING PINS BACKGROUND
// ═══════════════════════════════════════════════════════════════════

class _FloatingPins extends StatelessWidget {
  final AnimationController controller;
  const _FloatingPins({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final v = controller.value;
        return Stack(
          children: [
            Positioned(
              top: 100 + (v * 30), right: 40,
              child: _pin(size: 40, opacity: 0.15),
            ),
            Positioned(
              top: 250 + (v * -25), left: 30,
              child: _pin(size: 35, opacity: 0.10),
            ),
            Positioned(
              bottom: 200 + (v * 20), right: 60,
              child: _pin(size: 30, opacity: 0.12),
            ),
            Positioned(
              top: 0, left: 0, right: 0,
              child: Opacity(
                opacity: 0.05,
                child: CustomPaint(
                  size: const Size(double.infinity, 300),
                  painter: _GridPainter(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pin({required double size, required double opacity}) => Opacity(
    opacity: opacity,
    child: Icon(Icons.location_on_rounded, size: size, color: _kOrange),
  );
}

// ═══════════════════════════════════════════════════════════════════
// GRID PAINTER
// ═══════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kOrange.withOpacity(0.1)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}