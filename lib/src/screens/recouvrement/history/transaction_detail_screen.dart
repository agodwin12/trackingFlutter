// lib/src/screens/recouvrement/history/transaction_detail_screen.dart
//
// Detail view for a single mobile-money transaction. Built entirely from the
// list item (no detail endpoint exists on the partner API), so it is pushed
// with the already-parsed PaymentTransaction.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model/recouvremenet_transaction_model.dart';

// ── Colours (same palette as recouvrement_history.dart) ──────────────────────
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

class TransactionDetailScreen extends StatelessWidget {
  final PaymentTransaction transaction;

  const TransactionDetailScreen({Key? key, required this.transaction})
      : super(key: key);

  bool _fr(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fr';

  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  String _two(int n) => n.toString().padLeft(2, '0');

  String _fmtDate(BuildContext context, DateTime d) {
    final fr = _fr(context);
    final months = fr
        ? ['', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
      'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc']
        : ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  String _fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  Color _statusColor(TransactionStatus s) {
    switch (s) {
      case TransactionStatus.valide:
        return _green;
      case TransactionStatus.echec:
        return _red;
      case TransactionStatus.pending:
      case TransactionStatus.unknown:
        return _yellow;
    }
  }

  String _statusLabel(BuildContext context, PaymentTransaction tx) {
    final fr = _fr(context);
    switch (tx.status) {
      case TransactionStatus.valide:
        return fr ? 'Réussi' : 'Successful';
      case TransactionStatus.echec:
        return fr ? 'Échoué' : 'Failed';
      case TransactionStatus.pending:
        return fr ? 'En attente' : 'Pending';
      case TransactionStatus.unknown:
        return tx.rawStatus.isEmpty ? '—' : tx.rawStatus;
    }
  }

  IconData _statusIcon(TransactionStatus s) {
    switch (s) {
      case TransactionStatus.valide:
        return Icons.check_circle_rounded;
      case TransactionStatus.echec:
        return Icons.cancel_rounded;
      case TransactionStatus.pending:
      case TransactionStatus.unknown:
        return Icons.hourglass_top_rounded;
    }
  }

  void _copyReference(BuildContext context) {
    Clipboard.setData(ClipboardData(text: transaction.reference));
    final fr = _fr(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _border),
      ),
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _green, size: 16),
        const SizedBox(width: 8),
        Text(fr ? 'Référence copiée' : 'Reference copied',
            style: const TextStyle(color: _textPrimary, fontSize: 13)),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fr    = _fr(context);
    final tx    = transaction;
    final color = _statusColor(tx.status);
    final label = _statusLabel(context, tx);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(context, fr),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(children: [
                _buildAmountHeader(context, tx, color, label),
                const SizedBox(height: 16),
                _buildInfoCard(context, tx, fr),
                if (tx.isFailed) ...[
                  const SizedBox(height: 14),
                  _buildFailedNote(fr),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool fr) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: const BoxDecoration(
      color: _bgSubtle,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textMuted, size: 16),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fr ? 'Détails de la transaction' : 'Transaction details',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary)),
                Text(fr ? 'Paiement Mobile Money' : 'Mobile Money payment',
                    style:
                    const TextStyle(fontSize: 11, color: _textMuted)),
              ])),
    ]),
  );

  Widget _buildAmountHeader(BuildContext context, PaymentTransaction tx,
      Color color, String label) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(_statusIcon(tx.status), color: color, size: 28),
          ),
          const SizedBox(height: 14),
          Text('XAF ${_fmt(tx.amount)}',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      );

  Widget _buildInfoCard(
      BuildContext context, PaymentTransaction tx, bool fr) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fr ? 'INFORMATIONS' : 'INFORMATION',
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _textMuted,
                letterSpacing: 1.5)),
        const SizedBox(height: 14),

        // Reference — tappable, with explicit copy affordance. Drivers need
        // this when disputing a payment with support.
        GestureDetector(
          onTap: () => _copyReference(context),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fr ? 'Référence' : 'Reference',
                    style:
                    const TextStyle(fontSize: 12, color: _textMuted)),
                Flexible(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(tx.reference,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded,
                        color: _orange, size: 14),
                  ]),
                ),
              ]),
        ),
        const SizedBox(height: 12),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 12),

        _row(fr ? 'Téléphone' : 'Phone',
            tx.telephone.isEmpty ? '—' : '+${tx.telephone}'),
        const SizedBox(height: 10),
        _row(fr ? 'Initié le' : 'Initiated on',
            '${_fmtDate(context, tx.createdAt)}  ·  ${_fmtTime(tx.createdAt)}'),
        const SizedBox(height: 10),
        _row(
          fr ? 'Validé le' : 'Validated on',
          tx.dateValidation != null
              ? '${_fmtDate(context, tx.dateValidation!)}  ·  ${_fmtTime(tx.dateValidation!)}'
              : '—',
          valueColor: tx.dateValidation != null ? _green : _textMuted,
        ),
        const SizedBox(height: 10),
        _row('ID', '#${tx.id}'),
      ]),
    );
  }

  Widget _buildFailedNote(bool fr) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _red.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _red.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: _red, size: 18),
      const SizedBox(width: 12),

    ]),
  );

  Widget _row(String label, String value, {Color? valueColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: _textMuted)),
      Flexible(
        child: Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _textPrimary),
            textAlign: TextAlign.end),
      ),
    ],
  );
}