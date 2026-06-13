// lib/src/screens/recouvrement/dashboard/recouvremenet_model.dart

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ContratStatut    { actif, suspendu, solde, contentieux, unknown }
enum LeaseStatut      { paid, partial, unpaid, suspended, contentieux }
enum ContratFrequence { journalier, hebdomadaire, mensuel, unknown }

// ── TypeContrat (from /type-contrats/) ───────────────────────────────────────

class TypeContrat {
  final int    id;
  final String libelle;
  final String code;
  final bool   estPrincipal;

  const TypeContrat({
    required this.id,
    required this.libelle,
    required this.code,
    required this.estPrincipal,
  });

  factory TypeContrat.fromJson(Map<String, dynamic> json) => TypeContrat(
    id:           (json['id'] as num?)?.toInt() ?? 0,
    libelle:      json['libelle']       as String? ?? '',
    code:         json['code']          as String? ?? '',
    estPrincipal: json['est_principal'] as bool?   ?? false,
  );
}

// ── SousContrat (child contracts embedded in /contrats/ response) ─────────────

class SousContrat {
  final int      id;
  final int?     parentId;
  final String   reference;
  final int      typeContratId;
  final String   typeContratLibelle;
  final double   montantTotal;
  final double   montantRestant;
  final double   montantPaye;
  final double   montantParPaiement;
  final ContratFrequence frequence;
  final LeaseStatut      statut;
  final String   dateEcheance;
  final Map<String, dynamic> specificites;

  const SousContrat({
    required this.id,
    this.parentId,
    required this.reference,
    required this.typeContratId,
    required this.typeContratLibelle,
    required this.montantTotal,
    required this.montantRestant,
    required this.montantPaye,
    required this.montantParPaiement,
    required this.frequence,
    required this.statut,
    required this.dateEcheance,
    required this.specificites,
  });

  bool get isPaid       => statut == LeaseStatut.paid;
  bool get isPartial    => statut == LeaseStatut.partial;
  bool get isUnpaid     => statut == LeaseStatut.unpaid;
  bool get isActionable => isUnpaid || isPartial;

  factory SousContrat.fromJson(
      Map<String, dynamic> json,
      Map<int, String> typeLibelles, {
        int? parentId,
      }) {
    final total   = _parseDouble(json['montant_total']);
    final restant = _parseDouble(json['montant_restant'] ?? json['montant_total']);
    final paye    = (total - restant).clamp(0.0, double.infinity);
    final typeId  = (json['type_contrat'] as num?)?.toInt() ?? 0;

    return SousContrat(
      id:                 (json['id'] as num?)?.toInt() ?? 0,
      parentId:           parentId ?? (json['parent'] as num?)?.toInt(),
      reference:          json['reference']          as String? ?? '',
      typeContratId:      typeId,
      typeContratLibelle: typeLibelles[typeId] ??
          json['type_contrat_libelle'] as String? ?? 'Sous-contrat #$typeId',
      montantTotal:       total,
      montantRestant:     restant,
      montantPaye:        paye,
      montantParPaiement: _parseDouble(json['montant_par_paiement']),
      frequence:          _parseFrequence(json['frequence'] as String?),
      statut:             _normaliseToLeaseStatut(
          json['statut'] as String? ?? '', total, restant),
      dateEcheance:       (json['prochaine_echeance'] as String?)?.substring(0, 10) ?? '',
      specificites:       _parseSpecificites(json['specificites']),
    );
  }
}

// ── Lease (from /leases/ endpoint) ───────────────────────────────────────────

class Lease {
  final int    id;
  final int    compteId;
  final int    contratId;
  final String chauffeurNomComplet;
  final String typeContratLibelle;
  final String dateEcheance;
  final double montantAttendu;
  final double montantPaye;
  final double resteAPayer;
  final String statut;

  const Lease({
    required this.id,
    required this.compteId,
    required this.contratId,
    required this.chauffeurNomComplet,
    required this.typeContratLibelle,
    required this.dateEcheance,
    required this.montantAttendu,
    required this.montantPaye,
    required this.resteAPayer,
    required this.statut,
  });

  bool get isPaid       => statut == 'PAYE';
  bool get isPartial    => statut == 'PARTIELLEMENT_PAYE';
  bool get isUnpaid     => statut == 'NON_PAYE';
  bool get isActionable => !isPaid;

  factory Lease.fromJson(Map<String, dynamic> json) {
    final montantAttendu = double.tryParse(json['montant_attendu']?.toString() ?? '0') ?? 0;
    final resteAPayer    = double.tryParse(json['reste_a_payer']?.toString()   ?? '0') ?? 0;

    return Lease(
      id                  : json['id'] as int,
      compteId            : json['compte_id'] as int,
      contratId           : json['contrat_id'] as int,
      chauffeurNomComplet : json['chauffeur_nom_complet']?.toString() ?? '',
      typeContratLibelle  : json['type_contrat_libelle']?.toString() ?? '',
      dateEcheance        : json['date_echeance']?.toString() ?? '',
      montantAttendu      : montantAttendu,
      montantPaye         : double.tryParse(json['montant_paye']?.toString() ?? '0') ?? 0,
      resteAPayer         : resteAPayer,
      // ← normalise: API may return 'ACTIF' instead of 'NON_PAYE'/'PARTIELLEMENT_PAYE'
      statut              : _normaliseLeaseStatut(
        json['statut']?.toString() ?? 'NON_PAYE',
        montantAttendu,
        resteAPayer,
      ),
    );
  }
}

// ── Contrat (from /contrats/ — for immatriculation + sous_contrats) ───────────

class Contrat {
  final int      id;
  final int?     parentId;
  final String   reference;
  final String   immatriculation;
  final String?  vin;
  final double   montantTotal;
  final double   montantRestant;
  final ContratStatut    statut;
  final ContratFrequence frequenceEnum;
  final String   dateDebut;
  final String   dateFin;
  final String   prochaineEcheance;
  final Map<String, dynamic> specificites;
  final List<SousContrat>    sousContrats;

  const Contrat({
    required this.id,
    this.parentId,
    required this.reference,
    required this.immatriculation,
    this.vin,
    required this.montantTotal,
    required this.montantRestant,
    required this.statut,
    required this.frequenceEnum,
    required this.dateDebut,
    required this.dateFin,
    required this.prochaineEcheance,
    required this.specificites,
    required this.sousContrats,
  });

  String get frequence {
    switch (frequenceEnum) {
      case ContratFrequence.journalier:   return 'JOURNALIER';
      case ContratFrequence.hebdomadaire: return 'HEBDOMADAIRE';
      case ContratFrequence.mensuel:      return 'MENSUEL';
      default:                            return '';
    }
  }

  bool get isActif       => statut == ContratStatut.actif;
  bool get isSousContrat => parentId != null;

  factory Contrat.fromJson(
      Map<String, dynamic> json,
      Map<int, String> typeLibelles,
      ) {
    final parentRaw = json['parent'];
    final int? parsedParentId = parentRaw is num
        ? parentRaw.toInt()
        : (parentRaw is String ? int.tryParse(parentRaw) : null);

    final rawSous = json['sous_contrats'] as List<dynamic>? ?? [];

    return Contrat(
      id:                (json['id'] as num?)?.toInt() ?? 0,
      parentId:          parsedParentId,
      reference:         json['reference']       as String? ?? '',
      immatriculation:   json['immatriculation'] as String? ?? '',
      vin:               json['vin']             as String?,
      montantTotal:      _parseDouble(json['montant_total']),
      montantRestant:    _parseDouble(json['montant_restant'] ?? json['montant_total']),
      statut:            _parseContratStatut(json['statut'] as String?),
      frequenceEnum:     _parseFrequence(json['frequence'] as String?),
      dateDebut:         (json['date_debut']         as String?)?.substring(0, 10) ?? '',
      dateFin:           (json['date_fin']           as String?)?.substring(0, 10) ?? '',
      prochaineEcheance: (json['prochaine_echeance'] as String?)?.substring(0, 10) ?? '',
      specificites:      _parseSpecificites(json['specificites']),
      sousContrats:      rawSous.map((e) {
        final m = e as Map<String, dynamic>;
        return SousContrat.fromJson(
          m,
          typeLibelles,
          parentId: (json['id'] as num?)?.toInt(),
        );
      }).toList(),
    );
  }
}

// ── Parse helpers ─────────────────────────────────────────────────────────────

double _parseDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num)  return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

Map<String, dynamic> _parseSpecificites(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is String)               return {'note': v};
  return {};
}

ContratFrequence _parseFrequence(String? v) {
  switch (v) {
    case 'JOURNALIER':   return ContratFrequence.journalier;
    case 'HEBDOMADAIRE': return ContratFrequence.hebdomadaire;
    case 'MENSUEL':      return ContratFrequence.mensuel;
    default:             return ContratFrequence.unknown;
  }
}

ContratStatut _parseContratStatut(String? v) {
  switch (v) {
    case 'ACTIF':       return ContratStatut.actif;
    case 'SUSPENDU':    return ContratStatut.suspendu;
    case 'SOLDE':       return ContratStatut.solde;
    case 'CONTENTIEUX': return ContratStatut.contentieux;
    default:            return ContratStatut.unknown;
  }
}

// Used by SousContrat (enum-based statut)
LeaseStatut _normaliseToLeaseStatut(String s, double total, double restant) {
  switch (s) {
    case 'SOLDE':       return LeaseStatut.paid;
    case 'SUSPENDU':    return LeaseStatut.suspended;
    case 'CONTENTIEUX': return LeaseStatut.contentieux;
    case 'ACTIF':
      if (restant <= 0)    return LeaseStatut.paid;
      if (restant < total) return LeaseStatut.partial;
      return LeaseStatut.unpaid;
    default:            return LeaseStatut.unpaid;
  }
}

// Used by Lease (string-based statut) — normalises ACTIF and pass-through values
String _normaliseLeaseStatut(String s, double total, double restant) {
  switch (s) {
    case 'SOLDE':       return 'PAYE';
    case 'SUSPENDU':    return 'SUSPENDU';
    case 'CONTENTIEUX': return 'CONTENTIEUX';
    case 'ACTIF':
      if (restant <= 0)    return 'PAYE';
      if (restant < total) return 'PARTIELLEMENT_PAYE';
      return 'NON_PAYE';

    case 'PAYE':
    case 'PARTIELLEMENT_PAYE':
    case 'NON_PAYE':
      return s;
    default:
      return 'NON_PAYE';
  }
}