import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'config.dart';

/// Razorpay checkout. The key comes only from --dart-define (see config.dart).
/// With no real key configured, checkout is skipped gracefully and the
/// booking is saved with paymentStatus = pending_payment. That is the one
/// key-dependent step; it is never faked as a successful payment.
class PaymentService {
  final Razorpay _razorpay = Razorpay();
  void Function()? onSuccess;
  void Function(String message)? onFailure;

  void init() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse r) => onSuccess?.call());
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse r) => onFailure?.call(r.message ?? 'Payment failed'));
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET,
        (_) => onFailure?.call('External wallet not supported'));
  }

  void dispose() => _razorpay.clear();

  /// Returns true if checkout was opened, false if no key is configured
  /// (caller then saves the booking as pending payment).
  bool openCheckout({
    required double amountInr,
    required String bookingId,
    required String name,
  }) {
    if (!AppConfig.razorpayConfigured) return false;
    _razorpay.open({
      'key': AppConfig.razorpayKeyId,
      'amount': (amountInr * 100).round(),
      'currency': 'INR',
      'name': 'Kya Bro booking',
      'description': 'Booking $bookingId',
      'prefill': {'name': name},
    });
    return true;
  }
}
