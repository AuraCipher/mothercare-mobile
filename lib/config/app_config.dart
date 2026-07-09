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
}
