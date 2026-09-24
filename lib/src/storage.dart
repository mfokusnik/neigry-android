import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredLiveSession {
  const StoredLiveSession({
    required this.code,
    required this.key,
  });

  final String code;
  final String key;
}

class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const _roleKey = 'device_role';
  static const _tokenKey = 'auth_token';
  static const _controllerCodeKey = 'controller_live_code';
  static const _controllerKeyKey = 'controller_live_key';
  static const _stageCodeKey = 'stage_live_code';
  static const _stageKeyKey = 'stage_live_key';

  String _doneQueueKey(String code) => 'pending_done_$code';

  Future<String?> readDeviceRole() => _storage.read(key: _roleKey);

  Future<void> saveDeviceRole(String role) => _storage.write(key: _roleKey, value: role);

  Future<void> clearDeviceRole() => _storage.delete(key: _roleKey);

  Future<String?> readAuthToken() => _storage.read(key: _tokenKey);

  Future<void> saveAuthToken(String token) async {
    if (token.isEmpty) return;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearAuthToken() => _storage.delete(key: _tokenKey);

  Future<void> saveControllerSession({required String code, required String key}) async {
    await _storage.write(key: _controllerCodeKey, value: code);
    await _storage.write(key: _controllerKeyKey, value: key);
  }

  Future<StoredLiveSession?> readControllerSession() async {
    final values = await Future.wait([
      _storage.read(key: _controllerCodeKey),
      _storage.read(key: _controllerKeyKey),
    ]);
    final code = values[0] ?? '';
    final key = values[1] ?? '';
    if (code.isEmpty || key.isEmpty) return null;
    return StoredLiveSession(code: code, key: key);
  }

  Future<void> clearControllerSession() async {
    final code = await _storage.read(key: _controllerCodeKey);
    await _storage.delete(key: _controllerCodeKey);
    await _storage.delete(key: _controllerKeyKey);
    if (code != null && code.isNotEmpty) {
      await clearDoneQueue(code);
    }
  }

  Future<void> saveStageSession({required String code, required String key}) async {
    await _storage.write(key: _stageCodeKey, value: code);
    await _storage.write(key: _stageKeyKey, value: key);
  }

  Future<StoredLiveSession?> readStageSession() async {
    final values = await Future.wait([
      _storage.read(key: _stageCodeKey),
      _storage.read(key: _stageKeyKey),
    ]);
    final code = values[0] ?? '';
    final key = values[1] ?? '';
    if (code.isEmpty || key.isEmpty) return null;
    return StoredLiveSession(code: code, key: key);
  }

  Future<void> clearStageSession() async {
    await _storage.delete(key: _stageCodeKey);
    await _storage.delete(key: _stageKeyKey);
  }

  Future<List<Map<String, dynamic>>> readDoneQueue(String code) async {
    final raw = await _storage.read(key: _doneQueueKey(code));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveDoneQueue(String code, List<Map<String, dynamic>> queue) async {
    if (queue.isEmpty) {
      await clearDoneQueue(code);
      return;
    }
    await _storage.write(key: _doneQueueKey(code), value: jsonEncode(queue));
  }

  Future<void> clearDoneQueue(String code) => _storage.delete(key: _doneQueueKey(code));
}
