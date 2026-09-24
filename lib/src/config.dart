class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nogames.mycarolina.ru',
  );

  static String mediaUrl(String path) {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base$path';
  }

  static String wsUrl({
    required String code,
    required String role,
    required String key,
  }) {
    final base = Uri.parse(apiBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws/app',
      queryParameters: {
        'code': code,
        'role': role,
        'key': key,
      },
    ).toString();
  }
}
