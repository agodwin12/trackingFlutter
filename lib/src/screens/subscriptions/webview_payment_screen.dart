// lib/src/screens/subscriptions/webview_payment_screen.dart
import 'dart:async';
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
  bool _handled   = false;
  late final String _resolvedUrl;

  // The PayGate domain — any navigation AWAY from this domain means
  // PayGate has finished and is redirecting to success/cancel URL.
  static const List<String> _paygateDomains = [
    'paygate.staging.proxymgroup.com',
    'paygate.proxymgroup.com',
    'checkout.paygate',
  ];

  @override
  void initState() {
    super.initState();
    _resolvedUrl = _extractValidUrl(widget.redirectUrl);
    debugPrint('🌐 [WEBVIEW] Resolved URL: $_resolvedUrl');
    _initWebView();
  }

  String _extractValidUrl(String raw) {
    if (!raw.contains(',')) return raw.trim();
    final parts = raw.split(',').map((u) => u.trim()).toList();
    final httpsUrl = parts.firstWhere(
          (u) => u.startsWith('https://'),
      orElse: () => '',
    );
    if (httpsUrl.isNotEmpty) return httpsUrl;
    for (final part in parts) {
      try { Uri.parse(part); return part; } catch (_) {}
    }
    return parts.first;
  }

  /// Returns true if the URL belongs to the PayGate payment flow.
  /// Any URL outside PayGate domains = PayGate has finished redirecting.
  bool _isPaygateDomain(String url) {
    try {
      final host = Uri.parse(url).host;
      return _paygateDomains.any((d) => host.contains(d));
    } catch (_) {
      return false;
    }
  }

  bool _isExternalRedirect(String url) {
    // Ignore blank, about:blank, and the initial load URL
    if (url.isEmpty || url == 'about:blank') return false;
    if (url == _resolvedUrl) return false;
    // If it's no longer on a PayGate domain → PayGate redirected out
    return !_isPaygateDomain(url);
  }

  /// Treat as cancel if the URL explicitly says cancel/fail,
  /// otherwise treat as success (payment confirmed).
  bool _isCancelUrl(String url) =>
      url.contains('/payments/cancel') ||
          url.contains('payment_cancel')   ||
          url.contains('status=cancel')    ||
          url.contains('status=failed')    ||
          url.contains('cancelled=true');

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)

    // ── JS Bridge ────────────────────────────────────────────────────────
      ..addJavaScriptChannel(
        'FlutterWebView',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('📩 [WEBVIEW] JS Bridge: ${message.message}');
          if (_handled) return;
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final type = data['type'] as String? ?? '';
            if (type == 'PAYGATE_SUCCESS') {
              debugPrint('✅ [WEBVIEW] Bridge: SUCCESS → pending');
              _navigate(toPending: true);
            } else if (type == 'PAYGATE_CANCELLED') {
              debugPrint('❌ [WEBVIEW] Bridge: CANCELLED → failed');
              _navigate(toPending: false);
            }
          } catch (e) {
            debugPrint('❌ [WEBVIEW] Bridge decode error: $e');
          }
        },
      )

      ..setNavigationDelegate(
        NavigationDelegate(

          // ── Primary intercept ────────────────────────────────────────────
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            debugPrint('🔀 [WEBVIEW] Nav request: $url');

            if (!_handled && _isExternalRedirect(url)) {
              if (_isCancelUrl(url)) {
                debugPrint('❌ [WEBVIEW] External redirect: cancel → failed | URL: $url');
                _navigate(toPending: false);
              } else {
                debugPrint('✅ [WEBVIEW] External redirect: success → pending | URL: $url');
                _navigate(toPending: true);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },

          onPageStarted: (url) {
            debugPrint('🌐 [WEBVIEW] Page started: $url');
            if (mounted) setState(() { _isLoading = true; _hasError = false; });

            // Backup intercept — catches POST redirects
            if (!_handled && _isExternalRedirect(url)) {
              if (_isCancelUrl(url)) {
                debugPrint('❌ [WEBVIEW] Page started: cancel → failed | URL: $url');
                _navigate(toPending: false);
              } else {
                debugPrint('✅ [WEBVIEW] Page started: success → pending | URL: $url');
                _navigate(toPending: true);
              }
            }
          },

          onPageFinished: (url) {
            debugPrint('🌐 [WEBVIEW] Page finished: $url');
            if (mounted) setState(() => _isLoading = false);

            // Final safety net
            if (!_handled && _isExternalRedirect(url)) {
              if (_isCancelUrl(url)) {
                debugPrint('❌ [WEBVIEW] Page finished: cancel → failed | URL: $url');
                _navigate(toPending: false);
              } else {
                debugPrint('✅ [WEBVIEW] Page finished: success → pending | URL: $url');
                _navigate(toPending: true);
              }
            }
          },

          onWebResourceError: (error) {
            debugPrint('❌ [WEBVIEW] Resource error '
                '[mainFrame=${error.isForMainFrame}]: ${error.description}');
            if (error.isForMainFrame == true && mounted && !_handled) {
              setState(() { _isLoading = false; _hasError = true; });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_resolvedUrl));
  }

  // ── Single navigation entry point ─────────────────────────────────────────
  void _navigate({required bool toPending}) {
    if (_handled) return;
    _handled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => toPending
              ? PaymentPendingScreen(
            paymentId: widget.paymentId,
            planLabel: widget.planLabel,
            amount:    widget.amount,
            currency:  widget.currency,
          )
              : PaymentFailedScreen(
            planLabel:        widget.planLabel,
            amount:           widget.amount,
            currency:         widget.currency,
            selectedLanguage: '',
          ),
        ),
      );
    });
  }

  // ── Exit dialog ───────────────────────────────────────────────────────────
  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Payment?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          'If you\'ve already confirmed the payment on your phone, '
              'your payment is being processed and you\'ll see the result shortly.\n\n'
              'If you haven\'t confirmed yet, the payment will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay', style: TextStyle(color: fleetraOrange)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigate(toPending: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: fleetraOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Leave',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
                    if (_hasError)  _buildErrorState(),
                    if (_isLoading && !_hasError) _buildLoadingOverlay(),
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
                Text('Secure Payment',
                    style: AppTypography.h3.copyWith(fontSize: 18)),
                Text(widget.planLabel,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textSecondary)),
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
                Text('Secure',
                    style: AppTypography.caption.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w700)),
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
            Text('Loading payment page...',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary)),
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
            Text('Failed to load payment page',
                style: AppTypography.subtitle1.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Please check your internet connection and try again.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() { _hasError = false; _isLoading = true; });
                _controller.loadRequest(Uri.parse(_resolvedUrl));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: fleetraOrange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Try Again',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}