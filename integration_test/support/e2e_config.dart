/// Live E2E against a running MCS backend + demo seed.
abstract final class E2eConfig {
  static const live = bool.fromEnvironment('E2E_LIVE', defaultValue: false);

  static const apiUrl = String.fromEnvironment(
    'E2E_API_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );
}
