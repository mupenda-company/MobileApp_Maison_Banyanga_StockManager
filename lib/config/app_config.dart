class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String loginPath = '/api/mobile/login';

  static const String clientsPath = '/api/mobile/clients';
  static const String clientQrPath = '/api/mobile/client/qr';
  static const String missionPath = '/api/mobile/mission';
  static const String ventePath = '/api/mobile/vente';

  static const String salesPath = '/api/mobile/ventes';
}
