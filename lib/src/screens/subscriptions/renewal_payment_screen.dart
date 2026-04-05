// lib/src/screens/subscription/subscription_plans_screen.dart

import 'dart:convert';
import 'package:FLEETRA/src/screens/subscriptions/payment_history.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utility/app_theme.dart';
import '../../services/api_service.dart';
import '../subscriptions/webview_payment_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kProviderCodes = {
  'MTN':    'MTNMOMO',
  'ORANGE': 'CMORANGEOM',
};

const _kMtnLogoAsset    = 'assets/mtn_logo.png';
const _kOrangeLogoAsset = 'assets/orange_logo.png';

// Dial codes by ISO — used to strip country prefix from stored phone number
const _kDialCodes = {
  'CM': '+237',
  'NG': '+234',
  'GH': '+233',
  'CI': '+225',
  'BJ': '+229',
  'CG': '+242',
  'TG': '+228',
  'US': '+1',
  'FR': '+33',
};

// ─────────────────────────────────────────────────────────────────────────────
// Translations helper
// ─────────────────────────────────────────────────────────────────────────────

String _t(String lang, String en, String fr) => lang == 'fr' ? fr : en;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class _Plan {
  final int id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final int durationDays;
  final int durationMonths;
  final String billingMode;
  final List<String> features;

  const _Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.durationMonths,
    required this.billingMode,
    required this.features,
  });

  factory _Plan.fromJson(Map<String, dynamic> json) {
    List<String> featureList = [];
    final raw = json['features'];
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
      id:             parseInt(json['id']),
      name:           json['label']?.toString() ?? json['name']?.toString() ?? 'Plan',
      description:    json['code']?.toString()  ?? '',
      price:          parseDouble(json['price']),
      currency:       json['currency']?.toString() ?? 'XAF',
      durationDays:   parseInt(json['duration_days']),
      durationMonths: parseInt(json['duration_months']),
      billingMode:    json['billing_mode']?.toString() ?? 'MONTH',
      features:       featureList,
    );
  }

  String durationLabel(String lang) {
    if (durationMonths == 1) return _t(lang, '1 month', '1 mois');
    return _t(lang, '$durationMonths months', '$durationMonths mois');
  }

  String get priceLabel {
    final formatted = price == price.truncateToDouble()
        ? price.toInt().toString()
        : price.toStringAsFixed(0);
    return '$formatted $currency';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionPlansScreen extends StatefulWidget {
  final int? vehicleId;
  final String? vehicleName;
  final String? selectedLanguage;

  const SubscriptionPlansScreen({
    Key? key,
    this.vehicleId,
    this.vehicleName,
    this.selectedLanguage,
    void Function(int vehicleId)? onSubscribed,
  }) : super(key: key);

  @override
  State<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  List<_Plan> _plans = [];
  bool _isLoading = true;
  String? _error;
  int? _selectedPlanId;
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _initLang();
    _fetchPlans();
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

  Future<void> _fetchPlans() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await ApiService.get('/payments/plans');
      if (data['success'] == true) {
        final rawList = data['data'] as List<dynamic>;
        setState(() {
          _plans = rawList
              .map((e) => _Plan.fromJson(e as Map<String, dynamic>))
              .toList();
          if (_plans.isNotEmpty) _selectedPlanId = _plans.first.id;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = _t(_lang,
              'Failed to load plans. Please try again.',
              'Impossible de charger les forfaits. Veuillez réessayer.');
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = _t(_lang,
            'Failed to load plans. Please try again.',
            'Impossible de charger les forfaits. Veuillez réessayer.');
        _isLoading = false;
      });
      debugPrint('❌ Error fetching plans: $e');
    }
  }

  void _onSelectPlan(_Plan plan) {
    setState(() => _selectedPlanId = plan.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        plan: plan,
        preselectedVehicleId: widget.vehicleId,
        lang: _lang,
      ),
    );
  }

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _t(_lang, 'Subscription Plans', 'Forfaits d\'abonnement'),
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
          ? _LoadingView(lang: _lang)
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _fetchPlans, lang: _lang)
          : _PlansView(
        plans: _plans,
        selectedPlanId: _selectedPlanId,
        onSelect: _onSelectPlan,
        lang: _lang,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plans list
// ─────────────────────────────────────────────────────────────────────────────

class _PlansView extends StatelessWidget {
  final List<_Plan> plans;
  final int? selectedPlanId;
  final void Function(_Plan) onSelect;
  final String lang;

  const _PlansView({
    required this.plans,
    required this.selectedPlanId,
    required this.onSelect,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _t(lang,
                        'Choose the plan that fits your fleet and unlock all features.',
                        'Choisissez le forfait adapté à votre flotte et débloquez toutes les fonctionnalités.'),
                    style: AppTypography.body2
                        .copyWith(color: AppColors.primary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _t(lang, 'Available Plans', 'Forfaits disponibles'),
            style: AppTypography.h3.copyWith(
                fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          ...plans.asMap().entries.map((entry) {
            final plan      = entry.value;
            final isPopular = entry.key == 1 && plans.length > 1;
            return _PlanCard(
              plan:       plan,
              isSelected: plan.id == selectedPlanId,
              isPopular:  isPopular,
              onTap:      () => onSelect(plan),
              lang:       lang,
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan card
// ─────────────────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool isSelected;
  final bool isPopular;
  final VoidCallback onTap;
  final String lang;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isPopular,
    required this.onTap,
    required this.lang,
  });

  static const _allFeatureLabels = {
    'live_tracking':  ('Live Tracking',      'Suivi en direct'),
    'geofence':       ('Geofencing',          'Géofencing'),
    'safe_zone':      ('Safe Zone',           'Zone sécurisée'),
    'trip_history':   ('Trip History',        'Historique des trajets'),
    'engine_control': ('Engine Control',      'Contrôle moteur'),
    'report_stolen':  ('Theft Report',        'Signalement de vol'),
    'call_center':    ('Call Center Support', 'Assistance centre d\'appel'),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.black.withOpacity(0.04),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.06)
                    : Colors.grey.shade50,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                plan.name,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body1.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            if (isPopular) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _t(lang, 'Popular', 'Populaire'),
                                  style: AppTypography.caption.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan.durationLabel(lang),
                          style: AppTypography.body2.copyWith(
                              color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    plan.priceLabel,
                    style: AppTypography.h3.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),

            // ── Feature rows ─────────────────────────────────────────────────
            if (plan.features.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Column(
                  children: _allFeatureLabels.entries.map((entry) {
                    final key          = entry.key;
                    final labels       = entry.value;
                    final label        = lang == 'fr' ? labels.$2 : labels.$1;
                    final included     = plan.features.contains(key);
                    final icon         = _featureIcons[key] ?? Icons.check_circle;
                    final isCallCenter = key == 'call_center';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            included
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 18,
                            color: included
                                ? const Color(0xFF10B981)
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            icon,
                            size: 15,
                            color: included
                                ? (isCallCenter
                                ? const Color(0xFF6366F1)
                                : Colors.black54)
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              label,
                              style: AppTypography.body2.copyWith(
                                color: included
                                    ? Colors.black87
                                    : Colors.grey.shade400,
                                fontWeight: included
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isCallCenter && included)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '24/7',
                                style: AppTypography.caption.copyWith(
                                  color: const Color(0xFF6366F1),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // ── CTA button ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    isSelected ? AppColors.primary : Colors.grey.shade100,
                    foregroundColor:
                    isSelected ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isSelected
                        ? _t(lang, 'Select Vehicles & Pay',
                        'Sélectionner et payer')
                        : _t(lang, 'Select Plan', 'Choisir ce forfait'),
                    style: AppTypography.button.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment bottom sheet  —  2-step: vehicle selection → payment details
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentSheet extends StatefulWidget {
  final _Plan plan;
  final int? preselectedVehicleId;
  final String lang;

  const _PaymentSheet({
    required this.plan,
    required this.lang,
    this.preselectedVehicleId,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  int _step = 0;

  List<Map<String, dynamic>> _userVehicles = [];
  List<int> _selectedVehicleIds = [];
  bool _loadingVehicles = false;

  String _method   = 'MOBILE_MONEY';
  String _provider = 'MTN';
  final TextEditingController _phoneController = TextEditingController();
  String? _countryCode;

  bool _isSubmitting = false;
  String? _submitError;

  String get _lang => widget.lang;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadUserVehicles();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final savedIso = prefs.getString('user_country_code');
    if (savedIso != null && mounted) {
      setState(() => _countryCode = savedIso);
    }

    if (_phoneController.text.isEmpty) {
      try {
        final userStr = prefs.getString('user');
        if (userStr != null) {
          final userMap  = jsonDecode(userStr) as Map<String, dynamic>;
          final rawPhone = userMap['phone']?.toString() ?? '';
          if (rawPhone.isNotEmpty) {
            // Derive the dial code from the saved ISO code and strip it
            // exactly. The old regex ^\+\d{1,4} was greedy and consumed
            // the leading '6' of Cameroonian numbers (+237 matched +2376).
            final dialCode = _kDialCodes[savedIso ?? ''];
            final String localPhone;
            if (dialCode != null && rawPhone.startsWith(dialCode)) {
              localPhone = rawPhone.substring(dialCode.length);
            } else {
              // Fallback: strip '+' + digits up to the last 9 local digits.
              localPhone = rawPhone.replaceFirst(
                  RegExp(r'^\+\d+?(?=\d{9}$)'), '');
            }
            if (mounted) setState(() => _phoneController.text = localPhone);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not load phone from session: $e');
      }
    }
  }

  Future<void> _loadUserVehicles() async {
    setState(() => _loadingVehicles = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final vehiclesJson = prefs.getString('vehicles_list');
      if (vehiclesJson != null) {
        final List<dynamic> list = jsonDecode(vehiclesJson);
        final vehicles = list.map((v) => v as Map<String, dynamic>).toList();
        setState(() {
          _userVehicles = vehicles;
          _selectedVehicleIds = widget.preselectedVehicleId != null
              ? [widget.preselectedVehicleId!]
              : vehicles.map<int>((v) => v['id'] as int).toList();
        });
        return;
      }

      final userStr = prefs.getString('user');
      if (userStr == null) return;
      final userId = (jsonDecode(userStr)['id'] as num).toInt();
      final data = await ApiService.get('/voitures/user/$userId');
      if (data['success'] == true) {
        final vehicles = (data['vehicles'] as List<dynamic>)
            .map((v) => v as Map<String, dynamic>)
            .toList();
        setState(() {
          _userVehicles = vehicles;
          _selectedVehicleIds = widget.preselectedVehicleId != null
              ? [widget.preselectedVehicleId!]
              : vehicles.map<int>((v) => v['id'] as int).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading vehicles: $e');
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  double get _totalAmount => widget.plan.price * _selectedVehicleIds.length;

  String get _totalLabel {
    final v = _totalAmount;
    final f = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(0);
    return '$f ${widget.plan.currency}';
  }

  Future<void> _submit() async {
    // Phone safety check
    if (_method == 'MOBILE_MONEY' && _phoneController.text.trim().isEmpty) {
      setState(() => _submitError = _t(_lang,
          'Phone number not found. Please log out and log in again.',
          'Numéro introuvable. Veuillez vous déconnecter puis vous reconnecter.'));
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 🔥 ALWAYS get fresh country code from storage (no async timing issues)
      final String countryCode =
          _countryCode ?? prefs.getString('user_country_code') ?? 'CM';

      final isBatch     = _selectedVehicleIds.length > 1;
      final apiProvider = _kProviderCodes[_provider] ?? _provider;

      final Map<String, dynamic> body = {
        'plan_id': widget.plan.id,
        'method':  _method,

        if (_method == 'MOBILE_MONEY') 'provider': apiProvider,
        if (_method == 'MOBILE_MONEY')
          'phone_number': _phoneController.text.trim(),

        // ✅ ALWAYS INCLUDED NOW
        if (_method == 'MOBILE_MONEY')
          'country_code': countryCode,
      };

      // 🕵️ Debug log (optional but powerful)
      debugPrint("🚀 PAYMENT BODY: $body");

      final Map<String, dynamic> result = isBatch
          ? await ApiService.post('/payments/initiate-batch', body: {
        ...body,
        'vehicle_ids': _selectedVehicleIds,
      })
          : await ApiService.post('/payments/initiate', body: {
        ...body,
        'vehicle_id': _selectedVehicleIds.first,
      });

      if (!mounted) return;

      if (result['success'] == true) {
        final data        = result['data'] as Map<String, dynamic>;
        final redirectUrl = data['redirect_url'] as String?;
        final paymentId   = isBatch
            ? (data['payment_ids'] as List).first as int
            : data['payment_id'] as int;

        Navigator.of(context).pop();

        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WebViewPaymentScreen(
                redirectUrl: redirectUrl,
                paymentId:   paymentId,
                planLabel:   widget.plan.name,
                amount:      _totalLabel,
                currency:    widget.plan.currency,
              ),
            ),
          );
        }
      } else {
        setState(() => _submitError =
            result['message']?.toString() ??
                _t(_lang, 'Payment initiation failed.',
                    'Échec de l\'initiation du paiement.'));
      }
    } catch (e) {
      setState(() => _submitError = _t(_lang,
          'Something went wrong. Please try again.',
          'Une erreur s\'est produite. Veuillez réessayer.'));
      debugPrint('❌ Payment error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  if (_step == 1)
                    GestureDetector(
                      onTap: () => setState(() => _step = 0),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16, color: Colors.black54),
                    ),
                  if (_step == 1) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _step == 0
                          ? _t(_lang, 'Select Vehicles',
                          'Sélectionner les véhicules')
                          : _t(_lang, 'Payment Details',
                          'Détails du paiement'),
                      style: AppTypography.h3.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _t(_lang, 'Step ${_step + 1} of 2',
                          'Étape ${_step + 1} sur 2'),
                      style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade100),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child:
                _step == 0 ? _buildVehicleStep() : _buildPaymentStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 0: vehicle selection ───────────────────────────────────────────────

  Widget _buildVehicleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanSummaryBanner(plan: widget.plan, lang: _lang),
        const SizedBox(height: 20),
        Text(
          _t(_lang, 'Which vehicles to subscribe?',
              'Quels véhicules abonner ?'),
          style: AppTypography.body2
              .copyWith(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 10),

        if (_loadingVehicles)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_userVehicles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                _t(_lang, 'No vehicles found.', 'Aucun véhicule trouvé.'),
                style: AppTypography.body2
                    .copyWith(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ..._userVehicles.map((v) {
            final id              = v['id'] as int;
            final nick            = v['nickname'] as String?;
            final name            = (nick != null && nick.isNotEmpty)
                ? nick
                : '${v['marque'] ?? v['brand'] ?? ''} ${v['model'] ?? ''}'
                .trim();
            final plate           = v['immatriculation'] as String? ?? '';
            final selected        = _selectedVehicleIds.contains(id);
            final hasSubscription = v['has_active_subscription'] == true;

            return GestureDetector(
              onTap: () => setState(() {
                selected
                    ? _selectedVehicleIds.remove(id)
                    : _selectedVehicleIds.add(id);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.06)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : Colors.grey.shade200,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // ── Car icon ─────────────────────────────────────────
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.directions_car_rounded,
                          size: 20,
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade500),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body2.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AppColors.primary
                                  : Colors.black87,
                            ),
                          ),
                          if (plate.isNotEmpty)
                            Text(
                              plate,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption
                                  .copyWith(color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: hasSubscription
                            ? const Color(0xFF10B981).withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasSubscription
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 15,
                        color: hasSubscription
                            ? const Color(0xFF10B981)
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade400,
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 16),

        if (_selectedVehicleIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${_selectedVehicleIds.length} '
                        '${_selectedVehicleIds.length > 1 ? _t(_lang, 'vehicles', 'véhicules') : _t(_lang, 'vehicle', 'véhicule')} '
                        '× ${widget.plan.priceLabel}',
                    style: AppTypography.body2
                        .copyWith(color: Colors.black54),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _totalLabel,
                  style: AppTypography.body1.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedVehicleIds.isEmpty
                ? null
                : () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: Text(
              _t(_lang, 'Continue to Payment',
                  'Continuer vers le paiement'),
              style: AppTypography.button.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Step 1: payment details ─────────────────────────────────────────────────

  Widget _buildPaymentStep() {
    final hasCallCenter = widget.plan.features.contains('call_center');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanSummaryBanner(
            plan: widget.plan,
            vehicleCount: _selectedVehicleIds.length,
            lang: _lang),
        const SizedBox(height: 20),

        // ── Call center strip ─────────────────────────────────────────────
        if (hasCallCenter) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF6366F1).withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(_lang, '24/7 Call Center Included',
                            'Assistance téléphonique 24h/24 incluse'),
                        style: AppTypography.body2.copyWith(
                          color: const Color(0xFF6366F1),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t(_lang,
                            'Your plan includes round-the-clock assistance for your fleet.',
                            'Votre forfait inclut une assistance permanente pour votre flotte.'),
                        style: AppTypography.caption.copyWith(
                            color: const Color(0xFF6366F1).withOpacity(0.75),
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        Text(_t(_lang, 'Payment Method', 'Mode de paiement'),
            style:
            AppTypography.body1.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MethodTile(
                label:    _t(_lang, 'E-Wallet', 'Portefeuille'),
                icon:     Icons.account_balance_wallet_rounded,
                selected: _method == 'MOBILE_MONEY',
                onTap:    () => setState(() => _method = 'MOBILE_MONEY'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MethodTile(
                label:    _t(_lang, 'Cash', 'Espèces'),
                icon:     Icons.payments_rounded,
                selected: _method == 'CASH',
                onTap:    () => setState(() => _method = 'CASH'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_method == 'MOBILE_MONEY') ...[
          Text(_t(_lang, 'Provider', 'Opérateur'),
              style: AppTypography.body2.copyWith(
                  fontWeight: FontWeight.w600, color: Colors.black54)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ProviderTile(
                  label:     'MTN',
                  logoAsset: _kMtnLogoAsset,
                  color:     const Color(0xFFFFC107),
                  selected:  _provider == 'MTN',
                  onTap:     () => setState(() => _provider = 'MTN'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProviderTile(
                  label:     'Orange',
                  logoAsset: _kOrangeLogoAsset,
                  color:     const Color(0xFFFF6600),
                  selected:  _provider == 'ORANGE',
                  onTap:     () => setState(() => _provider = 'ORANGE'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Phone number — hidden, re-filled from session ──────────────
          // The controller holds the local number (e.g. 6XXXXXXXX) and is
          // sent in the request body exactly as before. Visibility(false) +
          // maintainState keeps the controller alive without rendering the
          // field, so the user cannot see or modify the number.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(_lang, 'Phone Number', 'Numéro de téléphone'),
                style: AppTypography.body2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: _t(_lang, 'Enter phone number', 'Entrez le numéro'),
                  prefixIcon: const Icon(Icons.phone_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],

        if (_method == 'CASH') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(_lang,
                        'Our team will contact you to arrange a cash payment.',
                        'Notre équipe vous contactera pour organiser le paiement en espèces.'),
                    style: AppTypography.body2.copyWith(
                        color: Colors.amber.shade800, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_submitError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_submitError!,
                      style: AppTypography.body2
                          .copyWith(color: AppColors.error)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Total + Pay ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_t(_lang, 'Total due', 'Total à payer'),
                      style: AppTypography.caption
                          .copyWith(color: Colors.black45)),
                  Text(
                    _totalLabel,
                    style: AppTypography.h3.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                    AppColors.primary.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                      : Text(
                    _method == 'MOBILE_MONEY'
                        ? _t(_lang, 'Pay Now', 'Payer maintenant')
                        : _t(_lang, 'Submit', 'Envoyer'),
                    style: AppTypography.button.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PaymentHistoryScreen()),
              );
            },
            icon:  const Icon(Icons.receipt_long_rounded, size: 16),
            label: Text(_t(_lang, 'View payment history',
                'Voir l\'historique des paiements')),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black45,
              textStyle: AppTypography.caption
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan summary banner
// ─────────────────────────────────────────────────────────────────────────────

class _PlanSummaryBanner extends StatelessWidget {
  final _Plan plan;
  final int? vehicleCount;
  final String lang;

  const _PlanSummaryBanner({
    required this.plan,
    required this.lang,
    this.vehicleCount,
  });

  @override
  Widget build(BuildContext context) {
    final count = vehicleCount ?? 1;
    final total = plan.price * count;
    final f = total == total.truncateToDouble()
        ? total.toInt().toString()
        : total.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.workspace_premium_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                    style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.bold, color: Colors.black87)),
                Text(plan.durationLabel(lang),
                    style: AppTypography.caption
                        .copyWith(color: Colors.grey.shade500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                vehicleCount != null ? '$f ${plan.currency}' : plan.priceLabel,
                style: AppTypography.body1.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w900),
              ),
              if (vehicleCount != null && vehicleCount! > 1)
                Text(
                  '$vehicleCount ${_t(lang, 'vehicles', 'véhicules')}',
                  style: AppTypography.caption
                      .copyWith(color: Colors.grey.shade400),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MethodTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color:
                selected ? AppColors.primary : Colors.grey.shade500),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body2.copyWith(
                  fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
                  color: selected
                      ? AppColors.primary
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final String label;
  final String logoAsset;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.label,
    required this.logoAsset,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                logoAsset,
                height: 24,
                width: 36,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 24,
                  color: selected ? color : Colors.grey.shade400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.body2.copyWith(
                fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / Error states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String lang;
  const _LoadingView({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            _t(lang, 'Loading plans...', 'Chargement des forfaits…'),
            style:
            AppTypography.body2.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String lang;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(message,
                style: AppTypography.body2
                    .copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                _t(lang, 'Retry', 'Réessayer'),
                style: AppTypography.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}