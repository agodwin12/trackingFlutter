// lib/src/screens/subscriptions/payment_pending_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/socket_service.dart';
import '../../services/vehicles_refresh_service.dart';
import '../../services/payment_notifier.dart';

String _t(String lang, String en, String fr) => lang == 'fr' ? fr : en;

class PaymentPendingScreen extends StatefulWidget {
  final int     paymentId;
  final String  planLabel;
  final String  amount;
  final String  currency;
  final String? selectedLanguage;

  const PaymentPendingScreen({
    Key? key,
    required this.paymentId,
    required this.planLabel,
    required this.amount,
    required this.currency,
    this.selectedLanguage,
  }) : super(key: key);

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen>
    with TickerProviderStateMixin {
  static const Color fleetraOrange = Color(0xFFFF6B35);

  StreamSubscription<Map<String, dynamic>>? _paymentSub;
  bool   _handled      = false;
  bool   _isRefreshing = false;
  bool   _showSuccess  = false;
  String _lang         = 'en';

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;
  late AnimationController _dotsController;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _initLang();
    _setupPulseAnimation();
    _setupDotsAnimation();
    _listenForPaymentUpdate();
  }

  Future<void> _initLang() async {
    if (widget.selectedLanguage != null) {
      setState(() => _lang = widget.selectedLanguage!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _lang = prefs.getString('language') ?? 'en');
  }

  void _setupPulseAnimation() {
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _setupDotsAnimation() {
    _dotsController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _dotCount = _dotCount < 3 ? _dotCount + 1 : 1);
        _dotsController.reset();
        _dotsController.forward();
      }
    });
    _dotsController.forward();
  }

  void _listenForPaymentUpdate() {
    debugPrint('👂 [PENDING] Listening for payment_update...');
    _paymentSub = SocketService().paymentUpdateStream.listen((data) {
      debugPrint('💳 [PENDING] payment_update: $data');

      final int? incomingId = data['payment_id'] is int
          ? data['payment_id'] as int
          : int.tryParse(data['payment_id']?.toString() ?? '');

      if (incomingId != null && incomingId != widget.paymentId) return;
      if (_handled) return;
      _handled = true;

      final status = (data['status'] ?? '') as String;
      if (status == 'SUCCESS') {
        _handleSuccess();
      } else if (status == 'FAILED') {
        _handleFailed();
      }
    });
  }

  // ── SUCCESS ────────────────────────────────────────────────────────────────
  // 1. Refresh SharedPreferences (vehicles_list)
  // 2. Show a brief success checkmark on this screen
  // 3. Signal the dashboard via PaymentNotifier (works across any stack depth)
  // 4. popUntil(first) — clears the entire payment stack
  //    The dashboard's listener fires reloadVehicles() which hits the API
  //    and calls notifyListeners() so the vehicle selector rebuilds.
  Future<void> _handleSuccess() async {
    if (!mounted) return;

    // Step 1 — refresh SharedPreferences while user sees the spinner
    setState(() => _isRefreshing = true);
    try {
      await VehiclesRefreshService.refreshVehiclesList();
      debugPrint('✅ [PENDING] vehicles_list refreshed in SharedPreferences');
    } catch (e) {
      debugPrint('⚠️ [PENDING] refresh error (non-fatal): $e');
    }
    if (!mounted) return;
    setState(() => _isRefreshing = false);

    // Step 2 — show success checkmark for 1.5 s
    setState(() => _showSuccess = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // Step 3 — signal the dashboard (bypasses the broken pop-result chain)
    PaymentNotifier.instance.notifySuccess();

    // Step 4 — pop the entire payment stack back to the dashboard
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── FAILED ─────────────────────────────────────────────────────────────────
  void _handleFailed() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showSuccess) return false;
        _showLeaveConfirmation();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),

                _showSuccess ? _buildSuccessIcon() : _buildPendingIcon(),

                const SizedBox(height: 40),

                Text(
                  _showSuccess
                      ? _t(_lang, 'Payment Successful!', 'Paiement réussi !')
                      : _t(_lang, 'Payment Pending',     'Paiement en attente'),
                  style: AppTypography.h3.copyWith(
                    fontSize: 26,
                    color: _showSuccess
                        ? const Color(0xFF10B981)
                        : AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                if (_isRefreshing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _t(_lang,
                            'Activating subscription...',
                            'Activation de l\'abonnement...'),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  )
                else
                  Text(
                    _showSuccess
                        ? _t(_lang,
                        'Your subscription is now active.',
                        'Votre abonnement est maintenant actif.')
                        : '${_t(_lang, 'Waiting for confirmation', 'En attente de confirmation')}${'.' * _dotCount}',
                    style: AppTypography.body2.copyWith(
                        color: AppColors.textSecondary, height: 1.5),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 32),

                if (!_showSuccess) ...[
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                  _buildHintBox(),
                ],

                const Spacer(flex: 3),

                if (!_showSuccess)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _showLeaveConfirmation,
                      style: OutlinedButton.styleFrom(
                        side:  const BorderSide(color: fleetraOrange),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _t(_lang, 'Back to Settings', 'Retour aux paramètres'),
                        style: const TextStyle(
                          fontSize:   16,
                          fontWeight: FontWeight.w700,
                          color:      fleetraOrange,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingIcon() => ScaleTransition(
    scale: _pulseAnimation,
    child: Container(
      width: 130, height: 130,
      decoration: BoxDecoration(
        color: fleetraOrange.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.hourglass_top_rounded,
          color: fleetraOrange, size: 72),
    ),
  );

  Widget _buildSuccessIcon() => Container(
    width: 130, height: 130,
    decoration: BoxDecoration(
      color: const Color(0xFF10B981).withOpacity(0.1),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.check_circle_rounded,
        color: Color(0xFF10B981), size: 72),
  );

  Widget _buildInfoCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color:        AppColors.white,
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: AppColors.border),
    ),
    child: Column(children: [
      _buildDetailRow(
        icon:  Icons.subscriptions_outlined,
        label: _t(_lang, 'Plan', 'Forfait'),
        value: widget.planLabel,
      ),
      if (widget.amount.isNotEmpty) ...[
        const Divider(height: 24),
        _buildDetailRow(
          icon:  Icons.payments_outlined,
          label: _t(_lang, 'Amount', 'Montant'),
          value: '${widget.amount} ${widget.currency}',
        ),
      ],
      const Divider(height: 24),
      _buildDetailRow(
        icon:       Icons.info_outline_rounded,
        label:      _t(_lang, 'Status', 'Statut'),
        value:      _t(_lang, 'Awaiting confirmation',
            'En attente de confirmation'),
        valueColor: Colors.orange,
      ),
    ]),
  );

  Widget _buildHintBox() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        Colors.blue.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded,
            color: Colors.blue, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _t(_lang,
                'Please do not close the app. This screen will update automatically once your payment is confirmed.',
                'Veuillez ne pas fermer l\'application. Cet écran se mettra à jour automatiquement une fois votre paiement confirmé.'),
            style: AppTypography.caption
                .copyWith(color: Colors.blue.shade700, height: 1.5),
          ),
        ),
      ],
    ),
  );

  void _showLeaveConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(
          _t(_lang, 'Leave this screen?', 'Quitter cet écran ?'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(_t(_lang,
            'Your payment is still being processed. If you leave, you won\'t see the confirmation here, but the payment will still complete in the background.',
            'Votre paiement est toujours en cours de traitement. Si vous partez, vous ne verrez pas la confirmation ici, mais le paiement se finalisera quand même en arrière-plan.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t(_lang, 'Stay', 'Rester'),
                style: const TextStyle(color: fleetraOrange)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fleetraOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(_t(_lang, 'Leave', 'Quitter'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String   label,
    required String   value,
    Color?            valueColor,
  }) =>
      Row(children: [
        Icon(icon, color: fleetraOrange, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: AppTypography.caption
                .copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        Text(value,
            style: AppTypography.subtitle1.copyWith(
                fontSize: 14,
                color: valueColor ?? AppColors.primary)),
      ]);
}