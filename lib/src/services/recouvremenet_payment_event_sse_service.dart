// lib/src/services/recouvrement_payment_event_sse_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'env_config.dart';

/// A single Server-Sent Event coming from /api/v1/events/.
///
/// Expected wire format (one event):
/// data: {"type":"transaction.completed","data":{"session_id":13,
///        "reference":"MOB.20260611.092443.C090EA","statut":"SUCCESS",
///        "montant":"500.00","message":"..."}}
class PaymentSseEvent {
  final String type;
  final int? sessionId;
  final String? reference; // MOB.xxxx — same as reference_interne
  final String? status; // SUCCESS / FAILED / ...
  final String? amount;
  final String? message;
  final Map<String, dynamic> raw;

  const PaymentSseEvent({
    required this.type,
    required this.raw,
    this.sessionId,
    this.reference,
    this.status,
    this.amount,
    this.message,
  });

  bool get isTransactionCompleted => type == 'transaction.completed';

  bool matchesReference(String ref) =>
      reference != null &&
          reference!.trim().toUpperCase() == ref.trim().toUpperCase();

  bool get isSuccess => status?.toUpperCase() == 'SUCCESS';

  bool get isFailed {
    final s = status?.toUpperCase();
    return s == 'FAILED' ||
        s == 'FAILURE' ||
        s == 'CANCELLED' ||
        s == 'CANCELED' ||
        s == 'ERROR' ||
        s == 'REJECTED';
  }

  factory PaymentSseEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final Map<String, dynamic> payload =
    data is Map<String, dynamic> ? data : <String, dynamic>{};

    return PaymentSseEvent(
      type: (json['type'] ?? '').toString(),
      raw: json,
      sessionId: payload['session_id'] is int
          ? payload['session_id'] as int
          : int.tryParse('${payload['session_id'] ?? ''}'),
      reference: payload['reference']?.toString(),
      status: payload['statut']?.toString() ?? payload['status']?.toString(),
      amount: payload['montant']?.toString() ?? payload['amount']?.toString(),
      message: payload['message']?.toString(),
    );
  }
}

/// Streaming SSE client for payment confirmation.
///
/// Connects to:  {partnerApiUrl}/events/?token={accessToken}
/// where partnerApiUrl already includes /api/v1.
class PaymentEventSseService {
  PaymentEventSseService({
    required this.getAccessToken,
    http.Client? client,
    this.autoReconnect = true,
  }) : _client = client ?? http.Client();

  final Future<String> Function() getAccessToken;
  final bool autoReconnect;
  final http.Client _client;

  StreamSubscription<String>? _lineSubscription;
  StreamController<PaymentSseEvent>? _controller;

  bool _stopped = false;
  bool _connecting = false;
  int _retryAttempt = 0;

  Stream<PaymentSseEvent> connect() {
    if (_controller != null && !_controller!.isClosed) {
      return _controller!.stream;
    }

    _stopped = false;
    _controller = StreamController<PaymentSseEvent>.broadcast(onCancel: stop);

    _connectInternal();

    return _controller!.stream;
  }

  // partnerApiUrl already ends in /api/v1 — strip a trailing slash only.
  // (The previous version appended /api/v1 again, producing a 404.)
  String get _base {
    final url = EnvConfig.partnerApiUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<void> _connectInternal() async {
    if (_stopped || _connecting) return;
    _connecting = true;

    try {
      final token = await getAccessToken();

      final uri = Uri.parse(
        '$_base/events/?token=${Uri.encodeComponent(token)}',
      );

      final request = http.Request('GET', uri)
        ..headers.addAll({
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'ngrok-skip-browser-warning': 'true',
        });

      final response = await _client.send(request);
      _connecting = false;

      if (_stopped) return;

      if (response.statusCode != 200) {
        throw Exception('SSE connection failed: HTTP ${response.statusCode}');
      }

      _retryAttempt = 0;
      String eventBuffer = '';

      _lineSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
          if (_stopped) return;
          final trimmed = line.trim();

          // Blank line = end of one SSE event → flush.
          if (trimmed.isEmpty) {
            _flushEvent(eventBuffer);
            eventBuffer = '';
            return;
          }

          if (trimmed.startsWith('data:')) {
            eventBuffer += trimmed.substring(5).trim();
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  void _flushEvent(String rawData) {
    if (rawData.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) return;

      final event = PaymentSseEvent.fromJson(decoded);
      if (!_stopped && !(_controller?.isClosed ?? true)) {
        _controller?.add(event);
      }
    } catch (_) {
      // Ignore malformed SSE chunks.
    }
  }

  void _scheduleReconnect() {
    if (_stopped || !autoReconnect) return;

    _lineSubscription?.cancel();
    _lineSubscription = null;

    _retryAttempt++;
    final seconds = _retryAttempt <= 1
        ? 1
        : _retryAttempt == 2
        ? 2
        : _retryAttempt == 3
        ? 4
        : 8;

    Future.delayed(Duration(seconds: seconds), () {
      if (!_stopped) _connectInternal();
    });
  }

  Future<void> stop() async {
    _stopped = true;
    await _lineSubscription?.cancel();
    _lineSubscription = null;

    if (!(_controller?.isClosed ?? true)) {
      await _controller?.close();
    }
    _controller = null;
  }

  void dispose() {
    stop();
    _client.close();
  }
}