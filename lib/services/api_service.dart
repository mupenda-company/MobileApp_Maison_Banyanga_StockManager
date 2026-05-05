import 'package:logis_agent/api/api_client.dart';
import 'package:logis_agent/config/app_config.dart';
import 'package:logis_agent/services/auth_service.dart';

class ApiService {
  static final ApiService instance = ApiService._();

  ApiService._();

  ApiClient createClient() {
    return ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenProvider: AuthService.instance.getAccessToken,
    );
  }
}
