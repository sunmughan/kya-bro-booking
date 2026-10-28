import 'package:cloud_functions/cloud_functions.dart';

/// Typed wrappers around the Cloud Functions in functions/index.js.
/// Every call throws a human-readable message when the backend is not
/// deployed yet, so the UI can say so honestly instead of faking a result.
/// No secrets pass through here: the functions read their own secrets.
class FunctionsService {
  static FirebaseFunctions get _fn => FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    try {
      final res = await _fn.httpsCallable(name).call(data);
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      return {};
    } on FirebaseFunctionsException catch (e) {
      throw Exception(_readable(e));
    } catch (e) {
      throw Exception('Backend not reachable ($name): $e');
    }
  }

  static String _readable(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'Backend function not deployed yet. Deploy Cloud Functions (see README), then try again.';
      case 'unauthenticated':
        return 'Backend rejected the call. Check the function deployment.';
      case 'failed-precondition':
        return e.message ?? 'Backend is not configured yet (missing secret or setting).';
      case 'invalid-argument':
        return e.message ?? 'Invalid payment details.';
      default:
        return e.message ?? 'Backend error (${e.code}).';
    }
  }

  /// Asks the server to create a Razorpay order for this booking. The
  /// server checks the amount against the booking's stored total.
  static Future<Map<String, dynamic>> createRazorpayOrder({
    required String bookingId,
  }) =>
      _call('createRazorpayOrder', {'bookingId': bookingId});

  /// Asks the server to verify the Razorpay signature. Returns
  /// {'verified': true} only when the server confirmed it.
  static Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String bookingId,
    required String paymentId,
    required String orderId,
    required String signature,
  }) =>
      _call('verifyRazorpayPayment', {
        'bookingId': bookingId,
        'paymentId': paymentId,
        'orderId': orderId,
        'signature': signature,
      });

  /// Sends a TEST email only, to the SMTP test recipient configured in the
  /// admin app (SMTP account sunmughan@gmail.com). Never used for booking
  /// mail; booking mail goes to the owner email via onBookingCreated.
  /// Optional transient credentials: when the owner types an SMTP password
  /// in the admin SMTP screen for a test, it is passed here for that one
  /// send only and is never stored anywhere (not in Firestore, not in the
  /// repo). With no transient credentials, the function uses the stored
  /// SMTP config plus the SMTP_PASS function secret.
  static Future<Map<String, dynamic>> sendTestMail([
    Map<String, dynamic>? transientSmtp,
  ]) =>
      _call('sendTestMail', transientSmtp == null ? {} : {'smtp': transientSmtp});

  /// Refreshes creator stats from the Instagram Graph API. Works when
  /// the creator connected via the admin app's Connect Instagram button
  /// (server-held token) or when the owner set the legacy
  /// INSTAGRAM_ACCESS_TOKEN secret; otherwise returns
  /// {'status': 'needs_token'} and writes nothing. Never invents numbers.
  static Future<Map<String, dynamic>> refreshCreatorStats() =>
      _call('refreshCreatorStats', {});

  /// Returns {'url': <Facebook OAuth login URL>} for the Connect
  /// Instagram button. The server builds the URL from the owner-entered
  /// Meta App ID + callback URL in content/settings. No token is ever
  /// returned to the app: the browser login hands the auth code straight
  /// to the server callback, which exchanges it server-side.
  static Future<Map<String, dynamic>> getInstagramConnectUrl() =>
      _call('getInstagramConnectUrl', {});

  /// Deletes the server-held Instagram token and marks the connection
  /// disconnected. The token never passes through the app.
  static Future<Map<String, dynamic>> disconnectInstagram() =>
      _call('disconnectInstagram', {});
}
