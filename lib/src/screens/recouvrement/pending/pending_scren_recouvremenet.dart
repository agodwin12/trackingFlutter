// lib/src/screens/recouvrement/pending/pending_scren_recouvremenet.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';

import '../../../services/env_config.dart';
 import '../../../services/recouvremenet_payment_event_sse_service.dart';
import '../../../services/token_refresh_service.dart';
import '../payment_result/payment_result.dart';

// ── Palette (matches pay_lease.dart) ─────────────────────────────────────────
const Color _bg          = Color(0xFF0D1117);
const Color _bgSubtle    = Color(0xFF161B22);
const Color _card        = Color(0xFF1C2333);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);
const Color _textPrimary = Color(0xFFE6EDF3);

// ══════════════════════════════════════════════════════════════════════════════
// PaymentPendingScreen
// ══════════════════════════════════════════════════════════════════════════════
class RecouvrementPaymentPendingScreen extends StatefulWidget {
  final String reference;   // reference_interne (MOB.xxxx) from initier-paiement/
  final double amount;
  final int    leaseCount;
  final String phone;       // 9-digit number, displayed with +237
  final String accessToken; // used for SSE /events/?token=...

  const RecouvrementPaymentPendingScreen({
    Key? key,
    required this.reference,
    required this.amount,
    required this.leaseCount,
    required this.phone,
    required this.accessToken,
  }) : super(key: key);

  @override
  State<RecouvrementPaymentPendingScreen> createState() =>
      _RecouvrementPaymentPendingScreenState();
}

class _RecouvrementPaymentPendingScreenState
    extends State<RecouvrementPaymentPendingScreen>
    with SingleTickerProviderStateMixin {

  // ── Config ────────────────────────────────────────────────────────────────
  static const _pollInterval = Duration(seconds: 4);
  static const _timeout      = Duration(seconds: 90);

  // ── State ─────────────────────────────────────────────────────────────────
  Timer? _pollTimer;
  Timer? _timeoutTimer;

  int  _elapsed   = 0;
  bool _navigated = false;

  late AnimationController _dotCtrl;

  final _tokenService = TokenRefreshService();
  String get _baseUrl => EnvConfig.partnerApiUrl;

  // ── SSE ───────────────────────────────────────────────────────────────────
  PaymentEventSseService? _sseService;
  StreamSubscription<PaymentSseEvent>? _sseSubscription;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // SSE first (real-time), polling as a safety net.
    _startSseListener();
    _startPolling();

    _timeoutTimer = Timer(_timeout, () {
      if (!_navigated) _goToResult(success: false, timedOut: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _sseSubscription?.cancel();
    _sseService?.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  // ── SSE listener ──────────────────────────────────────────────────────────
  void _startSseListener() {
    _sseService = PaymentEventSseService(
      getAccessToken: () async => widget.accessToken,
    );

    _sseSubscription = _sseService!.connect().listen(
          (event) {
        if (_navigated || !mounted) return;

        // Only completion events for THIS transaction.
        if (!event.isTransactionCompleted) return;
        if (!event.matchesReference(widget.reference)) return;

        if (event.isSuccess) {
          _goToResult(success: true);
        } else if (event.isFailed) {
          _goToResult(success: false);
        }
      },
      onError: (_) {
        // SSE failure is non-fatal — polling remains active.
      },
      cancelOnError: false,
    );
  }

  // ── Polling fallback ──────────────────────────────────────────────────────
  void _startPolling() {
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _elapsed += _pollInterval.inSeconds;
      if (mounted) setState(() {});
      _poll();
    });
  }

  Future<void> _poll() async {
    if (_navigated) return;

    try {
      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.get(
          Uri.parse('$_baseUrl/statut-paiement/?reference=${widget.reference}'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        ).timeout(const Duration(seconds: 10)),
      );

      if (!mounted || _navigated) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final status = (
            data['statut'] ??
                data['status'] ??
                data['data']?['statut'] ??
                data['data']?['status'] ??
                ''
        ).toString().toUpperCase();

        if (status == 'SUCCESS') {
          _goToResult(success: true);
        } else if (_isFailureStatus(status)) {
          _goToResult(success: false);
        }
        // PENDING / empty → keep polling.
      }
    } catch (_) {
      // Network hiccup — keep polling silently.
    }
  }

  bool _isFailureStatus(String status) =>
      status == 'FAILED' ||
          status == 'FAILURE' ||
          status == 'CANCELLED' ||
          status == 'CANCELED' ||
          status == 'ERROR' ||
          status == 'REJECTED';

  void _goToResult({required bool success, bool timedOut = false}) {
    if (_navigated) return;
    _navigated = true;

    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _sseSubscription?.cancel();
    _sseService?.dispose();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => RecouvrementPaymentResultScreen(
          success   : success,
          timedOut  : timedOut,
          amount    : widget.amount,
          leaseCount: widget.leaseCount,
          reference : widget.reference,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  double get _progress => (_elapsed / _timeout.inSeconds).clamp(0.0, 1.0);

  int get _remainingSeconds {
    final r = _timeout.inSeconds - _elapsed;
    return r < 0 ? 0 : r;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: PopScope(
        canPop: false, // payment in flight — block back
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                SizedBox(
                  width: 200, height: 200,
                  child: Lottie.network(
                    'https://assets9.lottiefiles.com/packages/lf20_myejiggj.json',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: CircularProgressIndicator(
                          color: _orange, strokeWidth: 3),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Paiement en cours',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: _textPrimary),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                AnimatedBuilder(
                  animation: _dotCtrl,
                  builder: (_, __) {
                    final dots = '.' * ((_dotCtrl.value * 4).floor() % 4);
                    return Text(
                      'En attente de confirmation$dots',
                      style: const TextStyle(fontSize: 14, color: _textMuted),
                    );
                  },
                ),

                const SizedBox(height: 36),

                // ── Amount card ────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(children: [
                    Text(
                      'XAF ${_fmt(widget.amount)}',
                      style: const TextStyle(fontSize: 32,
                          fontWeight: FontWeight.w900, color: _orange,
                          letterSpacing: -1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.leaseCount} Lease${widget.leaseCount > 1 ? 's' : ''} sélectionné${widget.leaseCount > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 13, color: _textMuted),
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: _border, height: 1),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Icon(Icons.phone_android_rounded,
                          color: _textMuted, size: 14),
                      const SizedBox(width: 8),
                      Text('+237 ${widget.phone}',
                          style: const TextStyle(fontSize: 13, color: _textMuted)),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.tag_rounded, color: _textMuted, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        widget.reference,
                        style: const TextStyle(fontSize: 11, color: _textMuted,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ]),
                ),

                const SizedBox(height: 32),

                // ── Progress bar ───────────────────────────────────────────
                Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Délai d\'expiration',
                          style: TextStyle(fontSize: 11, color: _textMuted)),
                      Text(
                        '${_remainingSeconds}s',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _elapsed > 60
                                ? const Color(0xFFDC2626)
                                : _textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: _progress),
                      duration: const Duration(milliseconds: 600),
                      builder: (_, value, __) => LinearProgressIndicator(
                        value: value,
                        backgroundColor: _bgSubtle,
                        valueColor: AlwaysStoppedAnimation(
                          value > 0.75
                              ? const Color(0xFFDC2626)
                              : value > 0.5
                              ? const Color(0xFFD97706)
                              : _orange,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 28),

                // ── Info note ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _bgSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: _textMuted, size: 16),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Acceptez la demande de paiement sur votre téléphone. '
                          'Ne fermez pas cette page.',
                      style: TextStyle(fontSize: 12, color: _textMuted, height: 1.5),
                    )),
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
}