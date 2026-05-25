// lib/src/screens/recouvrement/history/recouvrement_history.dart
import 'dart:convert';
import 'package:FLEETRA/src/screens/recouvrement/history/recouvrement_history_model.dart' hide Lease;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../dashboard/recouvremenet_model.dart';
import 'package:FLEETRA/l10n/app_localizations.dart';
import '../../../services/token_refresh_service.dart';

// ── Colours ────────────────────────────────────────────────────────────────────
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
const Color _purple      = Color(0xFF8B5CF6);

enum _DayStatus { paid, partial, unpaid }

class _CalDay {
  final Lease      lease;
  final _DayStatus status;
  final Payment?   payment;
  const _CalDay({required this.lease, required this.status, this.payment});
}

// ══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class LeaseHistoryScreen extends StatefulWidget {
  final String        accessToken;
  final List<Lease>   leases;
  final bool          embedded;
  final VoidCallback? onPayLease;

  const LeaseHistoryScreen({
    Key? key,
    required this.accessToken,
    required this.leases,
    this.embedded  = false,
    this.onPayLease,
  }) : super(key: key);

  @override
  State<LeaseHistoryScreen> createState() => _LeaseHistoryScreenState();
}

class _LeaseHistoryScreenState extends State<LeaseHistoryScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;
  late DateTime      _focusedMonth;
  DateTime?          _selectedDay;
  late List<Lease>   _leases;

  Map<int, Payment> _paiementMap      = {};
  bool              _loadingPaiements = true;

  final Set<int> _expandedIds = {};

  final _tokenService = TokenRefreshService();
  static const String _apiBase = 'https://recouvrement.proxymgroup.com/api/v1';

  @override
  void initState() {
    super.initState();
    _tabCtrl      = TabController(length: 2, vsync: this);
    _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _leases       = List<Lease>.from(widget.leases);
    _fetchPaiements();
  }

  @override
  void didUpdateWidget(LeaseHistoryScreen old) {
    super.didUpdateWidget(old);
    if (widget.leases != old.leases) {
      setState(() => _leases = List<Lease>.from(widget.leases));
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPaiements() async {
    setState(() => _loadingPaiements = true);
    try {
      final res = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.get(
          Uri.parse('$_apiBase/paiements/'),
          headers: {
            'Authorization':              'Bearer $token',
            'Content-Type':               'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        ).timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final raw  = jsonDecode(res.body);
        final list = raw is Map ? (raw['results'] as List? ?? []) : raw as List;
        final map  = <int, Payment>{};
        for (final item in list) {
          final p = Payment.fromJson(item as Map<String, dynamic>);
          if (!p.isValid) continue;
          if (!map.containsKey(p.leaseId) ||
              p.createdAt.isAfter(map[p.leaseId]!.createdAt)) {
            map[p.leaseId] = p;
          }
        }
        if (mounted) setState(() => _paiementMap = map);
      }
    } catch (_) {
      // non-fatal
    } finally {
      if (mounted) setState(() => _loadingPaiements = false);
    }
  }

  _DayStatus _leaseStatus(Lease l) {
    if (l.isPaid)    return _DayStatus.paid;
    if (l.isPartial) return _DayStatus.partial;
    return _DayStatus.unpaid;
  }

  Map<String, _CalDay> get _calMap {
    final map = <String, _CalDay>{};
    for (final l in _leases) {
      if (l.dateEcheance.isEmpty) continue;
      map[l.dateEcheance] = _CalDay(
        lease:   l,
        status:  _leaseStatus(l),
        payment: _paiementMap[l.id],
      );
    }
    return map;
  }

  int    get _paidCount    => _leases.where((l) => l.isPaid).length;
  int    get _partialCount => _leases.where((l) => l.isPartial).length;
  int    get _unpaidCount  => _leases.where((l) => l.isUnpaid).length;
  double get _totalPaid    => _leases.fold(0.0, (s, l) => s + l.montantPaye);

  Lease? get _nextUnpaid {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final list  = _leases
        .where((l) => (l.isUnpaid || l.isPartial) &&
        l.dateEcheance.compareTo(today) >= 0)
        .toList()
      ..sort((a, b) => a.dateEcheance.compareTo(b.dateEcheance));
    return list.isEmpty ? null : list.first;
  }

  String _fmt(double v) => v.toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Color _statusColor(_DayStatus s) {
    switch (s) {
      case _DayStatus.paid:    return _green;
      case _DayStatus.partial: return _yellow;
      case _DayStatus.unpaid:  return _red;
    }
  }

  String _statusLabel(_DayStatus s, AppLocalizations t) {
    switch (s) {
      case _DayStatus.paid:    return t.statusPaid;
      case _DayStatus.partial: return t.statusPartial;
      case _DayStatus.unpaid:  return t.statusUnpaid;
    }
  }

  List<String> _months(AppLocalizations t) {
    final fr = Localizations.localeOf(context).languageCode == 'fr';
    return fr
        ? ['','Janvier','Février','Mars','Avril','Mai','Juin',
      'Juillet','Août','Septembre','Octobre','Novembre','Décembre']
        : ['','January','February','March','April','May','June',
      'July','August','September','October','November','December'];
  }

  List<String> _monthsShort(AppLocalizations t) {
    final fr = Localizations.localeOf(context).languageCode == 'fr';
    return fr
        ? ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc']
        : ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  }

  List<String> _weekdays(AppLocalizations t) {
    final fr = Localizations.localeOf(context).languageCode == 'fr';
    return fr
        ? ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim']
        : ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ← THE FIX: ! unwraps the nullable return of AppLocalizations.of()
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        if (!widget.embedded) _buildTopBar(t),
        _buildTabBar(t),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildCalendarTab(t),
            _buildListTab(t),
          ],
        )),
      ])),
    );
  }

  Widget _buildTopBar(AppLocalizations t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: const BoxDecoration(
      color: _bgSubtle,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textMuted, size: 16),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.historyTitle, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
        Text(t.historySubtitle,
            style: const TextStyle(fontSize: 11, color: _textMuted)),
      ])),
    ]),
  );

  Widget _buildTabBar(AppLocalizations t) => Container(
    color: _bgSubtle,
    child: TabBar(
      controller:           _tabCtrl,
      indicatorColor:       _orange,
      indicatorWeight:      2.5,
      labelColor:           _orange,
      unselectedLabelColor: _textMuted,
      labelStyle:           const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      tabs: [Tab(text: t.tabCalendar), Tab(text: t.tabRecords)],
    ),
  );

  // ══ TAB 1 — CALENDAR ══════════════════════════════════════════════════════
  Widget _buildCalendarTab(AppLocalizations t) {
    final calMap = _calMap;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(children: [
        _buildStatsRow(t),
        const SizedBox(height: 14),
        _buildNextPayCard(t),
        const SizedBox(height: 14),
        _buildCalendar(calMap, t),
        const SizedBox(height: 12),
        _buildLegend(t),
        if (_selectedDay != null) ...[
          const SizedBox(height: 14),
          _buildDayDetail(calMap, t),
        ],
      ]),
    );
  }

  Widget _buildStatsRow(AppLocalizations t) => Row(children: [
    Expanded(child: _statChip(Icons.check_circle_outline_rounded,
        t.statDaysPaid, '$_paidCount', _green)),
    const SizedBox(width: 8),
    Expanded(child: _statChip(Icons.timelapse_rounded,
        t.statusPartial, '$_partialCount', _yellow)),
    const SizedBox(width: 8),
    Expanded(child: _statChip(Icons.cancel_outlined,
        t.statMissed, '$_unpaidCount', _red)),
  ]);

  Widget _statChip(IconData icon, String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: _textMuted)),
        ]),
      );

  Widget _buildNextPayCard(AppLocalizations t) {
    final next = _nextUnpaid;
    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _green.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _green.withOpacity(0.3))),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: _green, size: 22),
          const SizedBox(width: 14),
          Text(t.allUpToDate, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: _green)),
        ]),
      );
    }
    final ms    = _monthsShort(t);
    final wdays = _weekdays(t);
    final dt    = DateTime.tryParse(next.dateEcheance);
    final label = dt != null
        ? '${wdays[dt.weekday-1]}, ${ms[dt.month]} ${dt.day}, ${dt.year}'
        : next.dateEcheance;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_orange.withOpacity(0.18), _orange.withOpacity(0.05)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withOpacity(0.35)),
      ),
      child: Row(children: [
        Container(width: 42, height: 42,
            decoration: BoxDecoration(color: _orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.event_rounded, color: _orange, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.nextPaymentDue,
              style: const TextStyle(fontSize: 11, color: _textMuted)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(t.amount,
              style: const TextStyle(fontSize: 10, color: _textMuted)),
          const SizedBox(height: 2),
          Text('XAF ${_fmt(next.resteAPayer)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: _orange)),
        ]),
      ]),
    );
  }

  Widget _buildCalendar(Map<String, _CalDay> calMap, AppLocalizations t) {
    return Container(
      decoration: BoxDecoration(color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Column(children: [
        _buildCalHeader(t),
        const Divider(height: 1, color: _border),
        _buildWeekdayRow(t),
        const Divider(height: 1, color: _border),
        _buildDaysGrid(calMap, t),
      ]),
    );
  }

  Widget _buildCalHeader(AppLocalizations t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _navBtn(Icons.chevron_left_rounded, () => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1))),
      Text('${_months(t)[_focusedMonth.month]} ${_focusedMonth.year}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: _textPrimary)),
      _navBtn(Icons.chevron_right_rounded, () => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1))),
    ]),
  );

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: _bgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border)),
      child: Icon(icon, color: _textMuted, size: 20),
    ),
  );

  Widget _buildWeekdayRow(AppLocalizations t) {
    final wdays = _weekdays(t);
    final fr    = Localizations.localeOf(context).languageCode == 'fr';
    final sun   = fr ? 'Dim' : 'Sun';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: wdays.map((d) => Expanded(
        child: Center(child: Text(d, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3,
          color: d == sun ? _red.withOpacity(0.7) : _textMuted,
        ))),
      )).toList()),
    );
  }

  Widget _buildDaysGrid(Map<String, _CalDay> calMap, AppLocalizations t) {
    final first       = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final offset      = (first.weekday - 1) % 7;
    final todayKey    = _dateKey(DateTime.now());
    final cells       = <Widget>[];

    for (int i = 0; i < offset; i++) cells.add(const SizedBox());

    for (int d = 1; d <= daysInMonth; d++) {
      final date       = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      final key        = _dateKey(date);
      final calDay     = calMap[key];
      final isToday    = key == todayKey;
      final isSelected = _selectedDay != null && _dateKey(_selectedDay!) == key;

      cells.add(_buildDayCell(
        day:        d,
        calDay:     calDay,
        isToday:    isToday,
        isSelected: isSelected,
        onTap: calDay != null
            ? () => setState(() => _selectedDay = isSelected ? null : date)
            : null,
      ));
    }
    while (cells.length % 7 != 0) cells.add(const SizedBox());

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: GridView.count(
        crossAxisCount: 7, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4,
        children: cells,
      ),
    );
  }

  Widget _buildDayCell({
    required int      day,
    required _CalDay? calDay,
    required bool     isToday,
    required bool     isSelected,
    VoidCallback?     onTap,
  }) {
    Color bg, textColor;
    Color? borderColor;

    if (calDay != null) {
      final c = _statusColor(calDay.status);
      bg          = c.withOpacity(isSelected ? 0.35 : 0.18);
      textColor   = c;
      borderColor = isSelected ? c : c.withOpacity(0.4);
    } else {
      bg          = Colors.transparent;
      textColor   = _textMuted.withOpacity(0.4);
      borderColor = null;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isToday && calDay == null ? _orange.withOpacity(0.08) : bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday ? _orange : (borderColor ?? Colors.transparent),
            width: isToday || isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Center(child: Text('$day', style: TextStyle(
          fontSize: 12,
          fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isToday ? _orange : textColor,
        ))),
      ),
    );
  }

  Widget _buildLegend(AppLocalizations t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _legendDot(_green,  t.legendPaid),
      _legendDot(_yellow, t.legendPartial),
      _legendDot(_red,    t.legendUnpaid),
      _legendDot(_orange, t.legendToday),
    ]),
  );

  Widget _legendDot(Color color, String label) => Row(children: [
    Container(width: 9, height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 9, color: _textMuted)),
  ]);

  Widget _buildDayDetail(Map<String, _CalDay> calMap, AppLocalizations t) {
    final d      = _selectedDay!;
    final key    = _dateKey(d);
    final calDay = calMap[key];
    if (calDay == null) return const SizedBox();

    final lease   = calDay.lease;
    final payment = calDay.payment;
    final color   = _statusColor(calDay.status);
    final label   = _statusLabel(calDay.status, t);
    final ms      = _monthsShort(t);
    final wdays   = _weekdays(t);
    final dayStr  = '${wdays[d.weekday-1]}, ${ms[d.month]} ${d.day}, ${d.year}';
    final canPay  = calDay.status != _DayStatus.paid;

    final IconData icon = calDay.status == _DayStatus.paid
        ? Icons.check_circle_rounded
        : calDay.status == _DayStatus.partial
        ? Icons.pending_rounded
        : Icons.cancel_rounded;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08),
            blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header row ──────────────────────────────────────────────────────
        Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dayStr, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: _textPrimary)),
            const SizedBox(height: 2),
            Text('Contrat #${lease.contratId}',
                style: const TextStyle(fontSize: 11, color: _textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),

        const SizedBox(height: 16),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 14),

        // ── Financials ──────────────────────────────────────────────────────
        _detailRow(t.detailExpected, 'XAF ${_fmt(lease.montantAttendu)}'),
        const SizedBox(height: 8),
        _detailRow(t.detailPaid, 'XAF ${_fmt(lease.montantPaye)}',
            valueColor: _green),
        const SizedBox(height: 8),
        _detailRow(t.detailRemaining, 'XAF ${_fmt(lease.resteAPayer)}',
            valueColor: lease.resteAPayer > 0 ? _red : _green),

        if (calDay.status == _DayStatus.partial) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: lease.montantAttendu > 0
                  ? (lease.montantPaye / lease.montantAttendu).clamp(0.0, 1.0) : 0,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(_yellow),
              minHeight: 6,
            ),
          ),
        ],

        // ── Payment details (inlined, no second card) ────────────────────────
        if (payment != null) ...[
          const SizedBox(height: 16),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _sectionLabel('PAIEMENT'),
            _methodBadge(payment.methode),
          ]),
          const SizedBox(height: 10),
          _detailRow('Référence', payment.reference),
          const SizedBox(height: 7),
          _detailRow('Montant payé', 'XAF ${_fmt(payment.montant)}',
              valueColor: _green),
          const SizedBox(height: 7),
          _detailRow('Date & heure', '${payment.formattedDate}  ·  ${payment.formattedTime}'),
          if (payment.methode == 'MOBILE' && payment.sessionTelephone != null) ...[
            const SizedBox(height: 7),
            _detailRow('Téléphone', payment.sessionTelephone!),
          ],
          if (payment.enregistrePar != null && payment.enregistrePar!.isNotEmpty) ...[
            const SizedBox(height: 7),
            _detailRow('Enregistré par', payment.enregistrePar!),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, color: _green, size: 12),
              const SizedBox(width: 4),
              const Text('VALIDÉ', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
            ]),
          ),
        ],

        // ── Pay button ──────────────────────────────────────────────────────
        if (canPay) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton.icon(
              onPressed: () => widget.onPayLease?.call(),
              icon: const Icon(Icons.payment_rounded, size: 18),
              label: Text(t.payNowAmount(_fmt(lease.resteAPayer)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _paymentDetailCard(Payment p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgSubtle, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.reference,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: _textPrimary),
              overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _methodBadge(p.methode),
        ]),
        const SizedBox(height: 12),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 10),
        _detailRow('Montant payé', 'XAF ${_fmt(p.montant)}', valueColor: _green),
        const SizedBox(height: 7),
        _detailRow('Date', p.formattedDate),
        const SizedBox(height: 7),
        _detailRow('Heure', p.formattedTime),
        const SizedBox(height: 7),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Enregistré le',
              style: TextStyle(fontSize: 12, color: _textMuted)),
          Flexible(
            child: Text(p.formattedDateTime,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: _textPrimary),
                textAlign: TextAlign.end),
          ),
        ]),
        if (p.methode == 'MOBILE' && p.sessionTelephone != null) ...[
          const SizedBox(height: 7),
          _detailRow('Téléphone', p.sessionTelephone!),
        ],
        if (p.enregistrePar != null && p.enregistrePar!.isNotEmpty) ...[
          const SizedBox(height: 7),
          _detailRow('Enregistré par', p.enregistrePar!),
        ],
        const SizedBox(height: 10),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded, color: _green, size: 12),
            const SizedBox(width: 4),
            const Text('VALIDÉ', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
          ]),
        ),
      ]),
    );
  }

  Widget _methodBadge(String methode) {
    final isMobile = methode == 'MOBILE';
    final color    = isMobile ? _purple : _orange;
    final icon     = isMobile ? Icons.phone_android_rounded : Icons.payments_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 4),
        Text(methode, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(
      fontSize: 9, fontWeight: FontWeight.w700,
      color: _textMuted, letterSpacing: 1.5));

  Widget _detailRow(String label, String value, {Color? valueColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Flexible(child: Text(value, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: valueColor ?? _textPrimary),
          textAlign: TextAlign.end)),
    ],
  );

  // ══ TAB 2 — RECORDS LIST ══════════════════════════════════════════════════
  Widget _buildListTab(AppLocalizations t) {
    if (_loadingPaiements && _paiementMap.isEmpty) {
      return const Center(child: CircularProgressIndicator(
          color: _orange, strokeWidth: 2.5));
    }
    if (_leases.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.receipt_long_rounded, color: _textMuted, size: 48),
        const SizedBox(height: 12),
        Text(t.noRecordsYet,
            style: const TextStyle(color: _textMuted, fontSize: 14)),
      ]));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _buildListSummary(t),
        const SizedBox(height: 16),
        Text(t.allRecords, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _textMuted, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        ..._leases.map((l) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildRecordRow(l, t),
        )),
      ],
    );
  }

  Widget _buildListSummary(AppLocalizations t) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border)),
    child: Row(children: [
      Expanded(child: _summaryCol(t.summaryPaid,    '$_paidCount',    _green)),
      _vDivider(),
      Expanded(child: _summaryCol(t.summaryPartial, '$_partialCount', _yellow)),
      _vDivider(),
      Expanded(child: _summaryCol(t.summaryUnpaid,  '$_unpaidCount',  _red)),
      _vDivider(),
      Expanded(child: _summaryCol(
          t.statTotalPaidShort, 'XAF ${_fmt(_totalPaid)}', _orange, small: true)),
    ]),
  );

  Widget _summaryCol(String label, String value, Color color,
      {bool small = false}) =>
      Column(children: [
        Text(value, style: TextStyle(
            fontSize: small ? 11 : 18,
            fontWeight: FontWeight.w900, color: color),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _textMuted)),
      ]);

  Widget _vDivider() => Container(width: 1, height: 36, color: _border);

  Widget _buildRecordRow(Lease lease, AppLocalizations t) {
    final status   = _leaseStatus(lease);
    final color    = _statusColor(status);
    final label    = _statusLabel(status, t);
    final payment  = _paiementMap[lease.id];
    final canPay   = status != _DayStatus.paid;
    final expanded = _expandedIds.contains(lease.id);

    return GestureDetector(
      onTap: () => setState(() {
        if (expanded) _expandedIds.remove(lease.id);
        else           _expandedIds.add(lease.id);
      }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: expanded ? color.withOpacity(0.4) : _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42,
                decoration: BoxDecoration(color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                    status == _DayStatus.paid
                        ? Icons.check_rounded
                        : Icons.receipt_long_rounded,
                    color: color, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.contrat(lease.contratId),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: _textPrimary)),
              const SizedBox(height: 2),
              Text(lease.dateEcheance,
                  style: const TextStyle(fontSize: 12, color: _textMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('XAF ${_fmt(lease.montantAttendu)}',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: _textPrimary)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
          ]),
          if (!expanded) ...[
            const SizedBox(height: 8),
            if (status == _DayStatus.paid && payment != null)
              Row(children: [
                const Icon(Icons.access_time_rounded, color: _green, size: 12),
                const SizedBox(width: 5),
                Expanded(child: Text(
                  '${payment.formattedDateTime}  ·  ${payment.methode}',
                  style: const TextStyle(
                      fontSize: 11, color: _green, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                )),
                Icon(Icons.expand_more_rounded,
                    color: _textMuted.withOpacity(0.5), size: 16),
              ]),
            if (canPay)
              Row(children: [
                Text('${t.detailRemaining}: XAF ${_fmt(lease.resteAPayer)}',
                    style: TextStyle(fontSize: 11,
                        color: status == _DayStatus.partial ? _yellow : _red,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.expand_more_rounded,
                    color: _textMuted.withOpacity(0.5), size: 16),
              ]),
          ],
          if (expanded) ...[
            const SizedBox(height: 14),
            const Divider(color: _border, height: 1),
            const SizedBox(height: 12),
            _detailRow(t.detailExpected, 'XAF ${_fmt(lease.montantAttendu)}'),
            const SizedBox(height: 6),
            _detailRow(t.detailPaid, 'XAF ${_fmt(lease.montantPaye)}',
                valueColor: _green),
            const SizedBox(height: 6),
            _detailRow(t.detailRemaining, 'XAF ${_fmt(lease.resteAPayer)}',
                valueColor: lease.resteAPayer > 0 ? _red : _green),
            if (status == _DayStatus.partial) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: lease.montantAttendu > 0
                      ? (lease.montantPaye / lease.montantAttendu).clamp(0.0, 1.0)
                      : 0,
                  backgroundColor: _border,
                  valueColor: const AlwaysStoppedAnimation<Color>(_yellow),
                  minHeight: 4,
                ),
              ),
            ],
            if (payment != null) ...[
              const SizedBox(height: 14),
              _sectionLabel('DÉTAILS DU PAIEMENT'),
              const SizedBox(height: 8),
              _paymentDetailCard(payment),
            ],
            if (canPay) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity, height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => widget.onPayLease?.call(),
                  icon: const Icon(Icons.payment_rounded, size: 17),
                  label: Text(t.payNowAmount(_fmt(lease.resteAPayer)),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}