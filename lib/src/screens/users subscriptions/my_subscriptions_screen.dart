// lib/src/screens/subscriptions/my_subscriptions_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/api_service.dart';
import '../subscriptions/payment_history.dart';
import '../subscriptions/renewal_payment_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Translation helper
// ─────────────────────────────────────────────────────────────────────────────

String _t(String lang, String en, String fr) => lang == 'fr' ? fr : en;

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class _Plan {
  final int id;
  final String name;
  final String code;
  final double price;
  final String currency;
  final String billingMode;
  final int durationMonths;
  final List<String> features;

  _Plan({
    required this.id,
    required this.name,
    required this.code,
    required this.price,
    required this.currency,
    required this.billingMode,
    required this.durationMonths,
    required this.features,
  });

  factory _Plan.fromJson(Map<String, dynamic> j) {
    List<String> featureList = [];
    final raw = j['features'];
    if (raw is List) {
      featureList = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          featureList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        featureList = raw.split(',').map((e) => e.trim()).toList();
      }
    }

    double parseDouble(dynamic v) =>
        v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    int parseInt(dynamic v) =>
        v == null ? 0 : int.tryParse(v.toString()) ?? 0;

    return _Plan(
      id:             parseInt(j['id']),
      name:           j['name']?.toString() ?? j['label']?.toString() ?? 'Plan',
      code:           j['code']?.toString() ?? '',
      price:          parseDouble(j['price']),
      currency:       j['currency']?.toString()     ?? 'XAF',
      billingMode:    j['billing_mode']?.toString() ?? 'MONTH',
      durationMonths: parseInt(j['duration_months']),
      features:       featureList,
    );
  }

  String durationLabel(String lang) =>
      durationMonths == 1
          ? _t(lang, '1 month', '1 mois')
          : _t(lang, '$durationMonths months', '$durationMonths mois');
}

class _Subscription {
  final int id;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final _Plan plan;

  _Subscription({
    required this.id,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.plan,
  });

  factory _Subscription.fromJson(Map<String, dynamic> j) => _Subscription(
    id:        int.tryParse(j['id']?.toString() ?? '') ?? 0,
    status:    j['status']?.toString() ?? 'UNKNOWN',
    startDate: j['start_date'] != null
        ? DateTime.tryParse(j['start_date'].toString())
        : null,
    endDate: j['end_date'] != null
        ? DateTime.tryParse(j['end_date'].toString())
        : null,
    plan: _Plan.fromJson(j['plan'] as Map<String, dynamic>),
  );

  bool get isActive =>
      status == 'ACTIVE' && (endDate?.isAfter(DateTime.now()) ?? false);

  int get daysRemaining {
    if (endDate == null) return 0;
    return endDate!.difference(DateTime.now()).inDays;
  }
}

class _VehicleSub {
  final int vehicleId;
  final String vehicleName;
  final String vehiclePlate;
  final _Subscription? subscription;

  _VehicleSub({
    required this.vehicleId,
    required this.vehicleName,
    required this.vehiclePlate,
    required this.subscription,
  });

  factory _VehicleSub.fromJson(Map<String, dynamic> j) => _VehicleSub(
    vehicleId:    int.tryParse(j['vehicle_id']?.toString() ?? '') ?? 0,
    vehicleName:  j['vehicle_name']?.toString()  ?? 'Unknown Vehicle',
    vehiclePlate: j['vehicle_plate']?.toString() ?? '',
    subscription: j['subscription'] != null
        ? _Subscription.fromJson(j['subscription'] as Map<String, dynamic>)
        : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MySubscriptionsScreen extends StatefulWidget {
  final int? focusVehicleId;
  final String? selectedLanguage;

  const MySubscriptionsScreen({
    Key? key,
    this.focusVehicleId,
    this.selectedLanguage,
  }) : super(key: key);

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen> {
  // ── Theme-aligned accent colors ───────────────────────────────────────────
  // All derived from AppColors — no rogue palette values.
  static const Color _primary    = AppColors.primary;          // #D85119 — brand orange-red
  static const Color _success    = AppColors.success;          // #4CAF50
  static const Color _errorColor = AppColors.error;            // #F44336
  static const Color _warnColor  = AppColors.warning;          // #FF9800

  // ── Feature registry ──────────────────────────────────────────────────────
  static const _featureLabels = {
    'live_tracking':  ('Live Tracking',   'Suivi en direct'),
    'geofence':       ('Geofencing',       'Géofencing'),
    'safe_zone':      ('Safe Zone',        'Zone sécurisée'),
    'trip_history':   ('Trip History',     'Historique des trajets'),
    'engine_control': ('Engine Control',   'Contrôle moteur'),
    'report_stolen':  ('Theft Report',     'Signalement de vol'),
    'call_center':    ('Call Center',      'Centre d\'appel'),
  };

  static const _featureIcons = {
    'live_tracking':  Icons.location_on_rounded,
    'geofence':       Icons.fence_rounded,
    'safe_zone':      Icons.shield_rounded,
    'trip_history':   Icons.route_rounded,
    'engine_control': Icons.power_settings_new_rounded,
    'report_stolen':  Icons.gpp_bad_rounded,
    'call_center':    Icons.support_agent_rounded,
  };

  bool _isLoading = true;
  String? _error;
  List<_VehicleSub> _items = [];
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _initLang();
    _load();
  }

  Future<void> _initLang() async {
    if (widget.selectedLanguage != null) {
      setState(() => _lang = widget.selectedLanguage!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('language') ?? 'en';
    if (mounted) setState(() => _lang = saved);
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await ApiService.get('/payments/subscriptions/all');
      if (data['success'] == true) {
        final list = (data['data'] as List<dynamic>)
            .map((e) => _VehicleSub.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() { _items = list; _isLoading = false; });
      } else {
        setState(() {
          _error = _t(_lang,
              'Failed to load subscriptions.',
              'Impossible de charger les abonnements.');
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = _t(_lang,
            'Failed to load subscriptions.',
            'Impossible de charger les abonnements.');
        _isLoading = false;
      });
      debugPrint('❌ MySubscriptionsScreen: $e');
    }
  }

  void _openPlans(int vehicleId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionPlansScreen(
          vehicleId:        vehicleId,
          selectedLanguage: _lang,
        ),
      ),
    );
    _load();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _t(_lang, 'My Subscriptions', 'Mes abonnements'),
          style: AppTypography.h3
              .copyWith(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded,
                size: 22, color: Colors.black54),
            tooltip: _t(_lang, 'Payment History', 'Historique des paiements'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
          ? _buildError()
          : _buildList(),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTypography.body2.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: Text(
                _t(_lang, 'Retry', 'Réessayer'),
                style: AppTypography.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main list ──────────────────────────────────────────────────────────────

  Widget _buildList() {
    final activeCount =
        _items.where((i) => i.subscription?.isActive == true).length;
    final totalCount = _items.length;

    return RefreshIndicator(
      color: _primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _buildSummaryBanner(activeCount, totalCount),
          const SizedBox(height: 24),
          Text(
            _t(_lang, 'Your Vehicles', 'Vos véhicules'),
            style: AppTypography.h3.copyWith(
                fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 14),
          ..._items.map((item) => _buildVehicleCard(item)),
        ],
      ),
    );
  }

  // ── Fleet summary banner ───────────────────────────────────────────────────

  Widget _buildSummaryBanner(int active, int total) {
    final allActive  = active == total;
    final noneActive = active == 0;
    final inactive   = total - active;

    // Color logic: all active → success green, none → error red, mixed → brand primary
    final Color bannerColor = allActive
        ? _success
        : noneActive
        ? _errorColor
        : _primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: allActive
              ? [_success, const Color(0xFF388E3C)]
              : noneActive
              ? [_errorColor, const Color(0xFFC62828)]
              : [_primary, const Color(0xFFBF4010)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              allActive
                  ? Icons.verified_rounded
                  : noneActive
                  ? Icons.cancel_rounded
                  : Icons.info_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allActive
                      ? _t(_lang,
                      'All vehicles covered',
                      'Tous les véhicules couverts')
                      : noneActive
                      ? _t(_lang,
                      'No active subscriptions',
                      'Aucun abonnement actif')
                      : _t(_lang,
                      '$active of $total vehicles active',
                      '$active sur $total véhicules actifs'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  allActive
                      ? _t(_lang,
                      'Your entire fleet has active plans',
                      'Toute votre flotte a des forfaits actifs')
                      : noneActive
                      ? _t(_lang,
                      'Subscribe to unlock all features',
                      'Abonnez-vous pour débloquer toutes les fonctionnalités')
                      : _t(_lang,
                      '$inactive vehicle${inactive > 1 ? 's' : ''} without a plan',
                      '$inactive véhicule${inactive > 1 ? 's' : ''} sans forfait'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$active/$total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ── Vehicle card ───────────────────────────────────────────────────────────

  Widget _buildVehicleCard(_VehicleSub item) {
    final sub         = item.subscription;
    final active      = sub?.isActive ?? false;
    final accentColor = active ? _success : _errorColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Vehicle header ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.05),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.directions_car_rounded,
                      size: 22, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.vehicleName,
                          style: AppTypography.body1.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      if (item.vehiclePlate.isNotEmpty)
                        Text(item.vehiclePlate,
                            style: AppTypography.caption
                                .copyWith(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 13,
                        color: accentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        active
                            ? _t(_lang, 'Active', 'Actif')
                            : _t(_lang, 'No plan', 'Sans forfait'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: active && sub != null
                ? _buildActiveContent(sub)
                : _buildInactiveContent(item.vehicleId),
          ),
        ],
      ),
    );
  }

  // ── Active subscription content ────────────────────────────────────────────

  Widget _buildActiveContent(_Subscription sub) {
    final days          = sub.daysRemaining;
    final expiry        = sub.endDate;
    // Expiring soon → warning orange, otherwise brand primary for the countdown
    final urgentColor   = days <= 7 ? _warnColor : _primary;
    final hasCallCenter = sub.plan.features.contains('call_center');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Plan name + days remaining ──────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sub.plan.name,
                      style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  Text(sub.plan.durationLabel(_lang),
                      style: AppTypography.caption
                          .copyWith(color: Colors.grey.shade500)),
                ],
              ),
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: urgentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    '$days',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: urgentColor,
                    ),
                  ),
                  Text(
                    _t(_lang, 'days left', 'jours restants'),
                    style: TextStyle(
                        fontSize: 9,
                        color: urgentColor,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Expiry row ──────────────────────────────────────────────────
        if (expiry != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_rounded,
                  size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 5),
              Text(
                '${_t(_lang, 'Expires', 'Expire le')} ${_formatDate(expiry)}',
                style: AppTypography.caption.copyWith(
                  color: days <= 7 ? _warnColor : Colors.grey.shade500,
                  fontWeight:
                  days <= 7 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (days <= 7) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _warnColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _t(_lang, 'Expiring soon', 'Expire bientôt'),
                    style: TextStyle(
                        fontSize: 10,
                        color: _warnColor,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ],

        // ── Call center highlight strip ──────────────────────────────────
        // Uses primary brand color instead of indigo
        if (hasCallCenter) ...[
          const SizedBox(height: 12),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.support_agent_rounded,
                      color: _primary, size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(_lang,
                        '24/7 Call Center support is active for this vehicle.',
                        'L\'assistance téléphonique 24h/24 est active pour ce véhicule.'),
                    style: AppTypography.caption.copyWith(
                      color: _primary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '24/7',
                    style: TextStyle(
                        fontSize: 9,
                        color: _primary,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // ── Feature chips ───────────────────────────────────────────────
        if (sub.plan.features.isNotEmpty) ...[
          Text(
            _t(_lang, 'Included features', 'Fonctionnalités incluses'),
            style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _featureLabels.entries.map((entry) {
              final key          = entry.key;
              final labels       = entry.value;
              final label        = _lang == 'fr' ? labels.$2 : labels.$1;
              final included     = sub.plan.features.contains(key);
              final icon         = _featureIcons[key] ?? Icons.check;
              final isCallCenter = key == 'call_center';
              // Included features: call center uses primary, others use success green
              final chipColor =
              included ? (isCallCenter ? _primary : _success) : null;

              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: included
                      ? (isCallCenter
                      ? _primary.withOpacity(0.08)
                      : _success.withOpacity(0.08))
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: included
                        ? (isCallCenter
                        ? _primary.withOpacity(0.3)
                        : _success.withOpacity(0.3))
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 12,
                        color: included
                            ? chipColor
                            : Colors.grey.shade400),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                        included ? FontWeight.w600 : FontWeight.normal,
                        color: included
                            ? (isCallCenter
                            ? _primary
                            : Colors.black87)
                            : Colors.grey.shade400,
                      ),
                    ),
                    if (isCallCenter && included) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '24/7',
                          style: TextStyle(
                              fontSize: 8,
                              color: _primary,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],

        // ── Renew button ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openPlans(sub.plan.id),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_t(_lang, 'Renew Plan', 'Renouveler le forfait')),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: BorderSide(color: _primary.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Inactive / no-subscription content ─────────────────────────────────────

  Widget _buildInactiveContent(int vehicleId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _errorColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _errorColor.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_rounded,
                  size: 18, color: _errorColor.withOpacity(0.7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(_lang,
                      'No active subscription. Features like geofencing, trip history, and engine control are locked.',
                      'Aucun abonnement actif. Les fonctionnalités comme le géofencing, l\'historique des trajets et le contrôle moteur sont verrouillées.'),
                  style: AppTypography.caption.copyWith(
                    color: _errorColor.withOpacity(0.85),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _featureLabels.entries.map((entry) {
            final labels = entry.value;
            final label  = _lang == 'fr' ? labels.$2 : labels.$1;
            return Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded,
                      size: 11, color: Color(0xFFCBD5E1)),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openPlans(vehicleId),
            icon: const Icon(Icons.workspace_premium_rounded, size: 16),
            label: Text(
                _t(_lang, 'Subscribe Now', 'S\'abonner maintenant')),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }
}