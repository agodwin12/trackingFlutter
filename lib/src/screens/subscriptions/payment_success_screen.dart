// lib/src/screens/subscriptions/payment_success_screen.dart
//
// Used for CASH payments only.
// Mobile Money payments are confirmed by PaymentPendingScreen
// which handles success inline and uses the same PaymentNotifier.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/vehicles_refresh_service.dart';
import '../../services/payment_notifier.dart';

String _t(String lang, String en, String fr) => lang == 'fr' ? fr : en;

class PaymentSuccessScreen extends StatefulWidget {
  final String  method;
  final String  planLabel;
  final String  amount;
  final String  currency;
  final bool    isSuccess;
  final String? selectedLanguage;

  const PaymentSuccessScreen({
    Key? key,
    required this.method,
    required this.planLabel,
    required this.amount,
    required this.currency,
    this.isSuccess        = true,
    this.selectedLanguage,
  }) : super(key: key);

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with TickerProviderStateMixin {
  static const Color fleetraOrange = Color(0xFFFF6B35);

  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double>   _scaleAnimation;
  late Animation<double>   _fadeAnimation;

  String _lang         = 'en';
  bool   _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _initLang();

    _scaleController = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeController  = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut));
    _fadeAnimation  = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController,  curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 200),
            () => _scaleController.forward());
    Future.delayed(const Duration(milliseconds: 400),
            () => _fadeController.forward());

    if (widget.isSuccess) _silentRefresh();
  }

  Future<void> _initLang() async {
    if (widget.selectedLanguage != null) {
      setState(() => _lang = widget.selectedLanguage!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _lang = prefs.getString('language') ?? 'en');
  }

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    try {
      await VehiclesRefreshService.refreshVehiclesList();
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Go home ────────────────────────────────────────────────────────────────
  // 1. Signal the dashboard via PaymentNotifier (bypasses pop-result chain)
  // 2. popUntil(first) — clears the entire payment stack in one shot
  void _goHome() {
    if (!mounted) return;
    if (widget.isSuccess) {
      PaymentNotifier.instance.notifySuccess();
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final isCash    = widget.method == 'CASH';
    final isSuccess = widget.isSuccess;

    final title = isSuccess
        ? (isCash
        ? _t(_lang, 'Payment Recorded!',   'Paiement enregistré !')
        : _t(_lang, 'Payment Successful!', 'Paiement réussi !'))
        : _t(_lang, 'Payment Cancelled', 'Paiement annulé');

    final subtitle = isSuccess
        ? (isCash
        ? _t(_lang,
        'Your cash payment has been recorded and is awaiting confirmation from our team.',
        'Votre paiement en espèces a été enregistré et attend la confirmation de notre équipe.')
        : _t(_lang,
        'Your subscription for ${widget.planLabel} has been activated successfully.',
        'Votre abonnement pour ${widget.planLabel} a été activé avec succès.'))
        : _t(_lang,
        'Your payment was cancelled. No charges were made.',
        'Votre paiement a été annulé. Aucun montant n\'a été débité.');

    final statusValue = isCash
        ? _t(_lang, 'Pending Confirmation', 'En attente de confirmation')
        : _t(_lang, 'Active', 'Actif');

    return WillPopScope(
      onWillPop: () async {
        _goHome();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: isSuccess
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: isSuccess ? Colors.green : Colors.red,
                      size:  80,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(children: [
                    Text(
                      title,
                      style: AppTypography.h3.copyWith(
                        fontSize: 26,
                        color:    isSuccess ? AppColors.primary : Colors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    if (_isRefreshing) ...[
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
                                'Updating subscription...',
                                'Mise à jour de l\'abonnement...'),
                            style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    Text(
                      subtitle,
                      style: AppTypography.body2.copyWith(
                          color: AppColors.textSecondary, height: 1.5),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    if (isSuccess)
                      Container(
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
                            icon:  Icons.payment_rounded,
                            label: _t(_lang, 'Method', 'Mode de paiement'),
                            value: isCash
                                ? _t(_lang, 'Cash', 'Espèces')
                                : 'Mobile Money',
                          ),
                          const Divider(height: 24),
                          _buildDetailRow(
                            icon:       Icons.info_outline_rounded,
                            label:      _t(_lang, 'Status', 'Statut'),
                            value:      statusValue,
                            valueColor: isCash ? Colors.orange : Colors.green,
                          ),
                        ]),
                      ),
                  ]),
                ),

                const Spacer(),

                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isRefreshing ? null : _goHome,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:        fleetraOrange,
                        disabledBackgroundColor: fleetraOrange.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isRefreshing
                          ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : Text(
                        _t(_lang, 'Back to Home', 'Retour à l\'accueil'),
                        style: const TextStyle(
                          fontSize:   16,
                          fontWeight: FontWeight.w700,
                          color:      Colors.white,
                        ),
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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.subtitle1.copyWith(
              fontSize: 14,
              color:    valueColor ?? AppColors.primary,
            ),
          ),
        ),
      ]);
}