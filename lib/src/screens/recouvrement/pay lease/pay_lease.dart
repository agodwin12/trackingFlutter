// lib/src/screens/recouvrement/pay lease/pay_lease.dart
import 'dart:convert';
import 'dart:async';
import 'package:FLEETRA/src/screens/recouvrement/pay%20lease/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../../../services/env_config.dart';
import '../../../services/token_refresh_service.dart';
import '../dashboard/recouvremenet_model.dart';
import 'package:FLEETRA/l10n/app_localizations.dart';

// ── Colours ───────────────────────────────────────────────────────────────────
const Color _bg          = Color(0xFF0D1117);
const Color _bgSubtle    = Color(0xFF161B22);
const Color _card        = Color(0xFF1C2333);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);
const Color _textPrimary = Color(0xFFE6EDF3);
const Color _green       = Color(0xFF16A34A);
const Color _red         = Color(0xFFDC2626);
const Color _yellow      = Color(0xFFD97706);
const Color _mtnYellow   = Color(0xFFFFCC00);
const Color _orangeTel   = Color(0xFFFF6600);

// ── icon per contract type ────────────────────────────────────────────────────
IconData _typeIcon(String libelle) {
  switch (libelle.toLowerCase()) {
    case 'moto':       return Icons.two_wheeler_rounded;
    case 'téléphone':
    case 'telephone':  return Icons.phone_android_rounded;
    case 'parapluie':  return Icons.umbrella_rounded;
    case 'voiture':    return Icons.directions_car_rounded;
    default:           return Icons.receipt_long_rounded;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 1 — Lease selection + provider + payment initiation
// ══════════════════════════════════════════════════════════════════════════════
class PayLeaseScreen extends StatefulWidget {
  final String      accessToken;
  final List<Lease> allLeases;
  final String      userPhone;
  final int?        preSelectedLeaseId;

  const PayLeaseScreen({
    Key? key,
    required this.accessToken,
    required this.allLeases,
    required this.userPhone,
    this.preSelectedLeaseId,
  }) : super(key: key);

  @override
  State<PayLeaseScreen> createState() => _PayLeaseScreenState();
}

class _PayLeaseScreenState extends State<PayLeaseScreen> {

  final Set<int>    _selectedIds    = {};
  String?           _selectedProvider;
  bool              _processing     = false;
  String?           _error;

  /// null = all types shown
  String?           _activeFilter;

  /// date groups that are expanded (collapsed by default)
  final Set<String> _expandedDates  = {};

  final _tokenService = TokenRefreshService();
  String get _leaseBaseUrl => EnvConfig.partnerApiUrl;

  // ── lease helpers ─────────────────────────────────────────────────────────
  List<Lease> get _unpaidLeases =>
      widget.allLeases.where((l) => l.isUnpaid || l.isPartial).toList();

  /// Distinct type labels for filter chips
  List<String> get _typeLabels {
    final seen = <String>{};
    final out  = <String>[];
    for (final l in _unpaidLeases) {
      final lbl = l.typeContratLibelle.trim();
      if (lbl.isNotEmpty && seen.add(lbl)) out.add(lbl);
    }
    return out;
  }

  /// Unpaid leases after type filter
  List<Lease> get _filteredLeases => _activeFilter == null
      ? _unpaidLeases
      : _unpaidLeases.where((l) => l.typeContratLibelle == _activeFilter).toList();

  /// Leases grouped by dateEcheance, sorted ascending
  Map<String, List<Lease>> get _grouped {
    final map = <String, List<Lease>>{};
    for (final l in _filteredLeases) {
      map.putIfAbsent(l.dateEcheance, () => []).add(l);
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  List<Lease> get _selectedLeases =>
      _unpaidLeases.where((l) => _selectedIds.contains(l.id)).toList();

  double get _totalSelected =>
      _selectedLeases.fold(0, (s, l) => s + l.resteAPayer);

  bool get _allFilteredSelected =>
      _filteredLeases.isNotEmpty &&
          _filteredLeases.every((l) => _selectedIds.contains(l.id));

  String get _barePhone {
    String p = widget.userPhone.trim().replaceAll(' ', '');
    if (p.startsWith('+237')) return p.substring(4);
    if (p.startsWith('237') && p.length > 9) return p.substring(3);
    return p;
  }

  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  /// Friendly date label: "Aujourd'hui", "Demain", etc.
  String _friendlyDate(String iso) {
    try {
      final d     = DateTime.parse(iso);
      final today = DateTime.now();
      final diff  = DateTime(d.year, d.month, d.day)
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
      const months = ['','Jan','Fév','Mar','Avr','Mai','Jun',
        'Jul','Aoû','Sep','Oct','Nov','Déc'];
      final base = '${d.day} ${months[d.month]} ${d.year}';
      if (diff == 0)  return 'Aujourd\'hui — $base';
      if (diff == -1) return 'Hier — $base';
      if (diff == 1)  return 'Demain — $base';
      if (diff < 0)   return 'Il y a ${-diff}j — $base';
      return 'Dans ${diff}j — $base';
    } catch (_) { return iso; }
  }

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (widget.preSelectedLeaseId != null) {
      // user tapped a specific lease — select only that one
      _selectedIds.add(widget.preSelectedLeaseId!);
    } else {
      // "Pay all" path — select all today's unpaid leases
      for (final l in _unpaidLeases) {
        if (l.dateEcheance == today) _selectedIds.add(l.id);
      }
      // fallback: pre-select first if nothing today
      if (_selectedIds.isEmpty && _unpaidLeases.isNotEmpty) {
        _selectedIds.add(_unpaidLeases.first.id);
      }
    }
    // all groups start collapsed
  }

  // ── payment API ───────────────────────────────────────────────────────────
  Future<void> _initiatePayment(AppLocalizations t) async {
    if (_selectedProvider == null || _selectedLeases.isEmpty) return;
    setState(() { _processing = true; _error = null; });

    try {
      final lignes = _selectedLeases.map((l) => {
        'lease_id': l.id,
        'montant' : l.resteAPayer.toStringAsFixed(0),
      }).toList();

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.post(
          Uri.parse('$_leaseBaseUrl/initier-paiement/'),
          headers: {
            'Authorization'             : 'Bearer $token',
            'Content-Type'              : 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({'lignes': lignes, 'phone_number': _barePhone}),
        ).timeout(const Duration(seconds: 20)),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data     = jsonDecode(response.body) as Map<String, dynamic>;
        final String? url = data['redirect_url'] as String?;
        if (url == null || url.isEmpty) {
          setState(() { _processing = false; _error = 'No payment URL received.'; });
          return;
        }
        setState(() => _processing = false);
        if (!mounted) return;

        final reference    = data['reference_session'] as String? ?? '';
        final providerName = _selectedProvider == 'mtn' ? t.mtnMobileMoney : t.orangeMoney;
        final totalAmount  = _totalSelected;
        final paidLeases   = List<Lease>.from(_selectedLeases);

        await Navigator.push<String>(context, MaterialPageRoute(
          builder: (_) => _PayLeaseWebView(
            redirectUrl: url, selectedLeases: paidLeases, userPhone: widget.userPhone,
            providerName: providerName, totalAmount: totalAmount, reference: reference,
          ),
        ));
        if (!mounted) return;

        final pendingResult = await Navigator.push<String>(context, MaterialPageRoute(
          builder: (_) => PaymentPendingScreen(
            selectedLeases: paidLeases, totalAmount: totalAmount,
            providerName: providerName, reference: reference,
            accessToken: widget.accessToken,
          ),
        ));
        if (!mounted) return;
        if (pendingResult == 'refresh') Navigator.pop(context, 'refresh');

      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final msg  = data?['message'] as String?
            ?? data?['detail'] as String?
            ?? 'Payment failed (${response.statusCode})';
        setState(() { _processing = false; _error = msg; });
      }
    } on TimeoutException {
      setState(() { _processing = false; _error = t.errorRequestTimedOut; });
    } catch (e) {
      setState(() { _processing = false; _error = t.errorConnection(e.toString()); });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        _topBar(t),
        Expanded(child: _unpaidLeases.isEmpty ? _noLeaseState(t) : _paymentFlow(t)),
      ])),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────
  Widget _topBar(AppLocalizations t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: const BoxDecoration(
        color: _bgSubtle, border: Border(bottom: BorderSide(color: _border))),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _textMuted, size: 16)),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.payLeaseTitle, style: const TextStyle(fontSize: 16,
            fontWeight: FontWeight.w700, color: _textPrimary)),
        Text(t.payLeaseSubtitle,
            style: const TextStyle(fontSize: 11, color: _textMuted)),
      ])),
    ]),
  );

  // ── no lease state ────────────────────────────────────────────────────────
  Widget _noLeaseState(AppLocalizations t) => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
            decoration: BoxDecoration(color: _green.withOpacity(0.12),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, color: _green, size: 36)),
        const SizedBox(height: 20),
        Text(t.allCaughtUp, style: const TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: _textPrimary)),
        const SizedBox(height: 8),
        Text(t.noOutstandingLeases, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.5)),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(foregroundColor: _orange,
                side: const BorderSide(color: _orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(t.backToDashboard,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    ),
  );

  // ── main payment flow ─────────────────────────────────────────────────────
  Widget _paymentFlow(AppLocalizations t) {
    final labels  = _typeLabels;
    final grouped = _grouped;

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Filter chips (only when >1 type) ──────────────────────────
            if (labels.length > 1) ...[
              Text('Filtrer par type', style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              _buildFilterChips(labels),
              const SizedBox(height: 20),
            ],

            // ── Section label ─────────────────────────────────────────────
            Text(t.sectionOutstandingLeases, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5)),
            const SizedBox(height: 12),

            // ── Grouped & collapsible lease list ──────────────────────────
            if (grouped.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Aucun paiement pour ce type.',
                      style: const TextStyle(color: _textMuted, fontSize: 13))))
            else
              ...grouped.entries.map((entry) {
                final dateKey    = entry.key;
                final leases     = entry.value;
                final isExpanded = _expandedDates.contains(dateKey);
                final allSel     = leases.every((l) => _selectedIds.contains(l.id));
                final someSel    = leases.any((l)  => _selectedIds.contains(l.id));
                final selCount   = leases
                    .where((l) => _selectedIds.contains(l.id)).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── collapsible date header ──────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: someSel ? _orange.withOpacity(0.06) : _bgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: someSel ? _orange.withOpacity(0.4) : _border,
                          width: someSel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        // ── radio button: tap to select/deselect all in group
                        GestureDetector(
                          onTap: () => setState(() {
                            final ids = leases.map((l) => l.id).toSet();
                            if (allSel) _selectedIds.removeAll(ids);
                            else        _selectedIds.addAll(ids);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: allSel ? _orange : Colors.transparent,
                                border: Border.all(
                                  color: allSel ? _orange
                                      : someSel ? _orange.withOpacity(0.5)
                                      : _textMuted,
                                  width: 2,
                                ),
                              ),
                              child: allSel
                                  ? const Icon(Icons.check,
                                  color: Colors.white, size: 13)
                                  : someSel
                                  ? Center(child: Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: _orange.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  )))
                                  : null,
                            ),
                          ),
                        ),
                        // ── date label + count — tap to expand/collapse
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) _expandedDates.remove(dateKey);
                              else            _expandedDates.add(dateKey);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_friendlyDate(dateKey), style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700,
                                      color: someSel ? _textPrimary : _textMuted)),
                                  const SizedBox(height: 1),
                                  Text(
                                    selCount > 0
                                        ? '$selCount/${leases.length} sélectionné${selCount > 1 ? 's' : ''}'
                                        : '${leases.length} paiement${leases.length > 1 ? 's' : ''}',
                                    style: TextStyle(fontSize: 10,
                                        color: selCount > 0 ? _orange : _textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ── expand/collapse chevron
                        GestureDetector(
                          onTap: () => setState(() {
                            if (isExpanded) _expandedDates.remove(dateKey);
                            else            _expandedDates.add(dateKey);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                            child: AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more_rounded,
                                  color: someSel ? _orange : _textMuted,
                                  size: 22),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    // ── animated lease cards ─────────────────────────────
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 220),
                      crossFadeState: isExpanded
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(children: [
                          ...leases.map((l) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _leaseCheckCard(l, t),
                          )),
                        ]),
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              }),

            const SizedBox(height: 20),

            // ── Summary banner ────────────────────────────────────────────
            if (_selectedIds.isNotEmpty) ...[
              _summaryBanner(t),
              const SizedBox(height: 20),
            ],

            // ── Provider ──────────────────────────────────────────────────

            // ── Provider ──────────────────────────────────────────────────
            Text(t.sectionPaymentMethod, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _providerCard(id: 'mtn',    name: t.mtnMobileMoney,
                tagline: t.mtnTagline, accent: _mtnYellow, fallback: 'MTN',
                fallbackTxt: Colors.black, fallbackBg: _mtnYellow),
            const SizedBox(height: 12),
            _providerCard(id: 'orange', name: t.orangeMoney,
                tagline: t.orangeTagline, accent: _orangeTel, fallback: 'OM',
                fallbackTxt: Colors.white, fallbackBg: _orangeTel),
            const SizedBox(height: 20),

            // ── Info banner ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _textMuted, size: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(t.paygateInfo,
                    style: const TextStyle(fontSize: 12, color: _textMuted,
                        height: 1.4))),
              ]),
            ),

            // ── Error ─────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _red.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: _red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(fontSize: 12, color: _red,
                          height: 1.4))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
          ]),
        ),
      ),
      _stickyPayButton(t),
    ]);
  }

  // ── filter chips ──────────────────────────────────────────────────────────
  Widget _buildFilterChips(List<String> labels) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // "Tous" chip
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _activeFilter = null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _activeFilter == null ? _orange : _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _activeFilter == null ? _orange : _border,
                    width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.apps_rounded, size: 13,
                    color: _activeFilter == null ? Colors.white : _textMuted),
                const SizedBox(width: 5),
                Text('Tous', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _activeFilter == null ? Colors.white : _textMuted)),
              ]),
            ),
          ),
        ),
        // one chip per type label
        ...labels.map((lbl) {
          final active = _activeFilter == lbl;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = active ? null : lbl),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _orange : _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active ? _orange : _border, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_typeIcon(lbl), size: 13,
                      color: active ? Colors.white : _textMuted),
                  const SizedBox(width: 5),
                  Text(lbl, style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : _textMuted)),
                ]),
              ),
            ),
          );
        }),
      ]),
    );
  }

  // ── lease check card ──────────────────────────────────────────────────────
  Widget _leaseCheckCard(Lease lease, AppLocalizations t) {
    final selected    = _selectedIds.contains(lease.id);
    final statusColor = lease.isPartial ? _yellow : _red;
    final statusLabel = lease.isPartial ? t.statusPartial : t.statusUnpaid;
    final typeLbl     = lease.typeContratLibelle.isNotEmpty
        ? lease.typeContratLibelle
        : 'Contrat #${lease.contratId}';

    return GestureDetector(
      onTap: () => setState(() {
        if (selected) _selectedIds.remove(lease.id);
        else          _selectedIds.add(lease.id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _orange.withOpacity(0.06) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? _orange : _border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          // checkbox circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: selected ? _orange : Colors.transparent,
              border: Border.all(
                  color: selected ? _orange : _textMuted, width: 2),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 13)
                : null,
          ),
          const SizedBox(width: 12),
          // type icon
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: selected ? _orange.withOpacity(0.15) : _bgSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_typeIcon(typeLbl), size: 15,
                color: selected ? _orange : _textMuted),
          ),
          const SizedBox(width: 12),
          // type label + date
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(typeLbl, style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w700, color: _textPrimary)),
                const SizedBox(height: 2),
                Text('Échéance ${lease.dateEcheance}',
                    style: const TextStyle(fontSize: 11, color: _textMuted)),
              ])),
          // amount + status badge
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('XAF ${_fmt(lease.resteAPayer)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                    color: _textPrimary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(statusLabel, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── summary banner ────────────────────────────────────────────────────────
  Widget _summaryBanner(AppLocalizations t) {
    final plural = _selectedIds.length > 1 ? 's' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_orange.withOpacity(0.18), _orange.withOpacity(0.06)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _orange.withOpacity(0.35)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.leasesSelected(_selectedIds.length, plural),
              style: const TextStyle(fontSize: 12, color: _textMuted)),
          const SizedBox(height: 4),
          Text(t.totalToPay,
              style: const TextStyle(fontSize: 11, color: _textMuted)),
        ]),
        Text('XAF ${_fmt(_totalSelected)}',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                color: _orange, letterSpacing: -0.5)),
      ]),
    );
  }

  // ── provider card ─────────────────────────────────────────────────────────
  Widget _providerCard({
    required String id, required String name, required String tagline,
    required Color  accent, required String fallback,
    required Color  fallbackTxt, required Color fallbackBg,
  }) {
    final selected = _selectedProvider == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedProvider = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.08) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? accent : _border, width: selected ? 2 : 1),
          boxShadow: selected
              ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 16,
              offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(children: [
          Container(width: 56, height: 56,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                  color: fallbackBg),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/${id}_logo.png', fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(child: Text(fallback,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                          color: fallbackTxt))))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: selected ? accent : _textPrimary)),
                const SizedBox(height: 2),
                Text(tagline,
                    style: const TextStyle(fontSize: 12, color: _textMuted)),
              ])),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: selected ? accent : Colors.transparent,
              border: Border.all(
                  color: selected ? accent : _border, width: 2),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 13)
                : null,
          ),
        ]),
      ),
    );
  }

  // ── sticky pay button ─────────────────────────────────────────────────────
  Widget _stickyPayButton(AppLocalizations t) {
    final enabled  = _selectedProvider != null &&
        _selectedIds.isNotEmpty && !_processing;
    final btnColor = _selectedProvider == 'mtn'    ? _mtnYellow
        : _selectedProvider == 'orange' ? _orangeTel
        : _orange;
    final txtColor = _selectedProvider == 'mtn' ? Colors.black : Colors.white;

    final String label;
    if (_selectedIds.isEmpty) {
      label = t.selectAtLeastOneLease;
    } else if (_selectedProvider == null) {
      label = t.selectPaymentMethod;
    } else {
      final prov = _selectedProvider == 'mtn' ? 'MTN MoMo' : 'Orange Money';
      label = t.payVia(_fmt(_totalSelected), prov);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
          color: _bg, border: Border(top: BorderSide(color: _border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.leasesSelected(_selectedIds.length,
                      _selectedIds.length > 1 ? 's' : ''),
                      style: const TextStyle(fontSize: 12, color: _textMuted)),
                  Text('XAF ${_fmt(_totalSelected)}',
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w800, color: _orange)),
                ]),
          ),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: enabled ? () => _initiatePayment(t) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor, foregroundColor: txtColor,
              disabledBackgroundColor: _card,
              disabledForegroundColor: _textMuted,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _processing
                ? SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(txtColor)))
                : Text(label, style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: txtColor)),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP 2 — In-app WebView (unchanged)
// ══════════════════════════════════════════════════════════════════════════════
class _PayLeaseWebView extends StatefulWidget {
  final String      redirectUrl;
  final List<Lease> selectedLeases;
  final String      userPhone;
  final String      providerName;
  final double      totalAmount;
  final String      reference;

  const _PayLeaseWebView({
    required this.redirectUrl,    required this.selectedLeases,
    required this.userPhone,      required this.providerName,
    required this.totalAmount,    required this.reference,
  });

  @override
  State<_PayLeaseWebView> createState() => _PayLeaseWebViewState();
}

class _PayLeaseWebViewState extends State<_PayLeaseWebView> {
  late final WebViewController _controller;
  bool   _isLoading = true;
  bool   _hasError  = false;
  String _pageTitle = 'PayGate';

  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  @override
  void initState() { super.initState(); _initWebView(); }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted:  (_) => setState(() { _isLoading = true; _hasError = false; }),
        onPageFinished: (url) async {
          setState(() => _isLoading = false);
          final title = await _controller.getTitle();
          if (title != null && title.isNotEmpty && mounted) {
            setState(() => _pageTitle = title);
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true) {
            setState(() { _isLoading = false; _hasError = true; });
          }
        },
      ))
      ..addJavaScriptChannel('FlutterWebView',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final type = data['type'] as String?;
            if (type == 'PAYGATE_SUCCESS' && mounted) {
              Navigator.pop(context, 'success');
            } else if ((type == 'PAYGATE_CANCEL' || type == 'PAYGATE_FAILED')
                && mounted) {
              Navigator.pop(context, 'cancelled');
            }
          } catch (_) {}
        },
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  void _confirmClose(AppLocalizations t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1C2333),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF30363D))),
      title: Text(t.closePaymentTitle,
          style: const TextStyle(color: Color(0xFFE6EDF3),
              fontWeight: FontWeight.w700)),
      content: Text(t.closePaymentMessage,
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.stay, style: const TextStyle(
                color: Color(0xFFF58220), fontWeight: FontWeight.w600))),
        ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, 'cancelled');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0),
            child: Text(t.closeAnyway,
                style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(child: Column(children: [
        // webview top bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: Color(0xFF30363D)))),
          child: Row(children: [
            GestureDetector(
              onTap: () => _confirmClose(t),
              child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFF1C2333),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF30363D))),
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF8B949E), size: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_pageTitle, style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: Color(0xFFE6EDF3)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${widget.providerName} · XAF ${_fmt(widget.totalAmount)}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E))),
                ])),
            Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.lock_rounded,
                    color: Color(0xFF16A34A), size: 14)),
          ]),
        ),
        if (_isLoading)
          const LinearProgressIndicator(
              backgroundColor: Color(0xFF1C2333),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF58220)),
              minHeight: 2),
        Expanded(child: _hasError
            ? _buildError(t)
            : WebViewWidget(controller: _controller)),
      ])),
    );
  }

  Widget _buildError(AppLocalizations t) => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.12),
                shape: BoxShape.circle),
            child: const Icon(Icons.wifi_off_rounded,
                color: Color(0xFFDC2626), size: 32)),
        const SizedBox(height: 16),
        Text(t.failedToLoadPaymentPage,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFFE6EDF3))),
        const SizedBox(height: 8),
        Text(t.checkConnectionRetry, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8B949E),
                height: 1.5)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton(
              onPressed: () => Navigator.pop(context, 'cancelled'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B949E),
                  side: const BorderSide(color: Color(0xFF30363D)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(t.goBack)),
          const SizedBox(width: 12),
          ElevatedButton.icon(
              onPressed: () {
                setState(() { _hasError = false; _isLoading = true; });
                _controller.reload();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(t.retry),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0)),
        ]),
      ]),
    ),
  );
}