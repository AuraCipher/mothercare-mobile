/// Backend base URL — override per device:
///   Android emulator: http://10.0.2.2:5000
///   iOS simulator:    http://127.0.0.1:5000
///   Physical device:  http://YOUR_LAN_IP:5000
///
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

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
