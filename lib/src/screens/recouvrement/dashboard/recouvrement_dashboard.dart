// lib/src/screens/recouvrement/dashboard/recouvrement_dashboard.dart

import 'dart:async';
import 'dart:convert';

import 'package:FLEETRA/src/screens/recouvrement/dashboard/recouvremenet_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../services/token_refresh_service.dart';
import '../../../widgets/language_toggle.dart';
import '../../login/login.dart';
import '../history/recouvremenet_history.dart';
import '../pay lease/pay_lease.dart';
import '../profile/profile_screen.dart';

// ── palette ───────────────────────────────────────────────────────────────────
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

// ── error types ───────────────────────────────────────────────────────────────
enum _FetchErrorType { network, notFound, server, unknown }

_FetchErrorType _errorTypeFromStatus(int? code) {
  if (code == null) return _FetchErrorType.network;
  if (code == 404)  return _FetchErrorType.notFound;
  if (code >= 500)  return _FetchErrorType.server;
  return _FetchErrorType.unknown;
}

// ── debug helpers ─────────────────────────────────────────────────────────────
const bool _kDebug = true;
void _log(String msg) { if (_kDebug) debugPrint('📊 [RecDashboard] $msg'); }
void _logErr(String msg, Object err, [StackTrace? st]) {
  if (!_kDebug) return;
  debugPrint('❌ [RecDashboard] $msg | err=$err');
  if (st != null) debugPrint('❌ [RecDashboard] $st');
}
String _preview(String s, {int max = 2500}) =>
    s.length <= max ? s : '${s.substring(0, max)}…[+${s.length - max}]';
String _tokenHint(String t) =>
    t.length <= 12 ? '***' : '${t.substring(0, 6)}…${t.substring(t.length - 6)}';
Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}
List<dynamic> _extractList(dynamic raw, String tag) {
  if (raw is List) { _log('$tag → List(${raw.length})'); return raw; }
  if (raw is Map) {
    for (final key in ['results', 'data', 'items']) {
      if (raw[key] is List) {
        _log('$tag → Map[$key](${(raw[key] as List).length})');
        return raw[key] as List;
      }
    }
    if (raw.containsKey('id')) { _log('$tag → single object wrapped'); return [raw]; }
  }
  _log('$tag → could not extract list (${raw.runtimeType})');
  return const [];
}
String _safeStr(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return (s.isEmpty || s.toLowerCase() == 'null') ? fallback : s;
}

/// Robust numeric parsers — same behaviour as the profile screen, so contrats
/// are interpreted identically everywhere. Sequelize serialises DECIMAL/BIGINT
/// as strings, sometimes with spaces or comma decimal separators, which the
/// previous plain `double.tryParse` silently turned into 0.0 (the "paid stays
/// at 0" bug).
double _safeDouble(dynamic v, {double fallback = 0}) {
  if (v == null)   return fallback;
  if (v is double) return v;
  if (v is num)    return v.toDouble();
  final text = v.toString().trim().replaceAll(' ', '').replaceAll(',', '.');
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return double.tryParse(text) ?? fallback;
}

int _safeInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int)  return v;
  if (v is num)  return v.toInt();
  final text = v.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? fallback;
}

// ── env URLs ──────────────────────────────────────────────────────────────────
String get _partnerApiUrl =>
    (dotenv.env['PARTNER_API_URL'] ?? 'https://recouvrement.proxymgroup.com/api/v1')
        .replaceAll(RegExp(r'/$'), '');

String get _baseUrl =>
    (dotenv.env['BASE_URL'] ?? 'http://192.168.1.70:5000/api')
        .replaceAll(RegExp(r'/$'), '');

// ── simple contrat model (for summary totals) ─────────────────────────────────
class _Contrat {
  final int    id;
  final String immatriculation;
  final double montantTotal;
  final double montantRestant;
  final double montantVerse;
  final double montantParPaiement;
  final String typeContratLibelle;
  final String prochaineEcheance;

  const _Contrat({
    required this.id,
    required this.immatriculation,
    required this.montantTotal,
    required this.montantRestant,
    required this.montantVerse,
    required this.montantParPaiement,
    required this.typeContratLibelle,
    required this.prochaineEcheance,
  });

  factory _Contrat.fromJson(Map<String, dynamic> j) => _Contrat(
    id                 : _safeInt(j['id']),
    immatriculation    : _safeStr(j['immatriculation']),
    montantTotal       : _safeDouble(j['montant_total']),
    montantRestant     : _safeDouble(j['montant_restant']),
    montantVerse: _safeDouble(j['montant_paye']),
    montantParPaiement : _safeDouble(j['montant_par_paiement']),
    typeContratLibelle : _safeStr(j['type_contrat_libelle']),
    prochaineEcheance  : _safeStr(j['prochaine_echeance']),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHELL
// ══════════════════════════════════════════════════════════════════════════════
class RecouvrementDashboard extends StatefulWidget {
  final Map<String, dynamic> user;
  final String               accessToken;
  final List<String>         roles;

  const RecouvrementDashboard({
    Key? key,
    required this.user,
    required this.accessToken,
    required this.roles,
  }) : super(key: key);

  @override
  State<RecouvrementDashboard> createState() => _RecouvrementDashboardState();
}

class _RecouvrementDashboardState extends State<RecouvrementDashboard> {
  int _currentIndex = 0;

  List<Lease>    _leases   = [];
  List<_Contrat> _contrats = [];
  String?        _immatriculation;

  bool             _loading     = true;
  _FetchErrorType? _errorType;
  int?             _errorStatus;

  Timer? _midnightTimer;
  final _tokenService = TokenRefreshService();

  @override
  void initState() {
    super.initState();
    _log('initState | token=${_tokenHint(widget.accessToken)}');
    _fetchAll();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now      = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1, minutes: 2));
    _midnightTimer = Timer(midnight.difference(now), () async {
      await _fetchAll();
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _fetchAll() async {
    _log('──── FETCH ALL START ────');
    if (mounted) setState(() { _loading = true; _errorType = null; _errorStatus = null; });
    try {
      await Future.wait([_fetchLeases(), _fetchContrats()]);
      _log('FETCH ALL DONE | leases=${_leases.length} contrats=${_contrats.length} immat=$_immatriculation');
    } catch (e, st) {
      _logErr('fetchAll error', e, st);
      _errorType = _FetchErrorType.unknown;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── leases ────────────────────────────────────────────────────────────────
  Future<void> _fetchLeases() async {
    final uri = Uri.parse('$_partnerApiUrl/leases/');
    _log('GET $uri');
    try {
      final res = await _tokenService.makeAuthenticatedRequest(
        request: (t) => http.get(uri, headers: _kcHeaders(t))
            .timeout(const Duration(seconds: 15)),
      );
      _log('leases ${res.statusCode}');
      if (res.statusCode != 200) {
        _errorStatus = res.statusCode;
        _errorType   = _errorTypeFromStatus(res.statusCode);
        return;
      }
      final list   = _extractList(jsonDecode(res.body), 'leases');
      final parsed = <Lease>[];
      for (final item in list) {
        final m = _asMap(item);
        if (m == null) continue;
        try { parsed.add(Lease.fromJson(m)); } catch (e, st) { _logErr('lease parse', e, st); }
      }
      if (mounted) setState(() => _leases = parsed);
    } on TimeoutException catch (e, st) { _logErr('leases timeout', e, st); _errorType = _FetchErrorType.network; }
    catch (e, st) { _logErr('leases error', e, st); _errorType = _FetchErrorType.network; }
  }

  // ── contrats — for summary totals + immatriculation ───────────────────────
  Future<void> _fetchContrats() async {
    final uri = Uri.parse('$_partnerApiUrl/contrats/');
    _log('GET $uri');
    try {
      final res = await _tokenService.makeAuthenticatedRequest(
        request: (t) => http.get(uri, headers: _kcHeaders(t))
            .timeout(const Duration(seconds: 15)),
      );
      _log('contrats ${res.statusCode}');
      if (res.statusCode != 200) return;
      final list   = _extractList(jsonDecode(res.body), 'contrats');
      final parsed = <_Contrat>[];
      String? immat;
      for (final item in list) {
        final m = _asMap(item);
        if (m == null) continue;
        try {
          final c = _Contrat.fromJson(m);
          _log('contrat[${c.id}] verse=${c.montantVerse} '
              'restant=${c.montantRestant} total=${c.montantTotal} '
              '(raw verse=${m['montant_verse']})');
          parsed.add(c);
          // pick first non-empty immatriculation
          if (immat == null && c.immatriculation.isNotEmpty) immat = c.immatriculation;
        } catch (e, st) { _logErr('contrat parse', e, st); }
      }
      if (mounted) setState(() { _contrats = parsed; _immatriculation = immat; });
    } catch (e, st) { _logErr('contrats error', e, st); }
  }

  Map<String, String> _kcHeaders(String token) => {
    'Authorization'             : 'Bearer $token',
    'Content-Type'              : 'application/json',
    'Accept'                    : 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  Future<void> _refresh() => _fetchAll();

  void _navigateToPayLease({int? preSelectedLeaseId}) async {
    final token = await _tokenService.getValidAccessToken() ?? widget.accessToken;
    if (!mounted) return;
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PayLeaseScreen(
          accessToken: token,
          allLeases  : _leases,
          userPhone  : _safeStr(widget.user['phone']),
          preSelectedLeaseId  : preSelectedLeaseId,
        ),
      ),
    );
    await _refresh();
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const ModernLoginScreen()), (_) => false);
  }

  void _confirmLogout(AppLocalizations t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(t.logoutConfirmTitle,
          style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
      content: Text(t.logoutConfirmMessage, style: const TextStyle(color: _textMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text(t.cancel, style: const TextStyle(color: _textMuted))),
        ElevatedButton(
          onPressed: () { Navigator.pop(context); _logout(); },
          style: ElevatedButton.styleFrom(backgroundColor: _red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text(t.logout, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        _buildTopBar(t),
        Expanded(child: _buildCurrentTab(t)),
      ])),
      bottomNavigationBar: _buildBottomNav(t),
    );
  }

  Widget _buildTopBar(AppLocalizations t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
        color: _bgSubtle, border: Border(bottom: BorderSide(color: _border))),
    child: Row(children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(8)),
          child: const Center(child: Text('R',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)))),
      const SizedBox(width: 8),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(t.recouvrementTitle,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                color: _textPrimary, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
        Text(t.proxymGroup,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
                color: _orange, letterSpacing: 1.5)),
      ])),
      const SizedBox(width: 6),
      const LanguageToggle(),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _refresh),
      const SizedBox(width: 6),
      _iconBtn(Icons.logout_rounded, () => _confirmLogout(t)),
    ]),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: 34, height: 34,
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border)),
        child: Icon(icon, color: _textMuted, size: 17)),
  );

  Widget _buildCurrentTab(AppLocalizations t) {
    if (_loading) return _buildLoader(t);
    switch (_currentIndex) {
      case 0:
        return _HomeTab(
          user           : widget.user,
          roles          : widget.roles,
          leases         : _leases,
          contrats       : _contrats,
          immatriculation: _immatriculation,
          accessToken    : widget.accessToken,
          tokenService   : _tokenService,
          cutoffUrl      : '$_baseUrl/lease/cutoff-time',
          errorType      : _errorType,
          errorStatus    : _errorStatus,
          onRefresh      : _refresh,
          onPayLease     : _navigateToPayLease,
        );
      case 1:
        return LeaseHistoryScreen(
            accessToken: widget.accessToken, leases: _leases,
            embedded: true, onPayLease: () => _navigateToPayLease());
      case 2:
        return ProfileScreen(user: widget.user, accessToken: widget.accessToken, embedded: true);
      default:
        return const SizedBox();
    }
  }

  Widget _buildBottomNav(AppLocalizations t) => Container(
    decoration: const BoxDecoration(
        color: _bgSubtle, border: Border(top: BorderSide(color: _border))),
    child: BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) { setState(() => _currentIndex = i); },
      backgroundColor: Colors.transparent, elevation: 0,
      selectedItemColor: _orange, unselectedItemColor: _textMuted,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.home_rounded),          label: t.navHome),
        BottomNavigationBarItem(icon: const Icon(Icons.history_rounded),        label: t.navHistory),
        BottomNavigationBarItem(icon: const Icon(Icons.person_outline_rounded), label: t.navProfile),
      ],
    ),
  );

  Widget _buildLoader(AppLocalizations t) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(color: _orange, strokeWidth: 2.5),
    const SizedBox(height: 16),
    Text(t.loadingLeaseData, style: const TextStyle(color: _textMuted, fontSize: 14)),
  ]));
}

// ══════════════════════════════════════════════════════════════════════════════
// ANIMATED ERROR WIDGET
// ══════════════════════════════════════════════════════════════════════════════
class _AnimatedErrorWidget extends StatefulWidget {
  final _FetchErrorType errorType; final int? statusCode;
  final Future<void> Function() onRetry;
  const _AnimatedErrorWidget({required this.errorType, required this.onRetry, this.statusCode});
  @override State<_AnimatedErrorWidget> createState() => _AnimatedErrorWidgetState();
}
class _AnimatedErrorWidgetState extends State<_AnimatedErrorWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;
  @override void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.errorType == _FetchErrorType.notFound || widget.errorType == _FetchErrorType.server;
    final color   = isAdmin ? _yellow : _red;
    final icon    = isAdmin ? Icons.admin_panel_settings_rounded : Icons.wifi_off_rounded;
    final title   = isAdmin ? "Contactez l'administrateur" : 'Vérifiez votre connexion';
    final sub     = isAdmin
        ? 'Aucune ressource trouvée (${widget.statusCode ?? "?"}).\nVotre compte n\'est peut-être pas encore configuré.'
        : 'Impossible de joindre le serveur.\nVérifiez votre connexion internet et réessayez.';
    return Center(child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ScaleTransition(scale: _pulse, child: Container(width: 72, height: 72,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3), width: 1.5)),
            child: Icon(icon, color: color, size: 34))),
        const SizedBox(height: 20),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _textPrimary), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(sub, style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.5), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        ElevatedButton.icon(onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Réessayer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13), elevation: 0)),
      ]),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME TAB
// ══════════════════════════════════════════════════════════════════════════════
class _HomeTab extends StatefulWidget {
  final Map<String, dynamic>              user;
  final List<String>                      roles;
  final List<Lease>                       leases;
  final List<_Contrat>                    contrats;
  final String?                           immatriculation;
  final String                            accessToken;
  final TokenRefreshService               tokenService;
  final String                            cutoffUrl;
  final _FetchErrorType?                  errorType;
  final int?                              errorStatus;
  final Future<void> Function()           onRefresh;
  final void Function({int? preSelectedLeaseId}) onPayLease;

  const _HomeTab({
    required this.user, required this.roles, required this.leases,
    required this.contrats, required this.accessToken, required this.tokenService,
    required this.cutoffUrl, required this.onRefresh, required this.onPayLease,
    this.immatriculation, this.errorType, this.errorStatus,
  });

  @override State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late Timer _clockTimer;
  DateTime   _now = DateTime.now();

  DateTime? _cutoffTarget;
  bool      _cutoffLoading    = true;
  bool      _warningShown     = false;
  bool      _warningDismissed = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _checkCutoffWarning();
    });
    _fetchCutoff();
  }

  @override
  void didUpdateWidget(covariant _HomeTab old) {
    super.didUpdateWidget(old);
    if (old.leases.length != widget.leases.length ||
        old.immatriculation != widget.immatriculation) {
      _warningShown = false; _warningDismissed = false;
      _fetchCutoff();
    }
  }

  @override void dispose() { _clockTimer.cancel(); super.dispose(); }

  // ── cutoff ────────────────────────────────────────────────────────────────
  Future<void> _fetchCutoff() async {
    final immat = widget.immatriculation;
    if (immat == null || immat.isEmpty) {
      if (mounted) setState(() { _cutoffLoading = false; _cutoffTarget = null; });
      return;
    }
    try {
      final uri = Uri.parse(widget.cutoffUrl)
          .replace(queryParameters: {'immatriculation': immat});
      _log('fetchCutoff GET $uri');
      final res = await http.get(uri, headers: {
        'Accept': 'application/json', 'ngrok-skip-browser-warning': 'true',
      }).timeout(const Duration(seconds: 10));
      _log('fetchCutoff ${res.statusCode}');
      if (res.statusCode == 200) {
        final data    = jsonDecode(res.body) as Map<String, dynamic>;
        final nextIso = data['next_cutoff_iso'] as String?;
        if (nextIso != null) {
          final target = DateTime.parse(nextIso).toLocal();
          if (mounted) setState(() { _cutoffTarget = target; _cutoffLoading = false; });
          return;
        }
      }
    } catch (e) { _logErr('fetchCutoff error', e); }
    final fallback = DateTime(_now.year, _now.month, _now.day + 1);
    if (mounted) setState(() { _cutoffTarget = fallback; _cutoffLoading = false; });
  }

  void _checkCutoffWarning() {
    if (_cutoffLoading || _cutoffTarget == null) return;
    if (_warningShown || _warningDismissed) return;
    final secsLeft = _cutoffTarget!.difference(_now).inSeconds;
    if (secsLeft <= 30 && secsLeft > 0) {
      _warningShown = true;
      showDialog(context: context, barrierDismissible: false,
          builder: (_) => _CutoffWarningDialog(
            immatriculation: widget.immatriculation ?? 'votre véhicule',
            cutoffTarget   : _cutoffTarget!,
            onPayNow: () { Navigator.of(context).pop(); widget.onPayLease(); },
            onDismiss: () { _warningDismissed = true; Navigator.of(context).pop(); },
          ));
    }
  }

  // ── countdown ─────────────────────────────────────────────────────────────
  DateTime get _effectiveCutoff =>
      _cutoffTarget ?? DateTime(_now.year, _now.month, _now.day + 1);
  Duration get _remaining {
    final d = _effectiveCutoff.difference(_now);
    return d.isNegative ? Duration.zero : d;
  }
  String get _countdownStr {
    if (_cutoffLoading) return '--:--:--';
    final d = _remaining;
    return '${_pad(d.inHours)}:${_pad(d.inMinutes % 60)}:${_pad(d.inSeconds % 60)}';
  }
  Color  get _countdownColor => _remaining.inMinutes < 60 ? _red : _orange;
  bool   get _isUrgent       => _remaining.inMinutes < 60;
  String _pad(int n) => n.toString().padLeft(2, '0');

  // ── summary from contrats ─────────────────────────────────────────────────
  // Total expected = sum of montant_total across all contracts
  double get _grandTotal    => widget.contrats.fold(0.0, (s, c) => s + c.montantTotal);
  // Total paid = sum of montant_verse
  double get _grandPaid     => widget.contrats.fold(0.0, (s, c) => s + c.montantVerse);
  // Total remaining = sum of montant_restant
  double get _grandRemaining => widget.contrats.fold(0.0, (s, c) => s + c.montantRestant);

  // ── today payments ────────────────────────────────────────────────────────
  String get _today => _now.toIso8601String().substring(0, 10);

  // All actionable leases due today
  List<Lease> get _todayLeases =>
      widget.leases.where((l) => l.dateEcheance == _today && l.isActionable).toList();

  // Sum of reste_a_payer for all today's leases = total due today
  double get _todayTotalDue =>
      _todayLeases.fold(0.0, (s, l) => s + l.resteAPayer);

  // ── misc helpers ──────────────────────────────────────────────────────────
  bool get _hasNoData => widget.leases.isEmpty && widget.contrats.isEmpty;

  String get _timeStr => '${_pad(_now.hour)}:${_pad(_now.minute)}:${_pad(_now.second)}';
  String _dateStr() {
    const months = ['','Janvier','Février','Mars','Avril','Mai','Juin',
      'Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    const days   = ['','Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];
    return '${days[_now.weekday]}, ${_now.day} ${months[_now.month]}';
  }
  String _fmt(double v) => v.toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  String get _userName {
    final d = _safeStr(widget.user['nom_complet'] ?? widget.user['name'] ?? widget.user['full_name']);
    if (d.isNotEmpty) return d;
    return '${_safeStr(widget.user['nom'])} ${_safeStr(widget.user['prenom'])}'.trim().isEmpty
        ? 'Utilisateur'
        : '${_safeStr(widget.user['nom'])} ${_safeStr(widget.user['prenom'])}'.trim();
  }
  String get _userInitials {
    final parts = _userName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty)  return parts.first[0].toUpperCase();
    return 'U';
  }
  String get _primaryRole => widget.roles.isNotEmpty ? widget.roles.first : 'DRIVER';

  Color _statutColor(String s) {
    switch (s) {
      case 'PAYE':               return _green;
      case 'PARTIELLEMENT_PAYE': return _yellow;
      case 'SUSPENDU':           return _purple;
      case 'CONTENTIEUX':        return _red;
      default:                   return _red;
    }
  }
  String _statutLabel(String s, AppLocalizations t) {
    switch (s) {
      case 'PAYE':               return t.statusPaid;
      case 'PARTIELLEMENT_PAYE': return t.statusPartial;
      case 'SUSPENDU':           return 'SUSPENDU';
      case 'CONTENTIEUX':        return 'CONTENTIEUX';
      default:                   return t.statusUnpaid;
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (widget.errorType != null && widget.leases.isEmpty) {
      return _AnimatedErrorWidget(
          errorType: widget.errorType!, statusCode: widget.errorStatus, onRetry: widget.onRefresh);
    }
    final todayLeases = _todayLeases;
    return RefreshIndicator(
      color: _orange, backgroundColor: _card, onRefresh: widget.onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // user hero
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,16,16,0),
              child: _buildUserHeroCard())),
          // clock + countdown
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
              child: _buildClockRow(t))),
          // summary box (from contrats)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
              child: _buildSummaryBox(t))),
          // empty state
          if (_hasNoData)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
                child: _buildEmptyCard())),
          // TODAY'S PAYMENT HERO CARD — sum of all today's dues
          if (todayLeases.isNotEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
                child: _buildTodayHeroCard(t))),
          // section header + details list
          if (todayLeases.isNotEmpty) ...[
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16,14,16,8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t.sectionTodayPayments, style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5)),
                GestureDetector(onTap: () => widget.onPayLease(),
                    child: Text(t.payAll, style: const TextStyle(fontSize: 12,
                        color: _orange, fontWeight: FontWeight.w600))),
              ]),
            )),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,0,16,0),
                child: _buildTodayDetailsList(todayLeases, t))),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildUserHeroCard() {
    final email = _safeStr(widget.user['email']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Row(children: [
        Container(width: 50, height: 50,
            decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFF58220), Color(0xFFC45E00)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Center(child: Text(_userInitials, style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_userName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              color: _textPrimary, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(email, style: const TextStyle(fontSize: 11, color: _textMuted),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            _badge(_primaryRole, _orange),
            if (widget.immatriculation != null) ...[
              const SizedBox(width: 6),
              _badge(widget.immatriculation!, _textMuted, bg: _bgSubtle),
            ],
          ]),
        ])),
        Container(width: 9, height: 9,
            decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
      ]),
    );
  }

  Widget _badge(String text, Color color, {Color? bg}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.30))),
    child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.5)),
  );

  Widget _buildClockRow(AppLocalizations t) {
    final cc = _countdownColor;
    return Row(children: [
      Expanded(child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.access_time_rounded, color: _textMuted, size: 11),
            const SizedBox(width: 4),
            Text(t.localTime, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                color: _textMuted, letterSpacing: 1.0)),
          ]),
          const SizedBox(height: 5),
          Text(_timeStr, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
              color: _textPrimary, letterSpacing: 1)),
          Text(_dateStr(), style: const TextStyle(fontSize: 9, color: _textMuted),
              overflow: TextOverflow.ellipsis),
        ]),
      )),
      const SizedBox(width: 10),
      Expanded(child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(13),
            border: Border.all(color: cc.withOpacity(0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_isUrgent ? Icons.warning_amber_rounded : Icons.timer_outlined, color: cc, size: 11),
            const SizedBox(width: 4),
            Expanded(child: Text(t.nextPayIn, style: TextStyle(fontSize: 9,
                fontWeight: FontWeight.w700, color: cc, letterSpacing: 1.0),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 5),
          Text(_countdownStr, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
              color: cc, letterSpacing: 1)),
          Text(t.hrsMinSec, style: const TextStyle(fontSize: 9, color: _textMuted)),
        ]),
      )),
    ]);
  }

  /// Summary box — totals pulled from contrats API (montant_total, montant_verse, montant_restant)
  /// Progress bar removed: only the three stat cards remain.
  Widget _buildSummaryBox(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.summaryTitle, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: _textMuted, letterSpacing: 1.4)),
        const SizedBox(height: 12),
        Row(children: [
          // Total expected
          Expanded(child: _statBox(
            label   : 'Total contrats',
            amount  : _fmt(_grandTotal),
            subLabel: '${widget.contrats.length} contrat${widget.contrats.length > 1 ? 's' : ''}',
            topColor: _orange,
          )),
          const SizedBox(width: 8),
          // Total paid
          Expanded(child: _statBox(
            label   : t.statusPaid,
            amount  : _fmt(_grandPaid),
            subLabel: 'versé',
            topColor: _green,
          )),
          const SizedBox(width: 8),
          // Total remaining
          Expanded(child: _statBox(
            label   : t.remaining,
            amount  : _fmt(_grandRemaining),
            subLabel: 'restant',
            topColor: _red,
          )),
        ]),
      ]),
    );
  }

  Widget _statBox({required String label, required String amount,
    required String subLabel, required Color topColor}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(color: _bgSubtle, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: Column(children: [
            Container(height: 3, color: topColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(children: [
                Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                    color: _textMuted, letterSpacing: .7), textAlign: TextAlign.center),
                const SizedBox(height: 5),
                Text(amount, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: _textPrimary), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                const SizedBox(height: 3),
                Text(subLabel, style: const TextStyle(fontSize: 8, color: _textMuted),
                    textAlign: TextAlign.center),
              ]),
            ),
          ]),
        ),
      );

  Widget _buildEmptyCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border)),
    child: Column(children: [
      Container(width: 58, height: 58,
          decoration: BoxDecoration(color: _orange.withOpacity(0.12), shape: BoxShape.circle,
              border: Border.all(color: _orange.withOpacity(0.30))),
          child: const Icon(Icons.assignment_outlined, color: _orange, size: 28)),
      const SizedBox(height: 14),
      const Text('Aucune donnée de recouvrement', style: TextStyle(color: _textPrimary,
          fontSize: 15, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      const Text('Le serveur a bien répondu, mais aucun contrat et aucune échéance ne sont associés à ce compte.',
          style: TextStyle(color: _textMuted, fontSize: 12, height: 1.45), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      Row(children: [Expanded(child: OutlinedButton.icon(
        onPressed: widget.onRefresh,
        icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Recharger'),
        style: OutlinedButton.styleFrom(foregroundColor: _orange,
            side: const BorderSide(color: _orange),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ))]),
    ]),
  );

  /// Hero card showing the TOTAL amount due today (sum of all today's lease payments)
  Widget _buildTodayHeroCard(AppLocalizations t) {
    final totalDue = _todayTotalDue;
    final count    = _todayLeases.length;
    return GestureDetector(
      onTap: () => widget.onPayLease(),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color       : _card,
          borderRadius: BorderRadius.circular(16),
          border      : Border.all(color: _orange.withOpacity(0.5), width: 1.5),
          boxShadow   : [BoxShadow(color: _orange.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // header row
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.today_rounded, color: _orange, size: 12),
                const SizedBox(width: 5),
                Text(t.sectionTodayPayments,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _orange)),
              ]),
            ),
            const Spacer(),
            Text('$count paiement${count > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 11, color: _textMuted)),
          ]),
          const SizedBox(height: 14),
          // total due
          Text('Total à payer aujourd\'hui',
              style: const TextStyle(fontSize: 10, color: _textMuted, letterSpacing: 1.0,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('XAF ${_fmt(totalDue)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
                  color: _textPrimary, letterSpacing: -1.0)),
          const SizedBox(height: 14),
          // pay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onPayLease(),
              icon : const Icon(Icons.payment_rounded, size: 17),
              label: Text(t.payAll,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: Colors.white,
                padding  : const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Detail list — one row per lease due today, showing type label + individual amount
  Widget _buildTodayDetailsList(List<Lease> todayLeases, AppLocalizations t) {
    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: Column(children: [
        // header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border, width: 0.8))),
          child: Row(children: [
            const Icon(Icons.receipt_long_rounded, color: _textMuted, size: 15),
            const SizedBox(width: 8),
            Text('Détail des paiements du jour',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textPrimary)),
          ]),
        ),
        // rows
        ...todayLeases.asMap().entries.map((entry) {
          final i      = entry.key;
          final lease  = entry.value;
          final isLast = i == todayLeases.length - 1;
          final sc     = _statutColor(lease.statut);
          final label  = _statutLabel(lease.statut, t);
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 13, 11),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: _border, width: 0.8)),
            ),
            child: Row(children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lease.typeContratLibelle.isNotEmpty
                    ? lease.typeContratLibelle : 'Contrat #${lease.contratId}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textPrimary)),
                const SizedBox(height: 1),
                Text('Échéance ${lease.dateEcheance}',
                    style: const TextStyle(fontSize: 9, color: _textMuted)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('XAF ${_fmt(lease.resteAPayer)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textPrimary)),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: sc.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(label, style: TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700, color: sc)),
                ),
              ]),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => widget.onPayLease(preSelectedLeaseId: lease.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(8)),
                  child: Text(t.pay, style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CUTOFF WARNING DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _CutoffWarningDialog extends StatefulWidget {
  final String immatriculation; final DateTime cutoffTarget;
  final VoidCallback onPayNow; final VoidCallback onDismiss;
  const _CutoffWarningDialog({required this.immatriculation, required this.cutoffTarget,
    required this.onPayNow, required this.onDismiss});
  @override State<_CutoffWarningDialog> createState() => _CutoffWarningDialogState();
}
class _CutoffWarningDialogState extends State<_CutoffWarningDialog>
    with SingleTickerProviderStateMixin {
  late Timer               _timer;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      if (widget.cutoffTarget.difference(_now).inSeconds <= 0) {
        _timer.cancel();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }
  @override void dispose() { _timer.cancel(); _pulseCtrl.dispose(); super.dispose(); }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String get _countStr {
    final d = widget.cutoffTarget.difference(_now);
    if (d.isNegative) return '00';
    return _pad(d.inSeconds.clamp(0, 99));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _red.withOpacity(0.6), width: 1.5),
            boxShadow: [BoxShadow(color: _red.withOpacity(0.25), blurRadius: 32, spreadRadius: 4)]),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(scale: _pulse, child: Container(width: 76, height: 76,
              decoration: BoxDecoration(color: _red.withOpacity(0.12), shape: BoxShape.circle,
                  border: Border.all(color: _red.withOpacity(0.4), width: 2)),
              child: const Icon(Icons.electric_bolt_rounded, color: _red, size: 36))),
          const SizedBox(height: 20),
          Container(width: 70, height: 70,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: _red.withOpacity(0.3), width: 3),
                  color: _red.withOpacity(0.08)),
              child: Center(child: Text(_countStr, style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, color: _red, letterSpacing: -1)))),
          const SizedBox(height: 6),
          Text('secondes', style: TextStyle(fontSize: 10, color: _textMuted.withOpacity(0.8))),
          const SizedBox(height: 18),
          const Text('Coupure imminente !', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w900, color: _textPrimary, letterSpacing: -0.3),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          RichText(textAlign: TextAlign.center, text: TextSpan(
            style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.5),
            children: [
              const TextSpan(text: 'Votre véhicule '),
              TextSpan(text: widget.immatriculation,
                  style: const TextStyle(color: _orange, fontWeight: FontWeight.w800)),
              const TextSpan(text: ' va être coupé dans quelques secondes.\nPayez maintenant pour éviter la coupure.'),
            ],
          )),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: widget.onPayNow,
            icon: const Icon(Icons.payment_rounded, size: 18),
            label: const Text('Payer maintenant',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          )),
          const SizedBox(height: 10),
          TextButton(onPressed: widget.onDismiss,
              child: Text('Ignorer', style: TextStyle(fontSize: 12,
                  color: _textMuted.withOpacity(0.7), fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}