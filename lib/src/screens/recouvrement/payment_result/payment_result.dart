// lib/src/screens/recouvrement/payment_result/payment_result.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../../services/payment_notifier.dart'; // existing PaymentNotifier singleton

// ── Palette ───────────────────────────────────────────────────────────────────
const Color _bg          = Color(0xFF0D1117);
const Color _bgSubtle    = Color(0xFF161B22);
const Color _card        = Color(0xFF1C2333);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);
const Color _textPrimary = Color(0xFFE6EDF3);
const Color _green       = Color(0xFF16A34A);
const Color _red         = Color(0xFFDC2626);

// ── Lottie URLs ───────────────────────────────────────────────────────────────
// Free assets hosted on LottieFiles CDN — no asset bundling needed.
const _lottieSuccess = 'https://assets9.lottiefiles.com/packages/lf20_lk80fpsm.json';
const _lottieFailed  = 'https://assets4.lottiefiles.com/packages/lf20_qp1q7mct.json';

// ══════════════════════════════════════════════════════════════════════════════
// PaymentResultScreen
// ══════════════════════════════════════════════════════════════════════════════
class RecouvrementPaymentResultScreen extends StatefulWidget {
  final bool   success;
  final bool   timedOut;
  final double amount;
  final int    leaseCount;
  final String reference;

  const RecouvrementPaymentResultScreen({
    Key? key,
    required this.success,
    required this.timedOut,
    required this.amount,
    required this.leaseCount,
    required this.reference,
  }) : super(key: key);

  @override
  State<RecouvrementPaymentResultScreen> createState() =>
      _RecouvrementPaymentResultScreenState();
}

class _RecouvrementPaymentResultScreenState
    extends State<RecouvrementPaymentResultScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _lottieCtrl;
  bool _lottieFinished = false;
  Timer? _autoReturnTimer;

  @override
  void initState() {
    super.initState();

    _lottieCtrl = AnimationController(vsync: this);

    // On success: fire PaymentNotifier so the dashboard refreshes,
    // then auto-return to the dashboard after a short delay.
    if (widget.success) {
      PaymentNotifier.instance.notifySuccess();
      _autoReturnTimer = Timer(const Duration(seconds: 4), _returnToDashboard);
    }
  }

  @override
  void dispose() {
    _lottieCtrl.dispose();
    _autoReturnTimer?.cancel();
    super.dispose();
  }

  // Navigation stack at this point: [dashboard, pay_lease, result]
  // (pending was replaced by result via pushReplacement).
  void _returnToDashboard() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _retry() {
    if (!mounted) return;
    // A single pop lands back on PayLeaseScreen — pending no longer exists
    // in the stack (it was replaced). A double pop would skip pay_lease
    // and dump the user on the dashboard.
    Navigator.of(context).pop();
  }

  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final success = widget.success;
    final color   = success ? _green : _red;

    return Scaffold(
      backgroundColor: _bg,
      body: PopScope(
        // Allow back on failure so the user can retry; block on success
        // (auto-return handles it).
        canPop: !success,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                const Spacer(flex: 2),

                // ── Lottie ─────────────────────────────────────────────────
                SizedBox(
                  width: 220, height: 220,
                  child: Lottie.network(
                    success ? _lottieSuccess : _lottieFailed,
                    controller: _lottieCtrl,
                    fit: BoxFit.contain,
                    repeat: false,
                    onLoaded: (composition) {
                      _lottieCtrl
                        ..duration = composition.duration
                        ..forward().whenComplete(() {
                          if (mounted) setState(() => _lottieFinished = true);
                        });
                    },
                    errorBuilder: (_, __, ___) {
                      // Fallback icon if Lottie can't load.
                      return Center(child: Icon(
                        success
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: color,
                        size: 80,
                      ));
                    },
                  ),
                ),

                const SizedBox(height: 28),

                // ── Title ──────────────────────────────────────────────────
                Text(
                  success ? 'Paiement confirmé !' : _failTitle,
                  style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900,
                    color: success ? _textPrimary : _red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  success ? _successSubtitle : _failSubtitle,
                  style: const TextStyle(
                    fontSize: 14, color: _textMuted, height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 36),

                // ── Amount card (success only) ─────────────────────────────
                if (success) ...[
                  _amountCard(color),
                  const SizedBox(height: 32),
                ],

                // ── Failure detail card ────────────────────────────────────
                if (!success) ...[
                  _failCard(),
                  const SizedBox(height: 32),
                ],

                // ── Actions ────────────────────────────────────────────────
                AnimatedOpacity(
                  opacity: _lottieFinished || !success ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Column(children: [
                    if (success)
                      _primaryBtn(
                        label: 'Retour au tableau de bord',
                        icon : Icons.dashboard_rounded,
                        color: _green,
                        onTap: _returnToDashboard,
                      )
                    else ...[
                      _primaryBtn(
                        label: 'Réessayer le paiement',
                        icon : Icons.refresh_rounded,
                        color: _orange,
                        onTap: _retry,
                      ),
                      const SizedBox(height: 12),
                      _secondaryBtn(
                        label: 'Retour au tableau de bord',
                        onTap: _returnToDashboard,
                      ),
                    ],
                  ]),
                ),

                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Subwidgets ─────────────────────────────────────────────────────────────
  Widget _amountCard(Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(0.35)),
      boxShadow: [BoxShadow(
        color: color.withOpacity(0.08),
        blurRadius: 20, offset: const Offset(0, 6),
      )],
    ),
    child: Column(children: [
      const Icon(Icons.check_circle_rounded, color: _green, size: 32),
      const SizedBox(height: 14),
      Text(
        'XAF ${_fmt(widget.amount)}',
        style: const TextStyle(
          fontSize: 34, fontWeight: FontWeight.w900,
          color: _textPrimary, letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '${widget.leaseCount} loyer${widget.leaseCount > 1 ? 's' : ''} réglé${widget.leaseCount > 1 ? 's' : ''}',
        style: const TextStyle(fontSize: 13, color: _textMuted),
      ),
      const SizedBox(height: 16),
      const Divider(color: _border, height: 1),
      const SizedBox(height: 12),
      Row(children: [
        const Icon(Icons.tag_rounded, color: _textMuted, size: 13),
        const SizedBox(width: 6),
        Expanded(child: Text(
          widget.reference,
          style: const TextStyle(fontSize: 11, color: _textMuted,
              fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    ]),
  );

  Widget _failCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _red.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _red.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [
        Icon(Icons.error_outline_rounded, color: _red, size: 18),
        SizedBox(width: 8),
        Text('Détails de l\'erreur',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: _textPrimary)),
      ]),
      const SizedBox(height: 12),
      _row('Montant',   'XAF ${_fmt(widget.amount)}'),
      const SizedBox(height: 6),
      _row('Référence', widget.reference),
      const SizedBox(height: 6),
      _row('Motif',
          widget.timedOut
              ? 'Délai d\'attente dépassé (90 s)'
              : 'Paiement refusé ou annulé'),
    ]),
  );

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Flexible(child: Text(value, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: _textPrimary),
          textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
    ],
  );

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
  );

  Widget _secondaryBtn({
    required String label,
    required VoidCallback onTap,
  }) => SizedBox(
    width: double.infinity, height: 48,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _textMuted,
        side: const BorderSide(color: _border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600)),
    ),
  );

  // ── Copy helpers ───────────────────────────────────────────────────────────
  String get _failTitle =>
      widget.timedOut ? 'Délai dépassé' : 'Paiement échoué';

  String get _successSubtitle =>
      'Votre paiement a été confirmé avec succès.\n'
          'Vous serez redirigé automatiquement.';

  String get _failSubtitle =>
      widget.timedOut
          ? 'Le délai de confirmation a été dépassé.\n'
          'Vérifiez votre solde et réessayez.'
          : 'Le paiement n\'a pas pu être traité.\n'
          'Vérifiez votre numéro ou votre solde.';
}