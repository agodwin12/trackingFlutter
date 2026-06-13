// lib/src/screens/recouvrement/pay_lease/pay_lease.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../services/env_config.dart';
import '../../../services/token_refresh_service.dart';
import '../dashboard/recouvremenet_model.dart';
import '../pending/pending_scren_recouvremenet.dart';
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
// PayLeaseScreen
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

  final Set<int>    _selectedIds   = {};
  bool              _processing    = false;
  String?           _error;
  String?           _activeFilter;
  final Set<String> _expandedDates = {};

  final TextEditingController _phoneController = TextEditingController();
  bool _phoneError = false;

  final _tokenService = TokenRefreshService();
  String get _leaseBaseUrl => EnvConfig.partnerApiUrl;

  // ── lease helpers ─────────────────────────────────────────────────────────
  List<Lease> get _unpaidLeases =>
      widget.allLeases.where((l) => l.isUnpaid || l.isPartial).toList();

  List<String> get _typeLabels {
    final seen = <String>{};
    final out  = <String>[];
    for (final l in _unpaidLeases) {
      final lbl = l.typeContratLibelle.trim();
      if (lbl.isNotEmpty && seen.add(lbl)) out.add(lbl);
    }
    return out;
  }

  List<Lease> get _filteredLeases => _activeFilter == null
      ? _unpaidLeases
      : _unpaidLeases.where((l) => l.typeContratLibelle == _activeFilter).toList();

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

  String get _typedPhone =>
      _phoneController.text.trim().replaceAll(' ', '');

  bool get _phoneValid =>
      _typedPhone.length == 9 && int.tryParse(_typedPhone) != null;

  String _fmt(double n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

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
      _selectedIds.add(widget.preSelectedLeaseId!);
    } else {
      for (final l in _unpaidLeases) {
        if (l.dateEcheance == today) _selectedIds.add(l.id);
      }
      if (_selectedIds.isEmpty && _unpaidLeases.isNotEmpty) {
        _selectedIds.add(_unpaidLeases.first.id);
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ── payment API ───────────────────────────────────────────────────────────
  Future<void> _initiatePayment(AppLocalizations t) async {
    if (!_phoneValid) {
      setState(() => _phoneError = true);
      return;
    }

    if (_selectedLeases.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
      _phoneError = false;
    });

    try {
      final lignes = _selectedLeases.map((l) {
        return {
          'lease_id': l.id,
          'montant': l.resteAPayer.toStringAsFixed(0),
        };
      }).toList();

      // API doc 3.1 expects the bare 9-digit number — NO 237 prefix.
      final payload = {
        'lignes': lignes,
        'phone_number': _typedPhone,
      };

      debugPrint('PAYMENT INIT URL => $_leaseBaseUrl/initier-paiement/');
      debugPrint('PAYMENT INIT BODY => ${jsonEncode(payload)}');

      final response = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.post(
          Uri.parse('$_leaseBaseUrl/initier-paiement/'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 20)),
      );

      debugPrint('PAYMENT INIT STATUS => ${response.statusCode}');
      debugPrint('PAYMENT INIT RESPONSE => ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Backend returns: reference_interne (MOB.xxxx) + gateway_reference (uuid).
        // We track reference_interne — it is what SSE/statut-paiement key on.
        final reference = (data['reference_interne'] as String?) ??
            (data['gateway_reference'] as String?) ??
            (data['reference'] as String?) ??
            (data['transaction_ref'] as String?) ??
            (data['ref'] as String?) ??
            (data['data']?['reference_interne'] as String?) ??
            (data['data']?['reference'] as String?) ??
            (data['data']?['transaction_ref'] as String?) ??
            (data['data']?['ref'] as String?) ??
            '';

        if (reference.isEmpty) {
          setState(() {
            _processing = false;
            _error = 'Référence de paiement introuvable.';
          });
          return;
        }

        setState(() => _processing = false);

        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, anim, __) => RecouvrementPaymentPendingScreen(
              reference: reference,
              amount: _totalSelected,
              leaseCount: _selectedIds.length,
              phone: _typedPhone,
              accessToken: widget.accessToken,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
      } else {
        String msg = 'Erreur de paiement (${response.statusCode})';

        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          msg = (data['message'] as String?) ??
              (data['detail'] as String?) ??
              (data['error'] as String?) ??
              (data['dev_message'] as String?) ??
              (data['data']?['message'] as String?) ??
              (data['data']?['detail'] as String?) ??
              msg;
        } catch (_) {
          if (response.body.trim().isNotEmpty) {
            msg = response.body;
          }
        }

        setState(() {
          _processing = false;
          _error = msg;
        });
      }
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _processing = false;
        _error = t.errorRequestTimedOut;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processing = false;
        _error = t.errorConnection(e.toString());
      });
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
        Text(t.payLeaseTitle, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
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
        Text(t.allCaughtUp, style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
        const SizedBox(height: 8),
        Text(t.noOutstandingLeases, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.5)),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity, height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(foregroundColor: _orange,
                side: const BorderSide(color: _orange),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
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

            if (labels.length > 1) ...[
              const Text('Filtrer par type', style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: _textMuted,
                  letterSpacing: 1.5)),
              const SizedBox(height: 10),
              _buildFilterChips(labels),
              const SizedBox(height: 20),
            ],

            Text(t.sectionOutstandingLeases, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5)),
            const SizedBox(height: 12),

            if (grouped.isEmpty)
              const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('Aucun paiement pour ce type.',
                      style: TextStyle(color: _textMuted, fontSize: 13))))
            else
              ...grouped.entries.map((entry) {
                final dateKey  = entry.key;
                final leases   = entry.value;
                final isExpanded = _expandedDates.contains(dateKey);
                final allSel   = leases.every((l) => _selectedIds.contains(l.id));
                final someSel  = leases.any((l)  => _selectedIds.contains(l.id));
                final selCount = leases.where((l) => _selectedIds.contains(l.id)).length;

                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  ))) : null,
                            ),
                          ),
                        ),
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

            if (_selectedIds.isNotEmpty) ...[
              _summaryBanner(t),
              const SizedBox(height: 20),
            ],

            const Text('NUMÉRO POUR LE PAIEMENT', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: _textMuted, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            _phoneInputCard(),
            const SizedBox(height: 20),

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

  // ── phone input card ──────────────────────────────────────────────────────
  Widget _phoneInputCard() {
    final hasError = _phoneError && !_phoneValid;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: hasError ? _red.withOpacity(0.06) : _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError
              ? _red.withOpacity(0.5)
              : _phoneValid ? _green.withOpacity(0.5) : _border,
          width: (hasError || _phoneValid) ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: _bgSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Text('🇨🇲', style: TextStyle(fontSize: 16)),
            SizedBox(width: 6),
            Text('+237', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: _textPrimary)),
          ]),
        ),
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 9,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                color: _textPrimary, letterSpacing: 1.2),
            decoration: InputDecoration(
              hintText: '6XX XXX XXX',
              hintStyle: const TextStyle(fontSize: 14, color: _textMuted,
                  fontWeight: FontWeight.w400, letterSpacing: 0.5),
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              suffixIcon: _phoneValid
                  ? const Icon(Icons.check_circle_rounded, color: _green, size: 18)
                  : null,
            ),
            onChanged: (_) {
              if (_phoneError) setState(() => _phoneError = false);
              else setState(() {});
            },
          ),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  // ── filter chips ──────────────────────────────────────────────────────────
  Widget _buildFilterChips(List<String> labels) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
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
                    color: _activeFilter == null ? _orange : _border, width: 1.5),
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
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: selected ? _orange.withOpacity(0.15) : _bgSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_typeIcon(typeLbl), size: 15,
                color: selected ? _orange : _textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(typeLbl, style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w700, color: _textPrimary)),
                const SizedBox(height: 2),
                Text('Échéance ${lease.dateEcheance}',
                    style: const TextStyle(fontSize: 11, color: _textMuted)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('XAF ${_fmt(lease.resteAPayer)}',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: _textPrimary)),
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

  // ── sticky pay button ─────────────────────────────────────────────────────
  Widget _stickyPayButton(AppLocalizations t) {
    final enabled = _selectedIds.isNotEmpty && _phoneValid && !_processing;

    final String label;
    if (_selectedIds.isEmpty) {
      label = t.selectAtLeastOneLease;
    } else if (!_phoneValid) {
      label = 'Entrez votre numéro de paiement';
    } else {
      label = t.payVia(_fmt(_totalSelected), 'Mobile Money');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
          color: _bg, border: Border(top: BorderSide(color: _border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _card,
              disabledForegroundColor: _textMuted,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _processing
                ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white)))
                : Text(label, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}