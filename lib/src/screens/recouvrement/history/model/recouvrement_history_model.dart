// lib/src/screens/recouvrement/history/recouvrement_history_model.dart

import 'dart:math';

/// Small helper to parse paginated Django/DRF responses or direct list responses.
///
/// Supports:
/// - { "results": [...] }
/// - { "data": [...] }
/// - [...]
class ApiListParser {
  static List<Lease> leasesFromResponse(dynamic raw) {
    final list = _extractList(raw);
    return list
        .whereType<Map>()
        .map((e) => Lease.fromJson(_map(e)))
        .toList();
  }

  static List<Payment> paymentsFromResponse(dynamic raw) {
    final list = _extractList(raw);
    return list
        .whereType<Map>()
        .map((e) => Payment.fromJson(_map(e)))
        .toList();
  }

  static List<dynamic> _extractList(dynamic raw) {
    if (raw is List) return raw;

    if (raw is Map) {
      if (raw['results'] is List) return raw['results'] as List;
      if (raw['data'] is List) return raw['data'] as List;
      if (raw['items'] is List) return raw['items'] as List;
    }

    return const [];
  }
}

class Lease {
  final int id;
  final int contratId;

  final String reference;
  final String contratReference;
  final String nomComplet;

  final String chauffeurNom;
  final String immatriculation;
  final String vin;

  final String statut;
  final String frequence;

  /// yyyy-MM-dd, required by your calendar screen.
  final String dateEcheance;

  final DateTime? dateEcheanceDate;
  final DateTime? createdAt;

  /// Amount expected for this lease/echeance.
  final double montantAttendu;

  /// Amount already paid on this lease.
  final double montantPaye;

  /// Remaining amount on this lease.
  final double resteAPayer;

  /// Optional contract-level values.
  final double montantTotal;
  final double montantRestant;
  final double montantParPaiement;

  final Map<String, dynamic>? rawContrat;
  final Map<String, dynamic> raw;

  const Lease({
    required this.id,
    required this.contratId,
    required this.reference,
    required this.contratReference,
    required this.nomComplet,
    required this.chauffeurNom,
    required this.immatriculation,
    required this.vin,
    required this.statut,
    required this.frequence,
    required this.dateEcheance,
    required this.dateEcheanceDate,
    required this.createdAt,
    required this.montantAttendu,
    required this.montantPaye,
    required this.resteAPayer,
    required this.montantTotal,
    required this.montantRestant,
    required this.montantParPaiement,
    required this.rawContrat,
    required this.raw,
  });

  factory Lease.fromJson(Map<String, dynamic> json) {
    final contratMap = _mapOrNull(json['contrat']) ??
        _mapOrNull(json['contract']) ??
        _mapOrNull(json['parent']);

    final contratId = _asInt(
      json['contrat_id'] ??
          json['contratId'] ??
          json['contract_id'] ??
          json['parent_id'] ??
          _extractId(json['contrat']) ??
          _extractId(json['contract']) ??
          _extractId(json['parent']),
    );

    final dateValue = json['date_echeance'] ??
        json['dateEcheance'] ??
        json['echeance'] ??
        json['prochaine_echeance'] ??
        contratMap?['prochaine_echeance'];

    final expected = _asDouble(
      json['montant_attendu'] ??
          json['montantAttendu'] ??
          json['montant_du'] ??
          json['montant'] ??
          json['amount'] ??
          json['montant_par_paiement'] ??
          contratMap?['montant_par_paiement'],
    );

    final paid = _asDouble(
      json['montant_paye'] ??
          json['montantPaye'] ??
          json['paye'] ??
          json['amount_paid'] ??
          json['total_paye'] ??
          json['total_paid'],
    );

    final remainingFromApi = json['reste_a_payer'] ??
        json['resteAPayer'] ??
        json['montant_restant_echeance'] ??
        json['remaining_amount'];

    final remaining = remainingFromApi == null
        ? max(expected - paid, 0).toDouble()
        : _asDouble(remainingFromApi);

    final status = _asString(
      json['statut'] ??
          json['status'] ??
          json['etat'] ??
          contratMap?['statut'],
      fallback: 'ACTIF',
    ).toUpperCase();

    return Lease(
      id: _asInt(json['id'] ?? json['lease_id']),
      contratId: contratId,
      reference: _asString(json['reference'] ?? json['ref']),
      contratReference: _asString(
        json['contrat_reference'] ??
            json['contract_reference'] ??
            contratMap?['reference'],
      ),
      nomComplet: _asString(
        json['nom_complet'] ??
            json['nom_complet_search'] ??
            json['label'] ??
            contratMap?['nom_complet'],
      ),
      chauffeurNom: _asString(
        json['chauffeur_nom'] ??
            json['chauffeurNom'] ??
            _nestedString(json['chauffeur'], ['nom_complet', 'name', 'nom']) ??
            _nestedString(contratMap?['chauffeur'], ['nom_complet', 'name', 'nom']),
      ),
      immatriculation: _asString(
        json['immatriculation'] ?? contratMap?['immatriculation'],
      ),
      vin: _asString(json['vin'] ?? contratMap?['vin']),
      statut: status,
      frequence: _asString(
        json['frequence'] ?? contratMap?['frequence'],
        fallback: 'JOURNALIER',
      ).toUpperCase(),
      dateEcheance: _dateOnly(dateValue),
      dateEcheanceDate: _asDate(dateValue),
      createdAt: _asDate(json['created_at'] ?? json['createdAt']),
      montantAttendu: expected,
      montantPaye: status == 'SOLDE' && paid <= 0 && expected > 0
          ? expected
          : paid,
      resteAPayer: status == 'SOLDE' ? 0 : remaining,
      montantTotal: _asDouble(json['montant_total'] ?? contratMap?['montant_total']),
      montantRestant: _asDouble(
        json['montant_restant'] ?? contratMap?['montant_restant'],
      ),
      montantParPaiement: _asDouble(
        json['montant_par_paiement'] ?? contratMap?['montant_par_paiement'],
      ),
      rawContrat: contratMap,
      raw: json,
    );
  }

  bool get isPaid {
    if (statut == 'SOLDE') return true;
    if (montantAttendu > 0 && montantPaye >= montantAttendu) return true;
    return resteAPayer <= 0 && montantPaye > 0;
  }

  bool get isPartial {
    if (isPaid) return false;
    return montantPaye > 0 && resteAPayer > 0;
  }

  bool get isUnpaid {
    return !isPaid && !isPartial;
  }

  double get paymentProgress {
    if (montantAttendu <= 0) return 0;
    return (montantPaye / montantAttendu).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contrat_id': contratId,
      'reference': reference,
      'contrat_reference': contratReference,
      'nom_complet': nomComplet,
      'chauffeur_nom': chauffeurNom,
      'immatriculation': immatriculation,
      'vin': vin,
      'statut': statut,
      'frequence': frequence,
      'date_echeance': dateEcheance,
      'created_at': createdAt?.toIso8601String(),
      'montant_attendu': montantAttendu,
      'montant_paye': montantPaye,
      'reste_a_payer': resteAPayer,
      'montant_total': montantTotal,
      'montant_restant': montantRestant,
      'montant_par_paiement': montantParPaiement,
    };
  }
}

class Payment {
  final int id;
  final int leaseId;
  final int contratId;

  final String reference;
  final double montant;
  final String methode;
  final String statut;

  final bool estAnnule;

  final DateTime datePaiement;
  final DateTime createdAt;

  final String? sessionTelephone;
  final String? enregistrePar;
  final String? chauffeurNom;

  final Map<String, dynamic>? rawSession;
  final Map<String, dynamic>? rawLease;
  final Map<String, dynamic>? rawContrat;
  final Map<String, dynamic> raw;

  const Payment({
    required this.id,
    required this.leaseId,
    required this.contratId,
    required this.reference,
    required this.montant,
    required this.methode,
    required this.statut,
    required this.estAnnule,
    required this.datePaiement,
    required this.createdAt,
    required this.sessionTelephone,
    required this.enregistrePar,
    required this.chauffeurNom,
    required this.rawSession,
    required this.rawLease,
    required this.rawContrat,
    required this.raw,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    final leaseMap = _mapOrNull(json['lease']);
    final contratMap = _mapOrNull(json['contrat']) ??
        _mapOrNull(json['contract']) ??
        _mapOrNull(leaseMap?['contrat']);

    final sessionMap = _mapOrNull(json['session']);
    final enregistreParMap = _mapOrNull(json['enregistre_par']) ??
        _mapOrNull(json['recorded_by']) ??
        _mapOrNull(json['created_by']);

    final created = _asDate(
      json['created_at'] ??
          json['createdAt'] ??
          json['date_creation'] ??
          json['date_paiement'],
    ) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final paidAt = _asDate(
      json['date_paiement'] ??
          json['paid_at'] ??
          json['paidAt'] ??
          json['created_at'],
    ) ??
        created;

    return Payment(
      id: _asInt(json['id'] ?? json['payment_id']),
      leaseId: _asInt(
        json['lease_id'] ??
            json['leaseId'] ??
            _extractId(json['lease']),
      ),
      contratId: _asInt(
        json['contrat_id'] ??
            json['contratId'] ??
            json['contract_id'] ??
            _extractId(json['contrat']) ??
            _extractId(json['contract']) ??
            leaseMap?['contrat_id'] ??
            _extractId(leaseMap?['contrat']),
      ),
      reference: _asString(
        json['reference'] ??
            json['transaction_ref'] ??
            json['transaction_id'] ??
            json['ref'],
        fallback: 'PAY-${_asInt(json['id'])}',
      ),
      montant: _asDouble(json['montant'] ?? json['amount']),
      methode: _asString(json['methode'] ?? json['method'], fallback: 'CASH')
          .toUpperCase(),
      statut: _asString(json['statut'] ?? json['status'], fallback: 'EN_ATTENTE')
          .toUpperCase(),
      estAnnule: _asBool(json['est_annule'] ?? json['is_cancelled']),
      datePaiement: paidAt,
      createdAt: created,
      sessionTelephone: _nullableString(
        json['session_telephone'] ??
            json['sessionTelephone'] ??
            json['phone_number'] ??
            sessionMap?['telephone'] ??
            sessionMap?['phone_number'] ??
            sessionMap?['phone'],
      ),
      enregistrePar: _nullableString(
        json['enregistre_par_nom'] ??
            json['recorded_by_name'] ??
            _nestedString(enregistreParMap, ['nom_complet', 'name', 'nom']),
      ),
      chauffeurNom: _nullableString(
        json['chauffeur_nom'] ??
            _nestedString(json['chauffeur'], ['nom_complet', 'name', 'nom']) ??
            _nestedString(contratMap?['chauffeur'], ['nom_complet', 'name', 'nom']),
      ),
      rawSession: sessionMap,
      rawLease: leaseMap,
      rawContrat: contratMap,
      raw: json,
    );
  }

  bool get isValid {
    return statut == 'VALIDE' && !estAnnule;
  }

  bool get isPending {
    return statut == 'EN_ATTENTE' && !estAnnule;
  }

  bool get isMobile {
    return methode == 'MOBILE';
  }

  bool get isCash {
    return methode == 'CASH';
  }

  String get formattedDate {
    return _formatDate(datePaiement);
  }

  String get formattedTime {
    return _formatTime(datePaiement);
  }

  String get formattedDateTime {
    return '${_formatDate(datePaiement)} · ${_formatTime(datePaiement)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lease_id': leaseId,
      'contrat_id': contratId,
      'reference': reference,
      'montant': montant,
      'methode': methode,
      'statut': statut,
      'est_annule': estAnnule,
      'date_paiement': datePaiement.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'session_telephone': sessionTelephone,
      'enregistre_par': enregistrePar,
      'chauffeur_nom': chauffeurNom,
    };
  }
}

/// Optional request/filter model for `/api/v1/leases/`.
class LeaseHistoryFilter {
  final String? search;
  final String? statut;
  final List<String>? statutIn;
  final DateTime? dateEcheance;
  final DateTime? dateEcheanceStart;
  final DateTime? dateEcheanceEnd;
  final DateTime? createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  const LeaseHistoryFilter({
    this.search,
    this.statut,
    this.statutIn,
    this.dateEcheance,
    this.dateEcheanceStart,
    this.dateEcheanceEnd,
    this.createdAt,
    this.startDate,
    this.endDate,
  });

  Map<String, String> toQueryParameters() {
    final q = <String, String>{};

    void add(String key, Object? value) {
      if (value == null) return;
      final s = value.toString().trim();
      if (s.isEmpty) return;
      q[key] = s;
    }

    add('search', search);
    add('statut', statut);
    if (statutIn != null && statutIn!.isNotEmpty) {
      add('statut__in', statutIn!.join(','));
    }

    add('date_echeance', _dateOnly(dateEcheance));
    add('date_echeance_start', _dateOnly(dateEcheanceStart));
    add('date_echeance_end', _dateOnly(dateEcheanceEnd));
    add('created_at', _dateOnly(createdAt));
    add('start_date', _dateOnly(startDate));
    add('end_date', _dateOnly(endDate));

    return q;
  }
}

/// Optional request/filter model for `/api/v1/paiements/`.
class PaymentHistoryFilter {
  final String? search;
  final String? statut;
  final List<String>? statutIn;
  final String? methode;
  final List<String>? methodeIn;
  final bool? estAnnule;

  final DateTime? datePaiement;
  final DateTime? datePaiementStart;
  final DateTime? datePaiementEnd;

  final DateTime? createdAtStart;
  final DateTime? createdAtEnd;

  final double? montantMin;
  final double? montantMax;

  final int? contratId;
  final int? leaseId;
  final int? sessionId;
  final int? enregistreParId;
  final int? chauffeurId;

  const PaymentHistoryFilter({
    this.search,
    this.statut,
    this.statutIn,
    this.methode,
    this.methodeIn,
    this.estAnnule,
    this.datePaiement,
    this.datePaiementStart,
    this.datePaiementEnd,
    this.createdAtStart,
    this.createdAtEnd,
    this.montantMin,
    this.montantMax,
    this.contratId,
    this.leaseId,
    this.sessionId,
    this.enregistreParId,
    this.chauffeurId,
  });

  Map<String, String> toQueryParameters() {
    final q = <String, String>{};

    void add(String key, Object? value) {
      if (value == null) return;
      final s = value.toString().trim();
      if (s.isEmpty) return;
      q[key] = s;
    }

    add('search', search);
    add('statut', statut);
    if (statutIn != null && statutIn!.isNotEmpty) {
      add('statut__in', statutIn!.join(','));
    }

    add('methode', methode);
    if (methodeIn != null && methodeIn!.isNotEmpty) {
      add('methode__in', methodeIn!.join(','));
    }

    if (estAnnule != null) {
      add('est_annule', estAnnule == true ? 'true' : 'false');
    }

    add('date_paiement', _dateOnly(datePaiement));
    add('date_paiement_start', _dateOnly(datePaiementStart));
    add('date_paiement_end', _dateOnly(datePaiementEnd));

    add('created_at_start', _dateOnly(createdAtStart));
    add('created_at_end', _dateOnly(createdAtEnd));

    add('montant_min', montantMin);
    add('montant_max', montantMax);

    add('contrat_id', contratId);
    add('lease_id', leaseId);
    add('session_id', sessionId);
    add('enregistre_par_id', enregistreParId);
    add('chauffeur_id', chauffeurId);

    return q;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal parsing helpers
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _map(Map data) {
  return data.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? _mapOrNull(dynamic value) {
  if (value is Map) return _map(value);
  return null;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();

  final cleaned = value.toString().trim();
  if (cleaned.isEmpty) return fallback;

  return int.tryParse(cleaned) ??
      double.tryParse(cleaned)?.toInt() ??
      fallback;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();

  final cleaned = value
      .toString()
      .trim()
      .replaceAll(' ', '')
      .replaceAll(',', '.');

  if (cleaned.isEmpty) return fallback;

  return double.tryParse(cleaned) ?? fallback;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final s = value.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? _nullableString(dynamic value) {
  final s = _asString(value);
  return s.isEmpty ? null : s;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;

  final s = value.toString().trim().toLowerCase();
  if (['true', '1', 'yes', 'oui'].contains(s)) return true;
  if (['false', '0', 'no', 'non'].contains(s)) return false;

  return fallback;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;

  final s = value.toString().trim();
  if (s.isEmpty) return null;

  return DateTime.tryParse(s);
}

String _dateOnly(dynamic value) {
  final d = _asDate(value);
  if (d == null) {
    final s = _asString(value);
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

int? _extractId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);

  if (value is Map) {
    return _asInt(value['id'], fallback: -1) == -1
        ? null
        : _asInt(value['id']);
  }

  return null;
}

String? _nestedString(dynamic source, List<String> keys) {
  final map = _mapOrNull(source);
  if (map == null) return null;

  for (final key in keys) {
    final value = map[key];
    final s = _nullableString(value);
    if (s != null) return s;
  }

  return null;
}

String _formatDate(DateTime date) {
  const months = [
    '',
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  return '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month]} '
      '${date.year}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}