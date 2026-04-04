// lib/src/screens/subscriptions/payment_history_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utility/app_theme.dart';
import '../../services/payment_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Translation helper
// ─────────────────────────────────────────────────────────────────────────────
String _t(String lang, String en, String fr) => lang == 'fr' ? fr : en;

class PaymentHistoryScreen extends StatefulWidget {
  final String? selectedLanguage;

  const PaymentHistoryScreen({Key? key, this.selectedLanguage}) : super(key: key);

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  static const Color fleetraOrange = Color(0xFFFF6B35);

  bool _isLoading = true;
  List<Map<String, dynamic>> _payments = [];
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _initLang();
    _loadHistory();
  }

  Future<void> _initLang() async {
    if (widget.selectedLanguage != null) {
      setState(() => _lang = widget.selectedLanguage!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('language') ?? 'en';
    if (mounted) setState(() => _lang = saved);
  }

  Future<void> _loadHistory() async {
    try {
      final payments = await PaymentService.getPaymentHistory();
      if (mounted) {
        setState(() {
          _payments = payments;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading payment history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS': return const Color(0xFF10B981);
      case 'PENDING': return Colors.orange;
      case 'FAILED':  return Colors.red;
      case 'EXPIRED': return Colors.grey;
      default:        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS': return Icons.check_circle_rounded;
      case 'PENDING': return Icons.hourglass_empty_rounded;
      case 'FAILED':  return Icons.cancel_rounded;
      case 'EXPIRED': return Icons.timer_off_rounded;
      default:        return Icons.info_outline_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'SUCCESS': return _t(_lang, 'Success',  'Réussi');
      case 'PENDING': return _t(_lang, 'Pending',  'En attente');
      case 'FAILED':  return _t(_lang, 'Failed',   'Échoué');
      case 'EXPIRED': return _t(_lang, 'Expired',  'Expiré');
      default:        return status;
    }
  }

  String _methodLabel(String method, String? provider) {
    if (method.toUpperCase() == 'CASH') {
      return _t(_lang, 'Cash', 'Espèces');
    }
    const labels = {'MTNMOMO': 'MTN', 'CMORANGEOM': 'Orange'};
    final providerLabel =
    provider != null ? (labels[provider] ?? provider) : null;
    final walletLabel = _t(_lang, 'E-Wallet', 'Portefeuille');
    return providerLabel != null ? '$walletLabel • $providerLabel' : walletLabel;
  }

  IconData _getMethodIcon(String method) {
    switch (method.toUpperCase()) {
      case 'MOBILE_MONEY': return Icons.account_balance_wallet_rounded;
      case 'CASH':         return Icons.payments_outlined;
      default:             return Icons.payment_rounded;
    }
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return 'N/A';
    try {
      final date = DateTime.parse(dateVal.toString()).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}  '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: fleetraOrange))
                  : _payments.isEmpty
                  ? _buildEmptyState()
                  : _buildPaymentList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _payments.length;
    final txLabel = count == 1
        ? _t(_lang, '1 transaction', '1 transaction')
        : _t(_lang, '$count transactions', '$count transactions');

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(_lang, 'Payment History', 'Historique des paiements'),
                  style: AppTypography.h3.copyWith(fontSize: 18),
                ),
                Text(
                  txLabel,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentList() {
    return RefreshIndicator(
      color: fleetraOrange,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        itemBuilder: (context, index) =>
            _buildPaymentCard(_payments[index]),
      ),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final status      = payment['status']        as String? ?? 'PENDING';
    final method      = payment['method']        as String? ?? 'MOBILE_MONEY';
    final provider    = payment['provider']      as String?;
    final plan        = payment['plan']          as Map<String, dynamic>?;
    final vehicleName = payment['vehicle_name']  as String? ??
        _t(_lang, 'Unknown Vehicle', 'Véhicule inconnu');
    final plate       = payment['vehicle_plate'] as String? ?? '';
    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: method icon / plan + vehicle / amount ─────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: fleetraOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getMethodIcon(method),
                      color: fleetraOrange, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan?['name'] ??
                            _t(_lang, 'Subscription', 'Abonnement'),
                        style: AppTypography.subtitle1.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _methodLabel(method, provider),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${payment['amount']} ${payment['currency'] ?? 'XAF'}',
                  style: AppTypography.subtitle1.copyWith(
                      fontSize: 15, color: AppColors.primary),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Vehicle row ────────────────────────────────────────────────
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.directions_car_rounded,
                      size: 15, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vehicleName,
                      style: AppTypography.body2.copyWith(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  if (plate.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        plate,
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),

            // ── Bottom row: date / status badge ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(payment['created_at']),
                      style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(status),
                          size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        _statusLabel(status),
                        style: AppTypography.caption.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧾', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            _t(_lang, 'No payments yet', 'Aucun paiement pour le moment'),
            style: AppTypography.subtitle1.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _t(_lang,
                'Your payment history will appear here',
                'Votre historique de paiements apparaîtra ici'),
            style: AppTypography.caption
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}