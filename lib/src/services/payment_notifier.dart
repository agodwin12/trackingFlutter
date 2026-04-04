// lib/src/services/payment_notifier.dart


import 'package:flutter/foundation.dart';

class PaymentNotifier extends ChangeNotifier {
  PaymentNotifier._();
  static final PaymentNotifier instance = PaymentNotifier._();

  bool _paymentSucceeded = false;

  /// True if a payment succeeded since the last time [consume] was called.
  bool get paymentSucceeded => _paymentSucceeded;

  /// Called by PaymentPendingScreen (or PaymentSuccessScreen for CASH)
  /// after the webhook confirms SUCCESS and vehicles_list is refreshed.
  void notifySuccess() {
    _paymentSucceeded = true;
    notifyListeners();
  }

  /// Called by the dashboard after it has handled the reload.
  /// Resets the flag so it doesn't fire again on the next rebuild.
  void consume() {
    _paymentSucceeded = false;
  }
}