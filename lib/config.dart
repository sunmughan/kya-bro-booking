// App configuration. PLACEHOLDERS ONLY — no real keys or secrets live here.
// Pass real values at build time with --dart-define, never by editing a
// secret into this file, e.g.:
//   flutter build apk --dart-define=RAZORPAY_KEY_ID=rzp_live_xxxx \
//                     --dart-define=FIREBASE_API_KEY=xxxx ...
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
