import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, [this.message]);

  final int statusCode;
  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  String? token;

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool authorize = false,
  }) async {
    final request = await _http.openUrl(method, _uri(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    if (authorize && token != null && token!.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    headers?.forEach(request.headers.set);
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }

    final response = await request.close();
    final text = await utf8.decodeStream(response);
    Map<String, dynamic> data = <String, dynamic>{};
    if (text.trim().isNotEmpty) {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        (data['error'] ?? 'http_${response.statusCode}').toString(),
        data['message']?.toString(),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> info() => _request('GET', '/api/app/info');

  Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _request(
      'POST',
      '/api/app/auth/login',
      body: {'username': username, 'password': password},
    );
    token = data['token']?.toString();
    return data;
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/api/app/auth/logout', authorize: true);
    } finally {
      token = null;
    }
  }

  Future<Map<String, dynamic>> store() =>
      _request('GET', '/api/app/store', authorize: true);

  Future<Map<String, dynamic>> createPairing() =>
      _request('POST', '/api/app/pairings');

  Future<Map<String, dynamic>> pairingStatus(
    String pairingId,
    String secret,
  ) =>
      _request(
        'GET',
        '/api/app/pairings/$pairingId',
        headers: {'X-Pairing-Secret': secret},
      );

  Future<Map<String, dynamic>> claimPairing({
    required String code,
    required String seasonId,
  }) =>
      _request(
        'POST',
        '/api/app/pairings/claim',
        authorize: true,
        body: {'code': code, 'seasonId': seasonId},
      );

  Future<Map<String, dynamic>> live(
    String code, {
    String? liveKey,
  }) =>
      _request(
        'GET',
        '/api/app/live/$code',
        authorize: liveKey == null,
        headers: liveKey == null ? null : {'X-Live-Key': liveKey},
      );

  Future<void> stopLive(String code) async {
    await _request(
      'POST',
      '/api/app/live/$code/stop',
      authorize: true,
    );
  }

  void close() => _http.close(force: true);
}
