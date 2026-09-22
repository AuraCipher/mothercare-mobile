/// Backend base URL — REQUIRED at build time via `--dart-define`.
/// No default is bundled: every build must pass the target backend origin.
///   Android emulator: --dart-define=API_BASE_URL=http://10.0.2.2:5000
///   iOS simulator:    --dart-define=API_BASE_URL=http://127.0.0.1:5000
///   Physical device:  --dart-define=API_BASE_URL=http://YOUR_LAN_IP:5000
///   Release:          --dart-define-from-file=dart_defines/production.json
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// True when the build received `--dart-define=API_BASE_URL=...`.
  static bool get isConfigured => apiBaseUrl.isNotEmpty;

  static const String appName = 'Mother Care';

  /// Set `--dart-define=PUSH_ENABLED=true` after Firebase is configured.
  static const bool pushEnabled = bool.fromEnvironment(
    'PUSH_ENABLED',
    defaultValue: false,
  );

  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get hasFirebaseOptions =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}
