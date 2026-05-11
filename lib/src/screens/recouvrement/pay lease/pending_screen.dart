// lib/src/screens/recouvrement/pay lease/payment_pending_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../services/env_config.dart';
import '../../../services/token_refresh_service.dart';
import '../dashboard/recouvremenet_model.dart';
import 'package:FLEETRA/l10n/app_localizations.dart';

// ── Colours ───────────────────────────────────────────────────────────────────
const Color _bg          = Color(0xFF0D1117);
const Color _card        = Color(0xFF1C2333);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);
const Color _textPrimary = Color(0xFFE6EDF3);
const Color _green       = Color(0xFF16A34A);
const Color _yellow      = Color(0xFFD97706);

enum _PollState { pending, success, timeout }

class PaymentPendingScreen extends StatefulWidget {
  final List<Lease> selectedLeases;
  final double      totalAmount;
  final String      providerName;
  final String      reference;
  final String      accessToken;

  const PaymentPendingScreen({
    Key? key,
    required this.selectedLeases,
    required this.totalAmount,
    required this.providerName,
    required this.reference,
    required this.accessToken,
  }) : super(key: key);

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen>
    with TickerProviderStateMixin {

  _PollState   _state       = _PollState.pending;
  int          _attempt     = 0;
  static const _maxAttempts = 3;
  static const _interval    = 20;
  int          _countdown   = _interval;
  Timer?       _pollTimer;
  Timer?       _countdownTimer;

  List<Lease> _confirmedLeases = [];

  final _tokenService = TokenRefreshService();
  String get _leaseBaseUrl => EnvConfig.partnerApiUrl;

  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _successScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);

    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _startCountdown();
    _pollTimer = Timer(const Duration(seconds: _interval), _poll);
  }

  void _startCountdown() {
    _countdown = _interval;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() { if (_countdown > 0) _countdown--; });
    });
  }

  Future<void> _poll() async {
    if (!mounted) return;
    _attempt++;
    debugPrint('🔄 [Pending] Poll attempt $_attempt/$_maxAttempts');

    try {
      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.get(
          Uri.parse('$_leaseBaseUrl/leases/'),
          headers: {
            'Authorization':              'Bearer $token',
            'Content-Type':               'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        ).timeout(const Duration(seconds: 15)),
      );

      if (response.statusCode == 200) {
        final raw           = jsonDecode(response.body);
        final list          = raw is List ? raw : (raw is Map ? (raw['results'] as List? ?? []) : []);
        final updatedLeases = (list as List).map((e) => Lease.fromJson(e as Map<String, dynamic>)).toList();
        final selectedIds   = widget.selectedLeases.map((l) => l.id).toSet();
        _confirmedLeases    = updatedLeases
            .where((l) => selectedIds.contains(l.id) && l.isPaid).toList();

        if (_confirmedLeases.isNotEmpty) {
          _countdownTimer?.cancel();
          _pollTimer?.cancel();
          setState(() => _state = _PollState.success);
          _successCtrl.forward();
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Pending] Poll error: $e');
    }

    if (_attempt >= _maxAttempts) {
      _countdownTimer?.cancel();
      _pollTimer?.cancel();
      setState(() => _state = _PollState.timeout);
      return;
    }

    _startCountdown();
    _pollTimer = Timer(const Duration(seconds: _interval), _poll);
  }

  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  void _returnToDashboard() => Navigator.pop(context, 'refresh');

  @override
  Widget build(BuildContext context) {
    // ← FIX: ! because delegate is always registered in main.dart
    final t = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {},
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(t),
              Expanded(
                child: switch (_state) {
                  _PollState.pending => _buildPending(t),
                  _PollState.success => _buildSuccess(t),
                  _PollState.timeout => _buildTimeout(t),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () {
            if (_state == _PollState.pending) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      Localizations.localeOf(context).languageCode == 'fr'
                          ? 'Votre paiement est toujours en cours de traitement.'
                          : 'Your payment is still being processed.',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    )),
                  ]),
                  backgroundColor: _yellow,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            Navigator.pop(context, 'refresh');
          },
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _textMuted, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _state == _PollState.success
                  ? t.paymentConfirmed
                  : _state == _PollState.timeout
                  ? t.stillProcessing
                  : t.confirmingPayment,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary),
            ),
            Text(t.backToDashboard, style: const TextStyle(fontSize: 11, color: _textMuted)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPending(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 96, height: 96,
              decoration: BoxDecoration(color: _orange.withOpacity(0.12), shape: BoxShape.circle,
                  border: Border.all(color: _orange.withOpacity(0.4), width: 2)),
              child: const Center(
                child: SizedBox(width: 40, height: 40,
                    child: CircularProgressIndicator(color: _orange, strokeWidth: 3)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(t.confirmingPayment, style: const TextStyle(fontSize: 22,
              fontWeight: FontWeight.w800, color: _textPrimary)),
          const SizedBox(height: 10),
          Text(t.waitingForProvider(widget.providerName), textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.5)),
          const SizedBox(height: 32),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border)),
            child: Column(children: [
              _summaryRow(t.summaryAmount, 'XAF ${_fmt(widget.totalAmount)}'),
              const Divider(color: _border, height: 20),
              _summaryRow(t.summaryMethod, widget.providerName),
              const SizedBox(height: 8),
              _summaryRow(t.summaryLeases(widget.selectedLeases.length,
                  widget.selectedLeases.length > 1 ? 's' : ''), ''),
              const SizedBox(height: 8),
              _summaryRow(t.summaryReference, widget.reference,
                  valueStyle: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w500, color: _textMuted)),
            ]),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: _orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _orange.withOpacity(0.25))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.timer_outlined, color: _orange, size: 16),
              const SizedBox(width: 8),
              Text(t.checkingIn(_countdown, _attempt, _maxAttempts),
                  style: const TextStyle(fontSize: 13, color: _orange, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 20),
          Text(t.doNotCloseApp, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _textMuted.withOpacity(0.6))),
        ]),
      ),
    );
  }

  Widget _buildSuccess(AppLocalizations t) {
    final count   = _confirmedLeases.length;
    final plural  = count > 1 ? 's' : '';
    final plural2 = count > 1 ? 's' : '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ScaleTransition(
          scale: _successScale,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(color: _green.withOpacity(0.15), shape: BoxShape.circle,
                  border: Border.all(color: _green, width: 2)),
              child: const Icon(Icons.check_rounded, color: _green, size: 50),
            ),
            const SizedBox(height: 24),
            Text(t.paymentConfirmed, style: const TextStyle(fontSize: 24,
                fontWeight: FontWeight.w800, color: _textPrimary)),
            const SizedBox(height: 10),
            Text(t.paymentConfirmedSubtitle(count, plural, plural2, widget.providerName),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.5)),
            const SizedBox(height: 28),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _green.withOpacity(0.3))),
              child: Column(children: [
                _summaryRow(t.amountPaid, 'XAF ${_fmt(widget.totalAmount)}',
                    valueStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                        color: _green)),
                const Divider(color: _border, height: 20),
                _summaryRow(t.summaryMethod, widget.providerName),
                const SizedBox(height: 8),
                _summaryRow(t.summaryLeases(count, plural), t.leasesConfirmed(count, plural)),
                const SizedBox(height: 8),
                _summaryRow(t.summaryReference, widget.reference,
                    valueStyle: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w500, color: _textMuted)),
                const SizedBox(height: 8),
                _summaryRow(t.summaryStatus, t.confirmed,
                    valueStyle: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700, color: _green)),
              ]),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _returnToDashboard,
                style: ElevatedButton.styleFrom(backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                child: Text(t.backToDashboard,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTimeout(AppLocalizations t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: _yellow.withOpacity(0.12), shape: BoxShape.circle,
                border: Border.all(color: _yellow.withOpacity(0.4), width: 2)),
            child: const Icon(Icons.hourglass_bottom_rounded, color: _yellow, size: 48),
          ),
          const SizedBox(height: 24),
          Text(t.stillProcessing, style: const TextStyle(fontSize: 22,
              fontWeight: FontWeight.w800, color: _textPrimary)),
          const SizedBox(height: 10),
          Text(t.stillProcessingSubtitle, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.5)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _yellow.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _yellow.withOpacity(0.25))),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded, color: _yellow, size: 16),
                const SizedBox(width: 8),
                Text(t.whatToDo, style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: _yellow)),
              ]),
              const SizedBox(height: 10),
              Text('${t.timeoutStep1}\n${t.timeoutStep2}\n${t.timeoutStep3}',
                  style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.6)),
              const SizedBox(height: 10),
              _summaryRow(t.summaryReference, widget.reference,
                  valueStyle: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w500, color: _textMuted)),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _returnToDashboard,
              style: ElevatedButton.styleFrom(backgroundColor: _card,
                  foregroundColor: _textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _border)),
                  elevation: 0),
              child: Text(t.checkHistory,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {TextStyle? valueStyle}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Text(value, style: valueStyle ?? const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: _textPrimary)),
    ],
  );
}