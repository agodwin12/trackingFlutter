// lib/src/screens/subscriptions/subscription_gate_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../dashboard/dashboard.dart';
import '../login/login.dart';
import '../subscriptions/renewal_payment_screen.dart';

class SubscriptionGateScreen extends StatefulWidget {
  final List vehicles;
  final int userId;

  const SubscriptionGateScreen({
    Key? key,
    required this.vehicles,
    required this.userId,
  }) : super(key: key);

  @override
  State<SubscriptionGateScreen> createState() => _SubscriptionGateScreenState();
}

class _SubscriptionGateScreenState extends State<SubscriptionGateScreen>
    with SingleTickerProviderStateMixin {
  static const Color _orange = Color(0xFFFF6B35);

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  int _selectedVehicleIndex = 0;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Intercept back button — exit app, don't go back to login ──
  Future<bool> _onWillPop() async {
    SystemNavigator.pop();
    return false;
  }

  // ── Get display name for a vehicle ────────────────────────────
  String _vehicleDisplayName(Map<String, dynamic> v) {
    final nickname = v['nickname'] as String? ?? '';
    if (nickname.isNotEmpty) return nickname;
    final brand = v['marque'] ?? v['brand'] ?? '';
    final model = v['model'] ?? '';
    return '$brand $model'.trim().isNotEmpty
        ? '$brand $model'.trim()
        : 'Vehicle ${v['id']}';
  }

  // ── Navigate to plans for selected vehicle ─────────────────────
  void _goToPlans() {
    final vehicle = widget.vehicles[_selectedVehicleIndex]
    as Map<String, dynamic>;
    final vehicleId = (vehicle['id'] as num).toInt();
    final vehicleName = _vehicleDisplayName(vehicle);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionPlansScreen(
          vehicleId: vehicleId,
          vehicleName: vehicleName,

          onSubscribed: _onVehicleSubscribed,
        ),
      ),
    );
  }

  // ── Called by SubscriptionPlansScreen after a successful payment ─
  void _onVehicleSubscribed(int vehicleId) async {
    debugPrint('✅ [GATE] Vehicle $vehicleId subscribed');

    // Mark this vehicle as subscribed locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscription_status', 'ACTIVE');

    if (!mounted) return;

    // Go straight to dashboard with the just-subscribed vehicle
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ModernDashboard(vehicleId: vehicleId),
      ),
          (route) => false,
    );
  }

  // ── Logout ────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ModernLoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF5F0),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 32),
                          _buildHeroSection(),
                          const SizedBox(height: 40),
                          _buildExplanationCard(),
                          const SizedBox(height: 24),
                          if (widget.vehicles.length > 1) ...[
                            _buildVehicleSelector(),
                            const SizedBox(height: 24),
                          ],
                          _buildSubscribeButton(),
                          const SizedBox(height: 16),
                          _buildLogoutButton(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar with FLEETRA logo ──────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF8A5B)],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Text(
              'FLEETRA',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontFamily: 'Roboto',
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'by PROXYM GROUP',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero illustration + headline ───────────────────────────────
  Widget _buildHeroSection() {
    return Column(
      children: [
        // Illustration container
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _orange.withOpacity(0.1),
            border: Border.all(
              color: _orange.withOpacity(0.2),
              width: 2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.directions_car_rounded,
                size: 60,
                color: _orange.withOpacity(0.3),
              ),
              Positioned(
                bottom: 22,
                right: 22,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Activate Your Plan',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Your account is ready, but your vehicle\nneeds an active subscription to get started.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── What's included card ───────────────────────────────────────
  Widget _buildExplanationCard() {
    final features = [
      (Icons.location_on_rounded,    'Real-time GPS tracking'),
      (Icons.shield_rounded,         'Safe zone monitoring'),
      (Icons.power_settings_new_rounded, 'Remote engine control'),
      (Icons.timeline_rounded,       'Trip history & routes'),
      (Icons.notifications_rounded,  'Instant alerts'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What\'s included',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(f.$1, color: _orange, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  f.$2,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ── Vehicle selector (only shown if user has multiple vehicles) ─
  Widget _buildVehicleSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select vehicle to activate',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(widget.vehicles.length, (index) {
            final vehicle =
            widget.vehicles[index] as Map<String, dynamic>;
            final isSelected = _selectedVehicleIndex == index;
            final name = _vehicleDisplayName(vehicle);
            final plate = vehicle['immatriculation'] as String? ?? '';

            return GestureDetector(
              onTap: () => setState(() => _selectedVehicleIndex = index),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _orange.withOpacity(0.08)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _orange : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.directions_car_rounded,
                      color: isSelected ? _orange : Colors.grey.shade500,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? _orange
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          if (plate.isNotEmpty)
                            Text(
                              plate,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: _orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 13),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Main CTA button ───────────────────────────────────────────
  Widget _buildSubscribeButton() {
    final vehicle = widget.vehicles[_selectedVehicleIndex]
    as Map<String, dynamic>;
    final name = _vehicleDisplayName(vehicle);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _goToPlans,
        style: ElevatedButton.styleFrom(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rocket_launch_rounded, size: 20),
            const SizedBox(width: 10),
            Text(
              widget.vehicles.length > 1
                  ? 'Activate Plan for $name'
                  : 'View Subscription Plans',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logout link ───────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return TextButton(
      onPressed: _handleLogout,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        'Sign out',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}