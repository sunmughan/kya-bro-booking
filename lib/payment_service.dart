import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'config.dart';

/// Razorpay checkout, full order flow.
///
/// Primary flow (Cloud Functions deployed): the app asks the
/// `createRazorpayOrder` function for a server-side order (the secret never
/// leaves the server), opens checkout with that order id, then asks the
/// `verifyRazorpayPayment` function to verify the signature. Only a
/// server-verified payment becomes `paid`; anything else stays
/// `pending_payment` or becomes `failed`. A payment is never marked paid
/// from the client alone.
///
/// Fallback (functions not deployed yet): if a key id is configured but no
/// order can be created, checkout opens directly and the booking keeps
/// `pending_payment` with the payment ids recorded, so the owner can confirm
/// it manually in the admin app. No payment is faked as successful.
class PaymentService {
  final Razorpay _razorpay = Razorpay();
  void Function(String paymentId, String orderId, String signature)? onSuccess;
  void Function(String message)? onFailure;

  void init() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      onSuccess?.call(
        r.paymentId ?? '',
        r.orderId ?? '',
        r.signature ?? '',
      );
    });
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse r) => onFailure?.call(r.message ?? 'Payment failed'));
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET,
        (_) => onFailure?.call('External wallet not supported'));
  }

  void dispose() => _razorpay.clear();

  /// Key id actually in effect: the owner-set key from Firestore settings
  /// (admin Payments tab) wins, otherwise the build-time --dart-define.
  static String? effectiveKeyId(String? settingsKeyId) {
    final s = (settingsKeyId ?? '').trim();
    if (s.isNotEmpty && s.startsWith('rzp_')) return s;
    if (AppConfig.razorpayConfigured) return AppConfig.razorpayKeyId;
    return null;
  }

  /// Opens checkout against a server-created order. Returns false when no
  /// usable key id exists.
  bool openCheckoutWithOrder({
    required String keyId,
    required String orderId,
    required double amountInr,
    required String bookingId,
    required String name,
  }) {
    if (!keyId.startsWith('rzp_')) return false;
    _razorpay.open({
      'key': keyId,
      'order_id': orderId,
      'amount': (amountInr * 100).round(),
      'currency': 'INR',
      'name': 'Kya Bro booking',
      'description': 'Booking $bookingId',
      'prefill': {'name': name},
    });
    return true;
  }

  /// Direct checkout without a server order (fallback only, see class doc).
  bool openCheckoutDirect({
    required String keyId,
    required double amountInr,
    required String bookingId,
    required String name,
  }) {
    if (!keyId.startsWith('rzp_')) return false;
    _razorpay.open({
      'key': keyId,
      'amount': (amountInr * 100).round(),
      'currency': 'INR',
      'name': 'Kya Bro booking',
      'description': 'Booking $bookingId',
      'prefill': {'name': name},
    });
    return true;
  }
}
