// lib/src/screens/subscriptions/webview_payment_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/utility/app_theme.dart';
import 'payment_pending_screen.dart';
import 'payment_failed_screen.dart';

class WebViewPaymentScreen extends StatefulWidget {
  final String redirectUrl;
  final int paymentId;
  final String planLabel;
  final String amount;
  final String currency;

  const WebViewPaymentScreen({
    Key? key,
    required this.redirectUrl,
    required this.paymentId,
    required this.planLabel,
    required this.amount,
    required this.currency,
  }) : super(key: key);

  @override
  State<WebViewPaymentScreen> createState() => _WebViewPaymentScreenState();
}

class _WebViewPaymentScreenState extends State<WebViewPaymentScreen> {
  static const Color fleetraOrange = Color(0xFFFF6B35);

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError  = false;
  bool _handled   = false; // prevents duplicate navigation if bridge + URL both fire
  late final String _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolvedUrl = _extractValidUrl(widget.redirectUrl);
    debugPrint('🌐 [WEBVIEW] Resolved URL: $_resolvedUrl');
    _initWebView();
  }

  /// PayGate sometimes returns comma-separated URLs.
  /// Extract the first valid https:// URL, fallback to any valid URI.
  String _extractValidUrl(String raw) {
    if (!raw.contains(',')) return raw.trim();

    final parts = raw.split(',').map((u) => u.trim()).toList();

    final httpsUrl = parts.firstWhere(
          (u) => u.startsWith('https://'),
      orElse: () => '',
    );
    if (httpsUrl.isNotEmpty) return httpsUrl;

    for (final part in parts) {
      try {
        Uri.parse(part);
        return part;
      } catch (_) {}
    }

    return parts.first;
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)

    // ── JavaScript Bridge ───────────────────────────────────────────────────
    // Angular sends PAYGATE_SUCCESS as soon as PayGate redirects (before the
    // webhook fires). We treat it as "user finished on PayGate" and go to the
    // pending screen — which then waits for the real webhook confirmation via
    // Socket.IO before showing the final success screen.
    //
    // PAYGATE_CANCELLED means the user manually cancelled — no webhook will
    // ever come, so we go straight to the failed screen.
      ..addJavaScriptChannel(
        'FlutterWebView',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('📩 [WEBVIEW] JS Bridge message: ${message.message}');

          if (_handled) return;

          try {
            final Map<String, dynamic> data = jsonDecode(message.message);
            final String type = data['type'] ?? '';

            if (type == 'PAYGATE_SUCCESS') {
              debugPrint('✅ [WEBVIEW] Bridge: PAYGATE_SUCCESS → going to pending');
              _handled = true;
              _goToPending();
            } else if (type == 'PAYGATE_CANCELLED') {
              debugPrint('❌ [WEBVIEW] Bridge: PAYGATE_CANCELLED → going to failed');
              _handled = true;
              _goToFailed();
            } else {
              debugPrint('⚠️ [WEBVIEW] Bridge: Unknown event type → $type');
            }
          } catch (e) {
            debugPrint('❌ [WEBVIEW] Bridge: Failed to decode message → $e');
          }
        },
      )
    // ───────────────────────────────────────────────────────────────────────

      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('🌐 [WEBVIEW] Page started: $url');
            if (mounted) setState(() => _isLoading = true);

            // ── URL fallback — only fires if Angular bridge is unavailable ───
            // Same logic: success URL → pending, cancel URL → failed.
            if (!_handled) {
              if (_isSuccessUrl(url)) {
                debugPrint('✅ [WEBVIEW] Fallback: Success URL detected → pending');
                _handled = true;
                _goToPending();
              } else if (_isCancelUrl(url)) {
                debugPrint('❌ [WEBVIEW] Fallback: Cancel URL detected → failed');
                _handled = true;
                _goToFailed();
              }
            }
          },
          onPageFinished: (url) {
            debugPrint('🌐 [WEBVIEW] Page finished: $url');
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('❌ [WEBVIEW] Error: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError  = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_resolvedUrl));
  }

  // ── URL fallback helpers ──────────────────────────────────────────────────
  bool _isSuccessUrl(String url) {
    return url.contains('/payments/success') ||
        url.contains('payment_success') ||
        url.contains('status=success');
  }

  bool _isCancelUrl(String url) {
    return url.contains('/payments/cancel') ||
        url.contains('payment_cancel') ||
        url.contains('status=cancel');
  }
  // ─────────────────────────────────────────────────────────────────────────

  /// Angular sent PAYGATE_SUCCESS (or success URL detected).
  /// Payment may still be processing — go to pending and wait for webhook.
  void _goToPending() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentPendingScreen(
          paymentId: widget.paymentId,
          planLabel: widget.planLabel,
          amount:    widget.amount,
          currency:  widget.currency,
        ),
      ),
    );
  }

  /// Angular sent PAYGATE_CANCELLED (or cancel URL detected).
  /// User manually cancelled — no webhook is coming, go straight to failed.
  void _goToFailed() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentFailedScreen(
          planLabel: widget.planLabel,
          amount:    widget.amount,
          currency:  widget.currency,
          selectedLanguage: '',
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Leave Payment?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'If you\'ve already confirmed the payment on your phone, '
              'your payment is being processed and you\'ll see the result shortly.\n\n'
              'If you haven\'t confirmed yet, the payment will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Stay',
              style: TextStyle(color: fleetraOrange),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              _goToPending();         // go to pending screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fleetraOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showExitConfirmation();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Stack(
                  children: [
                    if (!_hasError) WebViewWidget(controller: _controller),
                    if (_hasError) _buildErrorState(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: _showExitConfirmation,
            icon: const Icon(Icons.close_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Payment',
                  style: AppTypography.h3.copyWith(fontSize: 18),
                ),
                Text(
                  widget.planLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Secure',
                  style: AppTypography.caption.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppColors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: fleetraOrange),
            const SizedBox(height: 16),
            Text(
              'Loading payment page...',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😕', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Failed to load payment page',
              style: AppTypography.subtitle1.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your internet connection and try again.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasError  = false;
                  _isLoading = true;
                });
                _controller.loadRequest(Uri.parse(_resolvedUrl));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: fleetraOrange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}