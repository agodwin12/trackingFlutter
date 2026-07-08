// lib/src/screens/recouvrement/history/recouvrement_transaction_model.dart
//
// Model for GET {PARTNER_API_URL}/transactions/  (DRF paginated)
// Defensive parsing throughout: montant_total arrives as a string ("3500.00"),
// date_validation is null on failed transactions, and any unexpected statut
// value falls back to `unknown` instead of crashing the screen.

enum TransactionStatus { valide, echec, pending, unknown }

class PaymentTransaction {
  final int id;
  final String reference;
  final String rawStatus;
  final TransactionStatus status;
  final double amount;
  final String telephone;
  final DateTime? dateValidation; // local time, null for failed/pending
  final DateTime createdAt;       // local time

  const PaymentTransaction({
    required this.id,
    required this.reference,
    required this.rawStatus,
    required this.status,
    required this.amount,
    required this.telephone,
    required this.dateValidation,
    required this.createdAt,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['statut'] ?? '').toString().toUpperCase().trim();

    TransactionStatus status;
    switch (rawStatus) {
      case 'VALIDE':
        status = TransactionStatus.valide;
        break;
      case 'ECHEC':
        status = TransactionStatus.echec;
        break;
      case 'EN_ATTENTE':
      case 'PENDING':
      case 'EN_COURS':
        status = TransactionStatus.pending;
        break;
      default:
        status = TransactionStatus.unknown;
    }

    // montant_total is a stringified decimal — never cast, always tryParse.
    final amount =
        double.tryParse((json['montant_total'] ?? '').toString()) ?? 0.0;

    // Timestamps carry a +01:00 offset; parse then convert to device local.
    final createdAt =
        DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0);

    DateTime? dateValidation;
    final rawValidation = json['date_validation'];
    if (rawValidation != null) {
      dateValidation =
          DateTime.tryParse(rawValidation.toString())?.toLocal();
    }

    return PaymentTransaction(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      reference: (json['reference'] ?? '').toString(),
      rawStatus: rawStatus,
      status: status,
      amount: amount,
      telephone: (json['telephone'] ?? '').toString(),
      dateValidation: dateValidation,
      createdAt: createdAt,
    );
  }

  bool get isSuccess => status == TransactionStatus.valide;
  bool get isFailed => status == TransactionStatus.echec;
}

/// One page of the DRF-paginated /transactions/ response.
class TransactionPage {
  final int count;
  final bool hasNext;
  final List<PaymentTransaction> results;

  const TransactionPage({
    required this.count,
    required this.hasNext,
    required this.results,
  });

  factory TransactionPage.fromJson(Map<String, dynamic> json) {
    final rawResults = (json['results'] as List?) ?? const [];
    final parsed = <PaymentTransaction>[];
    for (final item in rawResults) {
      if (item is Map<String, dynamic>) {
        try {
          parsed.add(PaymentTransaction.fromJson(item));
        } catch (_) {
          // One malformed row must never kill the whole page.
        }
      }
    }
    return TransactionPage(
      count: (json['count'] is int)
          ? json['count'] as int
          : int.tryParse('${json['count']}') ?? parsed.length,
      // NOTE: we only use `next` as a boolean. We never follow the URL it
      // contains — the backend returns it as plain http:// which would be
      // blocked as cleartext. Page N+1 is rebuilt from our own https base.
      hasNext: json['next'] != null,
      results: parsed,
    );
  }
}