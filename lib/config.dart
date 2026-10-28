// App configuration. PLACEHOLDERS ONLY — no real keys or secrets live here.
//
// Razorpay key ID flow (confirmed by the owner): the key ID is NEVER in
// this repo. The owner enters it in the admin app's Payments tab, it is
// saved as the `content/settings` Firestore document, and the booking app
// reads it from Firebase at runtime. The build-time --dart-define below is
// only a last-resort fallback for builds made before the admin entry
// exists. The Razorpay SECRET never appears here, in Firestore, or in
// either app: it lives only as a Cloud Functions secret, used server-side
// for order creation and signature verification.
// Firebase itself is configured the supported way: run
// `flutterfire configure` in the Firebase console step (see README) and it
// replaces the placeholder FirebaseOptions below. Until then Firebase
// initialisation fails gracefully and the app shows honest TBD/empty
// states instead of fake data.

class AppConfig {
  // Razorpay key id. The literal below is a placeholder, not a key.
  static const razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'YOUR_RAZORPAY_KEY_ID_HERE',
  );
  static bool get razorpayConfigured =>
      razorpayKeyId.isNotEmpty &&
      razorpayKeyId != 'YOUR_RAZORPAY_KEY_ID_HERE' &&
      razorpayKeyId.startsWith('rzp_');

  // Firebase web/API values, all placeholders until the console step.
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'YOUR_FIREBASE_API_KEY_HERE',
  );
  static const firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: 'YOUR_FIREBASE_APP_ID_HERE',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'YOUR_FIREBASE_PROJECT_ID_HERE',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: 'YOUR_FIREBASE_SENDER_ID_HERE',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'YOUR_FIREBASE_STORAGE_BUCKET_HERE',
  );
  static bool get firebaseConfigured =>
      !firebaseApiKey.contains('YOUR_') &&
      !firebaseAppId.contains('YOUR_') &&
      !firebaseProjectId.contains('YOUR_');
}
