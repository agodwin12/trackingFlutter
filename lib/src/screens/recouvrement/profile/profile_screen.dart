// lib/src/screens/recouvrement/profile/profile_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:FLEETRA/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/env_config.dart';
import '../../../services/token_refresh_service.dart';
import '../../login/login.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEBUG
// ─────────────────────────────────────────────────────────────────────────────
const bool _profileDebugLogs = true;
void _logProfile(String message) {
  if (!_profileDebugLogs) return;
  debugPrint('👤 [ProfileScreen] $message');
}
void _logProfileError(String message, Object error, [StackTrace? stackTrace]) {
  if (!_profileDebugLogs) return;
  debugPrint('❌ [ProfileScreen] $message');
  debugPrint('❌ [ProfileScreen] Error: $error');
  if (stackTrace != null) debugPrint('❌ [ProfileScreen] StackTrace: $stackTrace');
}
String _bodyPreview(String body, {int max = 1200}) =>
    body.length <= max ? body : '${body.substring(0, max)}... [+${body.length - max}]';
String _maskToken(String token) =>
    token.length <= 12 ? '***' : '${token.substring(0, 6)}...${token.substring(token.length - 6)}';

// ─────────────────────────────────────────────────────────────────────────────
// SAFE PARSERS
// ─────────────────────────────────────────────────────────────────────────────
Map<String, dynamic> _asMap(Map data) =>
    data.map((key, value) => MapEntry(key.toString(), value));
Map<String, dynamic>? _mapOrNull(dynamic value) {
  if (value is Map) return _asMap(value);
  return null;
}
int _toInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int)  return value;
  if (value is num)  return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? fallback;
}
double _toDouble(dynamic value, {double fallback = 0}) {
  if (value == null)   return fallback;
  if (value is double) return value;
  if (value is num)    return value.toDouble();
  final text = value.toString().trim().replaceAll(' ', '').replaceAll(',', '.');
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return double.tryParse(text) ?? fallback;
}
String _toStr(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return text;
}
List<dynamic> _extractList(dynamic raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['results', 'data', 'items']) {
      if (raw[key] is List) return raw[key] as List;
    }
    if (raw.containsKey('id')) return [raw];
  }
  return const [];
}
Uri _buildUri(String baseUrl, String endpoint) {
  final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final ep   = endpoint.startsWith('/') ? endpoint : '/$endpoint';
  return Uri.parse('$base$ep');
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTRACT MODEL  — flat structure, grouped client-side
// ─────────────────────────────────────────────────────────────────────────────
class Contract {
  final int    id;
  final int?   parentId;          // null = main contract
  final int    compteId;
  final String reference;
  final String immatriculation;
  final String vin;
  final String nomComplet;
  final String chauffeurNomComplet;
  final String enregistreParNomComplet;
  final String typeContratLibelle; // ← from API directly
  final double montantTotal;
  final double montantRestant;
  final double montantVerse;       // ← paid so far
  final double montantParPaiement;
  final String frequence;
  final String dateDebut;
  final String dateFin;
  final String prochaineEcheance;
  final String statut;
  final String createdAt;

  // populated after grouping
  List<Contract> sousContrats;

  Contract({
    required this.id,
    required this.parentId,
    required this.compteId,
    required this.reference,
    required this.immatriculation,
    required this.vin,
    required this.nomComplet,
    required this.chauffeurNomComplet,
    required this.enregistreParNomComplet,
    required this.typeContratLibelle,
    required this.montantTotal,
    required this.montantRestant,
    required this.montantVerse,
    required this.montantParPaiement,
    required this.frequence,
    required this.dateDebut,
    required this.dateFin,
    required this.prochaineEcheance,
    required this.statut,
    required this.createdAt,
    this.sousContrats = const [],
  });

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
    id                      : _toInt(j['id']),
    parentId                : j['parent'] != null ? _toInt(j['parent']) : null,
    compteId                : _toInt(j['compte_id']),
    reference               : _toStr(j['reference']),
    immatriculation         : _toStr(j['immatriculation']),
    vin                     : _toStr(j['vin']),
    nomComplet              : _toStr(j['nom_complet']),
    chauffeurNomComplet     : _toStr(j['chauffeur_nom_complet']),
    enregistreParNomComplet : _toStr(j['enregistre_par_nom_complet']),
    typeContratLibelle      : _toStr(j['type_contrat_libelle']),
    montantTotal            : _toDouble(j['montant_total']),
    montantRestant          : _toDouble(j['montant_restant']),
    montantVerse            : _toDouble(j['montant_verse']),
    montantParPaiement      : _toDouble(j['montant_par_paiement']),
    frequence               : _toStr(j['frequence']),
    dateDebut               : _toStr(j['date_debut']),
    dateFin                 : _toStr(j['date_fin']),
    prochaineEcheance       : _toStr(j['prochaine_echeance']),
    statut                  : _toStr(j['statut'], fallback: 'INCONNU').toUpperCase(),
    createdAt               : _toStr(j['created_at']),
  );

  bool get isMain => parentId == null;
  bool get isSub  => parentId != null;

  double get progressPercent {
    if (montantTotal <= 0) return 0;
    return (montantVerse / montantTotal).clamp(0.0, 1.0);
  }

  String get displayTitle {
    if (typeContratLibelle.isNotEmpty) return typeContratLibelle;
    if (nomComplet.isNotEmpty)         return nomComplet;
    if (immatriculation.isNotEmpty)    return immatriculation;
    return 'Contrat #$id';
  }

  String get displayVehicle {
    if (immatriculation.isNotEmpty && vin.isNotEmpty) return '$immatriculation · $vin';
    if (immatriculation.isNotEmpty) return immatriculation;
    if (vin.isNotEmpty)             return vin;
    return '-';
  }
}

/// Groups a flat list into [main → children] trees.
List<Contract> _groupContracts(List<Contract> flat) {
  final Map<int, Contract> byId    = { for (final c in flat) c.id: c };
  final mains = <Contract>[];

  for (final c in flat) {
    if (c.isMain) {
      mains.add(c);
    } else {
      final parent = byId[c.parentId];
      if (parent != null) {
        parent.sousContrats = [...parent.sousContrats, c];
      } else {
        // orphaned sub-contract — treat as main
        mains.add(c);
      }
    }
  }

  // sort mains by prochaine_echeance asc
  mains.sort((a, b) {
    if (a.prochaineEcheance.isEmpty && b.prochaineEcheance.isEmpty) return b.id.compareTo(a.id);
    if (a.prochaineEcheance.isEmpty) return 1;
    if (b.prochaineEcheance.isEmpty) return -1;
    return a.prochaineEcheance.compareTo(b.prochaineEcheance);
  });

  return mains;
}

// ─────────────────────────────────────────────────────────────────────────────
// COLOURS
// ─────────────────────────────────────────────────────────────────────────────
const Color _bg          = Color(0xFF0D1117);
const Color _bgSubtle    = Color(0xFF161B22);
const Color _card        = Color(0xFF1C2333);
const Color _inputBg     = Color(0xFF21262D);
const Color _border      = Color(0xFF30363D);
const Color _orange      = Color(0xFFF58220);
const Color _textMuted   = Color(0xFF8B949E);
const Color _textPrimary = Color(0xFFE6EDF3);
const Color _green       = Color(0xFF16A34A);
const Color _red         = Color(0xFFDC2626);
const Color _blue        = Color(0xFF2563EB);
const Color _yellow      = Color(0xFFD97706);
const Color _purple      = Color(0xFF8B5CF6);

// icon per contract type label
IconData _typeIcon(String libelle) {
  switch (libelle.toLowerCase()) {
    case 'moto':       return Icons.two_wheeler_rounded;
    case 'téléphone':
    case 'telephone':  return Icons.phone_android_rounded;
    case 'parapluie':  return Icons.umbrella_rounded;
    case 'voiture':
    case 'car':        return Icons.directions_car_rounded;
    default:           return Icons.assignment_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String               accessToken;
  final bool                 embedded;

  const ProfileScreen({
    Key? key,
    required this.user,
    required this.accessToken,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Contract> _contracts  = []; // grouped mains
  bool           _loading    = true;
  String?        _error;
  bool           _showPassView = false;

  final Set<int> _expandedSous = {};

  final _currentPassCtrl  = TextEditingController();
  final _newPassCtrl      = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  bool _savingPass     = false;
  bool _loggingOut     = false;
  bool _notifOn        = true;

  final _tokenService = TokenRefreshService();

  String get _partnerUrl  => EnvConfig.partnerApiUrl;
  String get _trackingUrl => EnvConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _logProfile('initState embedded=${widget.embedded}');
    _logProfile('token=${_maskToken(widget.accessToken)}');
    _fetchContracts();
  }

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ── fetch ─────────────────────────────────────────────────────────────────
  Future<void> _fetchContracts() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    final uri = _buildUri(_partnerUrl, '/contrats/');
    _logProfile('GET $uri');

    try {
      final res = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.get(uri, headers: {
          'Authorization'             : 'Bearer $token',
          'Content-Type'              : 'application/json',
          'Accept'                    : 'application/json',
          'ngrok-skip-browser-warning': 'true',
        }).timeout(const Duration(seconds: 20)),
      );

      _logProfile('status=${res.statusCode} body=${_bodyPreview(res.body)}');
      if (!mounted) return;

      if (res.statusCode < 200 || res.statusCode >= 300) {
        setState(() { _error = 'Échec du chargement (${res.statusCode})'; _loading = false; });
        return;
      }

      final list = _extractList(jsonDecode(res.body));
      _logProfile('raw count=${list.length}');

      final flat = <Contract>[];
      for (int i = 0; i < list.length; i++) {
        try {
          final m = _mapOrNull(list[i]);
          if (m == null) continue;
          final c = Contract.fromJson(m);
          _logProfile('parsed[$i] id=${c.id} parent=${c.parentId} '
              'type=${c.typeContratLibelle} statut=${c.statut}');
          flat.add(c);
        } catch (e, st) { _logProfileError('parse error index=$i', e, st); }
      }

      final grouped = _groupContracts(flat);
      _logProfile('grouped mains=${grouped.length} '
          'total subs=${grouped.fold(0, (s, c) => s + c.sousContrats.length)}');

      if (!mounted) return;
      setState(() { _contracts = grouped; _loading = false; });
    } on TimeoutException catch (e, st) {
      _logProfileError('Timeout', e, st);
      if (!mounted) return;
      setState(() { _error = 'Délai dépassé. Veuillez réessayer.'; _loading = false; });
    } on FormatException catch (e, st) {
      _logProfileError('Bad JSON', e, st);
      if (!mounted) return;
      setState(() { _error = 'Réponse serveur invalide.'; _loading = false; });
    } catch (e, st) {
      _logProfileError('Error', e, st);
      if (!mounted) return;
      setState(() { _error = 'Erreur de connexion: $e'; _loading = false; });
    }
  }

  // ── change password ───────────────────────────────────────────────────────
  Future<void> _savePassword(AppLocalizations t) async {
    final current = _currentPassCtrl.text.trim();
    final next    = _newPassCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();
    final isFr    = Localizations.localeOf(context).languageCode == 'fr';

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showSnack(t.errorFillAllFields, isError: true); return;
    }
    if (next != confirm) {
      _showSnack(t.errorPasswordMismatch, isError: true); return;
    }
    if (next.length < 8) {
      _showSnack(t.errorPasswordTooShort, isError: true); return;
    }
    if (current == next) {
      _showSnack(isFr ? 'Le nouveau mot de passe doit être différent.' : 'New password must differ from current.', isError: true);
      return;
    }

    setState(() => _savingPass = true);
    final uri = _buildUri(_trackingUrl, '/partner/change-password');
    _logProfile('PUT $uri');

    try {
      final res = await _tokenService.makeAuthenticatedRequest(
        request: (token) => http.put(uri, headers: {
          'Authorization': 'Bearer $token',
          'Content-Type' : 'application/json',
          'Accept'       : 'application/json',
        }, body: jsonEncode({'currentPassword': current, 'newPassword': next}))
            .timeout(const Duration(seconds: 15)),
      );

      _logProfile('password update status=${res.statusCode}');
      if (!mounted) return;

      Map<String, dynamic> data = {};
      try {
        final d = jsonDecode(res.body);
        if (d is Map) data = _asMap(d);
      } catch (_) {}

      if (res.statusCode == 200) {
        setState(() { _savingPass = false; _showPassView = false; });
        _currentPassCtrl.clear(); _newPassCtrl.clear(); _confirmPassCtrl.clear();
        _showSnack(t.passwordUpdated);
      } else {
        final msg = _toStr(data['message'],
            fallback: isFr ? 'Échec de la mise à jour.' : 'Failed to update password.');
        setState(() => _savingPass = false);
        _showSnack(msg, isError: true);
      }
    } on TimeoutException catch (e, st) {
      _logProfileError('Timeout updating password', e, st);
      if (!mounted) return;
      setState(() => _savingPass = false);
      _showSnack(isFr ? 'Délai dépassé.' : 'Request timed out.', isError: true);
    } catch (e, st) {
      _logProfileError('Error updating password', e, st);
      if (!mounted) return;
      setState(() => _savingPass = false);
      _showSnack(isFr ? 'Erreur de connexion.' : 'Connection error.', isError: true);
    }
  }

  // ── logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      final prefs        = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken') ?? '';
      if (refreshToken.isNotEmpty) {
        try {
          final uri = _buildUri(_trackingUrl, '/partner/logout');
          await _tokenService.makeAuthenticatedRequest(
            request: (token) => http.post(uri, headers: {
              'Authorization': 'Bearer $token',
              'Content-Type' : 'application/json',
            }, body: jsonEncode({'refreshToken': refreshToken}))
                .timeout(const Duration(seconds: 8)),
          );
        } catch (e, st) { _logProfileError('Keycloak logout failed', e, st); }
      }
      await prefs.clear();
    } catch (e, st) {
      _logProfileError('Logout error', e, st);
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const ModernLoginScreen()), (_) => false);
  }

  void _confirmLogout(AppLocalizations t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _border)),
      title: Text(t.signOutConfirmTitle,
          style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w700)),
      content: Text(t.signOutConfirmMessage,
          style: const TextStyle(color: _textMuted, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text(t.cancel, style: const TextStyle(color: _textMuted))),
        ElevatedButton(
          onPressed: () { Navigator.pop(context); _logout(); },
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
          child: Text(t.signOut, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: isError ? _red : _green,
      behavior: SnackBarBehavior.floating,
      shape  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin : const EdgeInsets.all(16),
    ));
  }

  String get _fullName {
    final d = _toStr(widget.user['nom_complet'] ?? widget.user['name'] ??
        widget.user['full_name'] ?? widget.user['fullName']);
    if (d.isNotEmpty) return d;
    final f = '${_toStr(widget.user['nom'] ?? widget.user['last_name'])} '
        '${_toStr(widget.user['prenom'] ?? widget.user['first_name'])}'.trim();
    return f.isEmpty ? 'Utilisateur' : f;
  }

  String get _initials {
    final parts = _fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'U';
  }

  String _fmt(double n) => n.toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  Color _statutColor(String s) {
    switch (s.toUpperCase()) {
      case 'ACTIF':       return _green;
      case 'SOLDE':
      case 'TERMINE':
      case 'TERMINÉ':     return _blue;
      case 'SUSPENDU':
      case 'CONTENTIEUX': return _red;
      default:            return _orange;
    }
  }

  String _userVal(List<String> keys, {String fallback = '-'}) {
    for (final k in keys) {
      final v = _toStr(widget.user[k]);
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  // ── quick stats: contracts AND sub-contracts counted at the same level ────
  // _contracts only holds grouped mains; this flattens mains + all their subs
  // so the stat cards treat every contract individually.
  List<Contract> get _allContracts =>
      [for (final c in _contracts) ...[c, ...c.sousContrats]];

  int    get _activeCount    => _allContracts.where((c) => c.statut == 'ACTIF').length;
  int    get _settledCount   => _allContracts.where((c) => c.statut == 'SOLDE').length;
  double get _totalRemaining => _allContracts.fold(0.0, (s, c) => s + c.montantRestant);

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (_loggingOut) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: _orange, strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(Localizations.localeOf(context).languageCode == 'fr'
              ? 'Déconnexion...' : 'Signing out...',
              style: const TextStyle(color: _textMuted, fontSize: 14)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        _buildTopBar(t),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _orange, strokeWidth: 2.5))
            : _error != null
            ? _buildErrorState(t)
            : _showPassView
            ? _buildChangePasswordView(t)
            : _buildProfileView(t)),
      ])),
    );
  }

  Widget _buildTopBar(AppLocalizations t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: const BoxDecoration(
        color: _bgSubtle, border: Border(bottom: BorderSide(color: _border))),
    child: Row(children: [
      if (_showPassView || !widget.embedded)
        GestureDetector(
          onTap: () {
            if (_showPassView) setState(() => _showPassView = false);
            else Navigator.pop(context);
          },
          child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _card,
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _textMuted, size: 16)),
        ),
      if (_showPassView || !widget.embedded) const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_showPassView ? t.changePasswordTitle : t.profileTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
        Text(_showPassView ? t.changePasswordSubtitle : t.profileSubtitle,
            style: const TextStyle(fontSize: 11, color: _textMuted)),
      ])),
      if (!_showPassView)
        GestureDetector(
          onTap: _fetchContracts,
          child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _card,
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
              child: const Icon(Icons.refresh_rounded, color: _textMuted, size: 18)),
        ),
    ]),
  );

  Widget _buildErrorState(AppLocalizations t) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: BoxDecoration(color: _red.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.wifi_off_rounded, color: _red, size: 32)),
      const SizedBox(height: 16),
      Text(_error!, textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 14)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _fetchContracts,
        icon : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(t.retry),
        style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
      ),
    ]),
  ));

  Widget _buildProfileView(AppLocalizations t) => RefreshIndicator(
    color: _orange, backgroundColor: _card, onRefresh: _fetchContracts,
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _buildAvatarHero(),
        const SizedBox(height: 20),
        _buildQuickStats(),
        const SizedBox(height: 20),
        _buildSection(t.sectionAccountInfo, [
          _infoTile(icon: Icons.person_outline_rounded,  label: t.fieldFullName, value: _fullName),
          _infoTile(icon: Icons.mail_outline_rounded,    label: t.fieldEmail,    value: _userVal(['email', 'mail'])),
          _infoTile(icon: Icons.phone_outlined,          label: t.fieldPhone,    value: _userVal(['phone', 'telephone', 'tel'])),
          _infoTile(icon: Icons.location_city_outlined,  label: t.fieldCity,     value: _userVal(['ville', 'city'])),
          _infoTile(icon: Icons.place_outlined,          label: t.fieldQuartier, value: _userVal(['quartier', 'address', 'adresse']), isLast: true),
        ]),
        const SizedBox(height: 20),
        _buildContractsSection(t),
        const SizedBox(height: 20),
        _buildSection(t.sectionSettings, [
          _actionTile(icon: Icons.lock_outline_rounded, label: t.settingsChangePassword,
              iconColor: _orange, onTap: () => setState(() => _showPassView = true)),
          _actionTile(icon: Icons.notifications_outlined, label: t.settingsNotifications,
              iconColor: _blue, trailing: _buildToggle(), isLast: true),
        ]),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 50,
          child: OutlinedButton.icon(
            onPressed: () => _confirmLogout(t),
            icon : const Icon(Icons.logout_rounded, size: 18),
            label: Text(t.signOut,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(foregroundColor: _red,
                side: const BorderSide(color: _red, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 12),
        Text(t.appVersion, style: const TextStyle(fontSize: 10, color: _textMuted)),
        const SizedBox(height: 16),
      ]),
    ),
  );

  Widget _buildAvatarHero() => Column(children: [
    Stack(children: [
      Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
              colors: [Color(0xFFF58220), Color(0xFFC45E00)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: _orange.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Center(child: Text(_initials,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white))),
      ),
      Positioned(bottom: 2, right: 2,
          child: Container(width: 24, height: 24,
              decoration: BoxDecoration(color: _green, shape: BoxShape.circle,
                  border: Border.all(color: _bg, width: 2)),
              child: const Icon(Icons.check, color: Colors.white, size: 12))),
    ]),
    const SizedBox(height: 14),
    Text(_fullName, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
    const SizedBox(height: 4),
    Text(_userVal(['email', 'mail'], fallback: ''),
        style: const TextStyle(fontSize: 12, color: _textMuted)),
  ]);

  // Quick stats — counts span contracts AND sub-contracts (flattened)
  Widget _buildQuickStats() => Row(children: [
    Expanded(child: _statBox(icon: Icons.assignment_turned_in_rounded,
        label: 'Actifs',   value: '$_activeCount',           color: _green)),
    const SizedBox(width: 10),
    Expanded(child: _statBox(icon: Icons.check_circle_outline_rounded,
        label: 'Soldés',   value: '$_settledCount',          color: _blue)),
    const SizedBox(width: 10),
    Expanded(child: _statBox(icon: Icons.account_balance_wallet_outlined,
        label: 'Restant',  value: _fmt(_totalRemaining),     color: _orange, smallValue: true)),
  ]);

  Widget _statBox({required IconData icon, required String label,
    required String value, required Color color, bool smallValue = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.28))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: smallValue ? 13 : 18,
                  fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: _textMuted)),
        ]),
      );

  // ── contracts section ─────────────────────────────────────────────────────
  Widget _buildContractsSection(AppLocalizations t) {
    if (_contracts.isEmpty) {
      return _buildSection(t.sectionContractDetails, [
        Container(width: double.infinity, padding: const EdgeInsets.all(18),
            child: const Column(children: [
              Icon(Icons.assignment_outlined, color: _textMuted, size: 34),
              SizedBox(height: 10),
              Text('Aucun contrat trouvé.',
                  style: TextStyle(color: _textMuted, fontSize: 13)),
            ])),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.sectionContractDetails, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _textMuted, letterSpacing: 1.5)),
      ),
      ..._contracts.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _buildContractCard(c, t),
      )),
    ]);
  }

  Widget _buildContractCard(Contract c, AppLocalizations t) {
    final sc          = _statutColor(c.statut);
    final sousOpen    = _expandedSous.contains(c.id);
    final hasSous     = c.sousContrats.isNotEmpty;
    final typeIcon    = _typeIcon(c.typeContratLibelle);

    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sc.withOpacity(0.35))),
      child: Column(children: [

        // ── header ─────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: sc.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: const Border(bottom: BorderSide(color: _border))),
          child: Row(children: [
            Container(width: 48, height: 48,
                decoration: BoxDecoration(color: sc.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(typeIcon, color: sc, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // type label — big and clear
              Text(c.typeContratLibelle.isNotEmpty ? c.typeContratLibelle : 'Contrat #${c.id}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: _textPrimary)),
              const SizedBox(height: 2),
              Text(c.displayVehicle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _textMuted)),
              const SizedBox(height: 2),
              Text('Réf: ${c.reference.isEmpty ? '-' : c.reference} · ${c.frequence.isEmpty ? '-' : c.frequence}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _textMuted)),
            ])),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sc.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(c.statut, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: sc, letterSpacing: 0.5)),
            ),
          ]),
        ),

        // ── progress ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Progression du remboursement',
                  style: TextStyle(fontSize: 11, color: _textMuted)),
              const Spacer(),
              Text('${(c.progressPercent * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: c.progressPercent, backgroundColor: _border,
                    valueColor: AlwaysStoppedAnimation<Color>(sc), minHeight: 8)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Versé: XAF ${_fmt(c.montantVerse)}',
                  style: const TextStyle(fontSize: 11, color: _green))),
              Text('Restant: XAF ${_fmt(c.montantRestant)}',
                  style: const TextStyle(fontSize: 11, color: _red)),
            ]),
          ]),
        ),

        const Divider(color: _border, height: 24, indent: 16, endIndent: 16),

        // ── detail rows ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(children: [
            _row('Chauffeur',            c.chauffeurNomComplet.isEmpty ? '-' : c.chauffeurNomComplet),
            const SizedBox(height: 10),
            _row('Montant total',        'XAF ${_fmt(c.montantTotal)}'),
            const SizedBox(height: 10),
            _row('Montant par paiement', 'XAF ${_fmt(c.montantParPaiement)}'),
            const SizedBox(height: 10),
            _row('Fréquence',            c.frequence.isEmpty ? '-' : c.frequence),
            const SizedBox(height: 10),
            _row('Date début',           c.dateDebut.isEmpty  ? '-' : c.dateDebut),
            const SizedBox(height: 10),
            _row('Date fin',             c.dateFin.isEmpty    ? '-' : c.dateFin),
            const SizedBox(height: 10),
            _row('Prochaine échéance',
                c.prochaineEcheance.isEmpty ? '-' : c.prochaineEcheance,
                valueColor: _orange),
            const SizedBox(height: 10),
            _row('Enregistré par',
                c.enregistreParNomComplet.isEmpty ? '-' : c.enregistreParNomComplet),
          ]),
        ),

        // ── sous-contrats toggle ───────────────────────────────────────────
        if (hasSous) ...[
          GestureDetector(
            onTap: () => setState(() {
              if (sousOpen) _expandedSous.remove(c.id);
              else          _expandedSous.add(c.id);
            }),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.05),
                border: Border(
                  top   : const BorderSide(color: _border),
                  bottom: sousOpen ? const BorderSide(color: _border) : BorderSide.none,
                ),
                borderRadius: sousOpen
                    ? BorderRadius.zero
                    : const BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Row(children: [
                Container(width: 26, height: 26,
                    decoration: BoxDecoration(color: _orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.account_tree_rounded, color: _orange, size: 14)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '${c.sousContrats.length} sous-contrat${c.sousContrats.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: _textPrimary),
                )),
                AnimatedRotation(
                  turns: sousOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: _orange, size: 20),
                ),
              ]),
            ),
          ),

          // ── sous-contrats list ─────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: sousOpen
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(children: [
              ...c.sousContrats.asMap().entries.map((entry) {
                final i      = entry.key;
                final sc2    = entry.value;
                final col    = _statutColor(sc2.statut);
                final isLast = i == c.sousContrats.length - 1;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: col.withOpacity(0.03),
                    borderRadius: isLast
                        ? const BorderRadius.vertical(bottom: Radius.circular(15))
                        : BorderRadius.zero,
                    border: isLast
                        ? null
                        : const Border(bottom: BorderSide(color: _border, width: 0.8)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // sub header
                    Row(children: [
                      Container(width: 36, height: 36,
                          decoration: BoxDecoration(color: col.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(9)),
                          child: Icon(_typeIcon(sc2.typeContratLibelle), color: col, size: 18)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // type label prominent
                        Text(
                          sc2.typeContratLibelle.isNotEmpty
                              ? sc2.typeContratLibelle
                              : 'Sous-contrat #${sc2.id}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                              color: _textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text('${sc2.frequence.isEmpty ? '-' : sc2.frequence} · '
                            'XAF ${_fmt(sc2.montantParPaiement)}/paiement',
                            style: const TextStyle(fontSize: 10, color: _textMuted)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: col.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(sc2.statut,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: col)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    // progress
                    ClipRRect(borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                            value: sc2.progressPercent, backgroundColor: _border,
                            valueColor: AlwaysStoppedAnimation<Color>(col), minHeight: 5)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Text('Versé: XAF ${_fmt(sc2.montantVerse)}',
                          style: const TextStyle(fontSize: 10, color: _green))),
                      Text('Restant: XAF ${_fmt(sc2.montantRestant)}',
                          style: const TextStyle(fontSize: 10, color: _red)),
                    ]),
                    const SizedBox(height: 6),
                    _row('Montant total',      'XAF ${_fmt(sc2.montantTotal)}'),
                    const SizedBox(height: 4),
                    _row('Prochaine échéance',
                        sc2.prochaineEcheance.isEmpty ? '-' : sc2.prochaineEcheance,
                        valueColor: _orange),
                    const SizedBox(height: 4),
                    _row('Date fin', sc2.dateFin.isEmpty ? '-' : sc2.dateFin),
                  ]),
                );
              }),
            ]),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ]),
    );
  }

  // ── shared row ────────────────────────────────────────────────────────────
  Widget _row(String label, String value, {Color? valueColor}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
        const SizedBox(width: 14),
        Flexible(child: Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: valueColor ?? _textPrimary),
            overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
      ]);

  Widget _buildSection(String title, List<Widget> children) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Text(title, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: _textMuted, letterSpacing: 1.5))),
        Container(
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border)),
          child: Column(children: children),
        ),
      ]);

  Widget _infoTile({required IconData icon, required String label,
    required String value, bool isLast = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(border: isLast
            ? null : const Border(bottom: BorderSide(color: _border, width: 0.8))),
        child: Row(children: [
          Icon(icon, color: _textMuted, size: 16),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: _textMuted)),
            const SizedBox(height: 2),
            Text(value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: _textPrimary)),
          ])),
        ]),
      );

  Widget _actionTile({required IconData icon, required String label,
    required Color iconColor, VoidCallback? onTap, Widget? trailing, bool isLast = false}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isLast ? 14 : 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(border: isLast
              ? null : const Border(bottom: BorderSide(color: _border, width: 0.8))),
          child: Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: iconColor, size: 16)),
            const SizedBox(width: 12),
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: _textPrimary))),
            trailing ?? Icon(Icons.chevron_right_rounded,
                color: _textMuted.withOpacity(0.5), size: 20),
          ]),
        ),
      );

  Widget _buildToggle() => GestureDetector(
    onTap: () => setState(() => _notifOn = !_notifOn),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 24,
      decoration: BoxDecoration(color: _notifOn ? _orange : _border,
          borderRadius: BorderRadius.circular(12)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: _notifOn ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(margin: const EdgeInsets.all(3), width: 18, height: 18,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    ),
  );

  Widget _buildChangePasswordView(AppLocalizations t) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _orange.withOpacity(0.25))),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: _orange, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(t.passwordHint,
              style: const TextStyle(fontSize: 12, color: _orange, height: 1.4))),
        ]),
      ),
      const SizedBox(height: 24),
      _buildSection(t.sectionUpdatePassword, [
        _passField(controller: _currentPassCtrl, label: t.fieldCurrentPassword,
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent)),
        _passField(controller: _newPassCtrl, label: t.fieldNewPassword,
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew)),
        _passField(controller: _confirmPassCtrl, label: t.fieldConfirmPassword,
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            isLast: true),
      ]),
      const SizedBox(height: 28),
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton(
          onPressed: _savingPass ? null : () => _savePassword(t),
          style: ElevatedButton.styleFrom(backgroundColor: _orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _orange.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0),
          child: _savingPass
              ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Text(t.updatePassword,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _passField({required TextEditingController controller, required String label,
    required bool obscure, required VoidCallback onToggle, bool isLast = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: isLast
            ? null : const Border(bottom: BorderSide(color: _border, width: 0.8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller : controller,
            obscureText: obscure,
            style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: '••••••••', hintStyle: const TextStyle(color: _textMuted),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: _textMuted, size: 18),
                onPressed: onToggle,
              ),
              filled: true, fillColor: _inputBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border       : OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _orange, width: 1.5)),
            ),
          ),
        ]),
      );
}