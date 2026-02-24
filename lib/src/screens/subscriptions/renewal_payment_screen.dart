// lib/src/screens/subscription/renewal_payment_screen.dart

import 'package:flutter/material.dart';
import '../../core/utility/app_theme.dart';
import '../settings/models/subscription_plan.dart';

class RenewalPaymentScreen extends StatefulWidget {
  final int userId;
  final int vehicleId;
  final String currentExpiryDate;

  const RenewalPaymentScreen({
    Key? key,
    required this.userId,
    required this.vehicleId,
    required this.currentExpiryDate,
  }) : super(key: key);

  @override
  State<RenewalPaymentScreen> createState() => _RenewalPaymentScreenState();
}

class _RenewalPaymentScreenState extends State<RenewalPaymentScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Selection State
  SubscriptionPlan? _selectedPlan;
  String? _selectedPaymentMethod;

  // Status State
  bool _isProcessing = false;
  String _paymentStatus = 'pending';

  void _nextStep() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _processPayment();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 3));
    setState(() {
      _isProcessing = false;
      _paymentStatus = 'success';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentStatus == 'success') return _buildSuccessScreen();
    if (_paymentStatus == 'failed') return _buildFailureScreen();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _buildStepIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (int page) => setState(() => _currentStep = page),
                  children: [
                    _buildPlanSelectionStep(),
                    _buildPaymentMethodStep(),
                    _buildReviewStep(),
                  ],
                ),
              ),
              _buildBottomNavigation(),
            ],
          ),
        ),
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Renew Subscription', style: AppTypography.h3.copyWith(fontSize: 18)),
      centerTitle: true,
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.symmetric(vertical: AppSizes.spacingM, horizontal: AppSizes.spacingL),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Center(child: _stepText("Plan", 0))),
              Expanded(child: Center(child: _stepText("Payment", 1))),
              Expanded(child: Center(child: _stepText("Review", 2))),
            ],
          ),
          SizedBox(height: AppSizes.spacingS),
          LinearProgressIndicator(
            value: (_currentStep + 1) / 3,
            backgroundColor: AppColors.border,
            color: AppColors.primary,
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  Widget _stepText(String label, int index) {
    bool isActive = _currentStep == index;
    return Text(
      label,
      style: AppTypography.caption.copyWith(
        color: isActive ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // --- STEP 1: PLAN SELECTION ---
  Widget _buildPlanSelectionStep() {
    return ListView(
      padding: EdgeInsets.all(AppSizes.spacingL),
      children: [
        _buildCurrentStatusCard(),
        SizedBox(height: AppSizes.spacingXL),
        Text('Choose a Plan', style: AppTypography.h3.copyWith(fontSize: 18)),
        SizedBox(height: AppSizes.spacingM),
        ...staticPlans.map((plan) => _buildPlanCard(plan)).toList(),
      ],
    );
  }

  Widget _buildCurrentStatusCard() {
    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, color: AppColors.primary),
          SizedBox(width: AppSizes.spacingM),
          Expanded( // Added Expanded to prevent text overflow
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Expiry', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                Text(widget.currentExpiryDate, style: AppTypography.body2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    bool isSelected = _selectedPlan?.id == plan.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan),
      child: Container(
        margin: EdgeInsets.only(bottom: AppSizes.spacingM),
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            SizedBox(width: AppSizes.spacingM),
            Expanded( // Use Expanded to give the column room and prevent horizontal push
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.nameEn, style: AppTypography.subtitle1.copyWith(fontWeight: FontWeight.bold)),
                  if (plan.savingsEn != null)
                    Text(plan.savingsEn!, style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Text('${plan.price.toInt()} XAF', style: AppTypography.subtitle1.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // --- STEP 2: PAYMENT METHOD ---
  Widget _buildPaymentMethodStep() {
    return Padding(
      padding: EdgeInsets.all(AppSizes.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Payment Method', style: AppTypography.h3.copyWith(fontSize: 18)),
          SizedBox(height: AppSizes.spacingL),
          _buildMethodTile('momo', 'MTN Mobile Money', 'https://brandlogovector.com/wp-content/uploads/2023/08/MTN-Logo-PNG.png'),
          SizedBox(height: AppSizes.spacingM),
          _buildMethodTile('orange', 'Orange Money', 'https://brandlogovector.com/wp-content/uploads/2020/07/Orange-Logo.png'),
        ],
      ),
    );
  }

  Widget _buildMethodTile(String id, String title, String logoUrl) {
    bool isSelected = _selectedPaymentMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedPaymentMethod = id),
      child: Container(
        padding: EdgeInsets.all(AppSizes.spacingL),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Image.network(
              logoUrl,
              width: 40,
              height: 40,
              errorBuilder: (context, error, stackTrace) => Icon(Icons.account_balance_wallet, color: AppColors.primary),
            ),
            SizedBox(width: AppSizes.spacingM),
            Expanded(child: Text(title, style: AppTypography.subtitle1)),
            if (isSelected) Icon(Icons.check_circle, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // --- STEP 3: REVIEW ---
  Widget _buildReviewStep() {
    return ListView( // Changed from Padding/Column to ListView to handle overflow if keyboard pops up or screen is small
      padding: EdgeInsets.all(AppSizes.spacingL),
      children: [
        Text('Confirm Details', style: AppTypography.h3.copyWith(fontSize: 18)),
        SizedBox(height: AppSizes.spacingL),
        Container(
          padding: EdgeInsets.all(AppSizes.spacingL),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppSizes.radiusM)),
          child: Column(
            children: [
              _buildReviewRow('Vehicle ID', '#${widget.vehicleId}'),
              Divider(height: 32),
              _buildReviewRow('Plan', _selectedPlan?.nameEn ?? 'Not Selected'),
              _buildReviewRow('Price', '${_selectedPlan?.price.toInt() ?? 0} XAF'),
              _buildReviewRow('Method', _selectedPaymentMethod == 'momo' ? 'MTN MoMo' : 'Orange Money'),
              Divider(height: 32),
              _buildReviewRow('Total Amount', '${_selectedPlan?.price.toInt() ?? 0} XAF', isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8), // Increased vertical padding for better tap targets
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // Align to top in case of long values
        children: [
          Text(label, style: isTotal ? AppTypography.subtitle1.copyWith(fontWeight: FontWeight.bold) : AppTypography.body2),
          SizedBox(width: 10), // Small spacer
          Flexible( // Crucial to prevent horizontal overflow
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: isTotal ? AppTypography.h3.copyWith(color: AppColors.primary, fontSize: 20) : AppTypography.subtitle1,
            ),
          ),
        ],
      ),
    );
  }

  // --- FEEDBACK OVERLAYS ---
  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: AppSizes.spacingXL),
          padding: EdgeInsets.all(AppSizes.spacingXL),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppSizes.radiusL)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: AppSizes.spacingL),
              Text('Processing Payment...', style: AppTypography.subtitle1, textAlign: TextAlign.center),
              SizedBox(height: 4),
              Text('Please do not close the app', style: AppTypography.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppSizes.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 100),
            SizedBox(height: AppSizes.spacingL),
            Text('Payment Successful!', style: AppTypography.h2, textAlign: TextAlign.center),
            SizedBox(height: AppSizes.spacingM),
            Text('Your subscription has been renewed. It may take a few minutes for the status to update.',
                textAlign: TextAlign.center, style: AppTypography.body2),
            SizedBox(height: AppSizes.spacingXL),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 54)),
              child: const Text('Return to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureScreen() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppSizes.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_rounded, color: AppColors.error, size: 100),
            SizedBox(height: AppSizes.spacingL),
            Text('Payment Failed', style: AppTypography.h2, textAlign: TextAlign.center),
            SizedBox(height: AppSizes.spacingM),
            Text('We couldn\'t process your transaction. Please try again or use a different method.',
                textAlign: TextAlign.center, style: AppTypography.body2),
            SizedBox(height: AppSizes.spacingXL),
            ElevatedButton(
              onPressed: () => setState(() => _paymentStatus = 'pending'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 54)),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    bool canContinue = (_currentStep == 0 && _selectedPlan != null) ||
        (_currentStep == 1 && _selectedPaymentMethod != null) ||
        (_currentStep == 2);

    return Container(
      padding: EdgeInsets.all(AppSizes.spacingL),
      decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))]
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
                child: OutlinedButton(
                    onPressed: _prevStep,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                    child: const Text('Back')
                )
            ),
          if (_currentStep > 0) SizedBox(width: AppSizes.spacingM),
          Expanded(
            child: ElevatedButton(
              onPressed: canContinue ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(0, 50)
              ),
              child: Text(_currentStep == 2 ? 'Pay Now' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}