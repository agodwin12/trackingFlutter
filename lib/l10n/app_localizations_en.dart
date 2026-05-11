// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Recouvrement';

  @override
  String get navHome => 'Home';

  @override
  String get navHistory => 'History';

  @override
  String get navProfile => 'Profile';

  @override
  String get loadingLeaseData => 'Loading your lease data...';

  @override
  String get retry => 'Retry';

  @override
  String get errorRequestTimedOut => 'Request timed out. Please retry.';

  @override
  String errorConnection(String error) {
    return 'Connection error: $error';
  }

  @override
  String errorFailedToLoadLeases(int code) {
    return 'Failed to load lease data ($code)';
  }

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirmTitle => 'Log out';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to log out?';

  @override
  String get cancel => 'Cancel';

  @override
  String get recouvrementTitle => 'RECOUVREMENT';

  @override
  String get proxymGroup => 'PROXYM GROUP';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusPartial => 'Partial';

  @override
  String get statusUnpaid => 'Unpaid';

  @override
  String get statusHoliday => 'Holiday';

  @override
  String get statusNoLease => 'No Lease';

  @override
  String get statusUpcoming => 'Upcoming';

  @override
  String get statTotalDue => 'Total Due';

  @override
  String get statTotalPaid => 'Total Paid';

  @override
  String get statUnpaid => 'Unpaid';

  @override
  String get summaryTitle => 'PAYMENT SUMMARY';

  @override
  String get localTime => 'LOCAL TIME';

  @override
  String get nextPayIn => 'NEXT PAY IN';

  @override
  String get hrsMinSec => 'hrs : min : sec';

  @override
  String get sectionTodayPayments => 'TODAY\'S PAYMENTS';

  @override
  String get sectionOutstandingPayments => 'OUTSTANDING PAYMENTS';

  @override
  String get pendingPayments => 'Pending payments';

  @override
  String get echeances => 'due dates';

  @override
  String get mainContract => 'Main contract';

  @override
  String get subContract => 'Sub-contract';

  @override
  String get payAll => 'Pay all';

  @override
  String get todayLease => 'TODAY\'S LEASE';

  @override
  String get due => 'Due:';

  @override
  String get paid => 'Paid:';

  @override
  String get remaining => 'Remaining:';

  @override
  String get tapToPayNow => 'Tap to pay now';

  @override
  String get unpaidLeasesTitle => 'Unpaid Leases';

  @override
  String unpaidLeasesPending(int count, String plural) {
    return '$count pending payment$plural';
  }

  @override
  String get pay => 'Pay';

  @override
  String contrat(int id) {
    return 'Contract #$id';
  }

  @override
  String get historyTitle => 'Lease History';

  @override
  String get historySubtitle => 'Calendar overview & payment records';

  @override
  String get tabCalendar => 'Calendar';

  @override
  String get tabRecords => 'Records';

  @override
  String get statDaysPaid => 'Days Paid';

  @override
  String get statMissed => 'Missed';

  @override
  String get statTotalPaidShort => 'Total Paid';

  @override
  String days(int n) {
    return '$n days';
  }

  @override
  String get allUpToDate => 'All payments are up to date!';

  @override
  String get nextPaymentDue => 'Next Payment Due';

  @override
  String get amount => 'Amount';

  @override
  String get legendPaid => 'Paid';

  @override
  String get legendUnpaid => 'Unpaid';

  @override
  String get legendPartial => 'Partial';

  @override
  String get legendToday => 'Today';

  @override
  String get detailExpected => 'Expected';

  @override
  String get detailPaid => 'Paid';

  @override
  String get detailRemaining => 'Remaining';

  @override
  String get detailReference => 'Reference';

  @override
  String get detailPaidAt => 'Paid at';

  @override
  String get detailMethod => 'Method';

  @override
  String payNowAmount(String amount) {
    return 'Pay XAF $amount now';
  }

  @override
  String get noRecordsYet => 'No records yet';

  @override
  String get allRecords => 'ALL RECORDS';

  @override
  String get summaryRecords => 'Records';

  @override
  String get summaryPaid => 'Paid';

  @override
  String get summaryUnpaid => 'Unpaid';

  @override
  String get summaryPartial => 'Partial';

  @override
  String get payLeaseTitle => 'Pay Lease';

  @override
  String get payLeaseSubtitle => 'Select leases to pay';

  @override
  String get allCaughtUp => 'All Caught Up!';

  @override
  String get noOutstandingLeases => 'You have no outstanding lease payments.';

  @override
  String get backToDashboard => 'Back to Dashboard';

  @override
  String get sectionOutstandingLeases => 'OUTSTANDING LEASES';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String leasesSelected(int count, String plural) {
    return '$count lease$plural selected';
  }

  @override
  String get totalToPay => 'Total to pay';

  @override
  String get sectionMobileMoneyNumber => 'MOBILE MONEY NUMBER';

  @override
  String get mobileMoneyNumber => 'Mobile Money Number';

  @override
  String get auto => 'Auto';

  @override
  String get sectionPaymentMethod => 'PAYMENT METHOD';

  @override
  String get mtnMobileMoney => 'MTN Mobile Money';

  @override
  String get mtnTagline => 'Pay with MTN MoMo';

  @override
  String get orangeMoney => 'Orange Money';

  @override
  String get orangeTagline => 'Pay with Orange Money';

  @override
  String get paygateInfo =>
      'PayGate will open inside the app. Keep your phone reachable for the payment prompt.';

  @override
  String get selectAtLeastOneLease => 'Select at least one lease';

  @override
  String get selectPaymentMethod => 'Select a payment method';

  @override
  String payVia(String amount, String provider) {
    return 'Pay XAF $amount via $provider';
  }

  @override
  String get closePaymentTitle => 'Close payment?';

  @override
  String get closePaymentMessage =>
      'If you close now your payment may not be confirmed. Are you sure?';

  @override
  String get stay => 'Stay';

  @override
  String get closeAnyway => 'Close anyway';

  @override
  String get failedToLoadPaymentPage => 'Failed to load payment page';

  @override
  String get checkConnectionRetry => 'Check your connection and try again.';

  @override
  String get goBack => 'Go Back';

  @override
  String get confirmingPayment => 'Confirming Payment';

  @override
  String waitingForProvider(String provider) {
    return 'Waiting for $provider to confirm.\nThis usually takes a few seconds.';
  }

  @override
  String checkingIn(int seconds, int attempt, int max) {
    return 'Checking in ${seconds}s (attempt $attempt/$max)';
  }

  @override
  String get doNotCloseApp =>
      'Please do not close the app.\nYour payment is being processed.';

  @override
  String get summaryAmount => 'Amount';

  @override
  String get summaryMethod => 'Method';

  @override
  String summaryLeases(int count, String plural) {
    return '$count payment$plural';
  }

  @override
  String get summaryReference => 'Reference';

  @override
  String get summaryStatus => 'Status';

  @override
  String get paymentConfirmed => 'Payment Confirmed!';

  @override
  String paymentConfirmedSubtitle(
      int count, String plural, String plural2, String provider) {
    return '$count lease$plural paid successfully via $provider.';
  }

  @override
  String get amountPaid => 'Amount Paid';

  @override
  String leasesConfirmed(int count, String plural) {
    return '$count confirmed';
  }

  @override
  String get confirmed => '✅ Confirmed';

  @override
  String get stillProcessing => 'Still Processing';

  @override
  String get stillProcessingSubtitle =>
      'We could not confirm your payment yet.\nThis can take a few minutes depending on your network.';

  @override
  String get whatToDo => 'What to do:';

  @override
  String get timeoutStep1 => '1. Check your SMS for a payment confirmation';

  @override
  String get timeoutStep2 => '2. Open the History tab to verify the status';

  @override
  String get timeoutStep3 => '3. If unsure, contact your partner';

  @override
  String get checkHistory => 'Check History';

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileSubtitle => 'Account info & contract';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get changePasswordSubtitle => 'Update your security credentials';

  @override
  String get sectionAccountInfo => 'ACCOUNT INFORMATION';

  @override
  String get fieldFullName => 'Full Name';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldPhone => 'Phone';

  @override
  String get fieldCity => 'City';

  @override
  String get fieldQuartier => 'Quartier';

  @override
  String get sectionContractDetails => 'CONTRACT DETAILS';

  @override
  String contractHeader(int id, String frequency) {
    return 'Contract #$id · $frequency';
  }

  @override
  String get repaymentProgress => 'Repayment Progress';

  @override
  String paidAmount(String amount) {
    return 'Paid: XAF $amount';
  }

  @override
  String remainingAmount(String amount) {
    return 'Remaining: XAF $amount';
  }

  @override
  String get contractTotalAmount => 'Total Amount';

  @override
  String get contractPerPayment => 'Per Payment';

  @override
  String get contractFrequency => 'Frequency';

  @override
  String get contractStartDate => 'Start Date';

  @override
  String get contractEndDate => 'End Date';

  @override
  String get contractNextDue => 'Next Due';

  @override
  String get contractRegisteredBy => 'Registered By';

  @override
  String get sectionSettings => 'SETTINGS';

  @override
  String get settingsChangePassword => 'Change Password';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signOutConfirmTitle => 'Sign Out';

  @override
  String get signOutConfirmMessage => 'Are you sure you want to sign out?';

  @override
  String get passwordHint =>
      'Use at least 8 characters with a mix of letters and numbers.';

  @override
  String get sectionUpdatePassword => 'UPDATE PASSWORD';

  @override
  String get fieldCurrentPassword => 'Current Password';

  @override
  String get fieldNewPassword => 'New Password';

  @override
  String get fieldConfirmPassword => 'Confirm New Password';

  @override
  String get updatePassword => 'Update Password';

  @override
  String get passwordUpdated => 'Password updated successfully.';

  @override
  String get errorFillAllFields => 'Please fill in all password fields.';

  @override
  String get errorPasswordMismatch => 'New passwords do not match.';

  @override
  String get errorPasswordTooShort => 'Password must be at least 8 characters.';

  @override
  String get appVersion => 'Fleetra v1.0.0 — PROXYM GROUP';

  @override
  String get languageToggleLabel => 'Language';
}
