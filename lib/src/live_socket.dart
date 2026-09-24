import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LiveSocket {
  LiveSocket(this.url);

  final String url;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connectFuture;
  bool _disposed = false;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connection =
      StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get connection => _connection.stream;
  bool get connected => _socket != null;

  Future<void> connect() {
    if (_disposed) return Future<void>.value();
    final existing = _connectFuture;
    if (existing != null) return existing;
    final future = _connectInternal();
    _connectFuture = future;
    return future.whenComplete(() {
      if (identical(_connectFuture, future)) _connectFuture = null;
    });
  }

  Future<void> _connectInternal() async {
    await closeSocketOnly();
    final socket = await WebSocket.connect(url).timeout(const Duration(seconds: 12));
    if (_disposed) {
      await socket.close();
      return;
    }
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    _connection.add(true);
    _subscription = socket.listen(
      (dynamic raw) {
        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is Map) {
            _messages.add(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {
          // Ignore malformed messages. The server protocol is JSON-only.
        }
      },
      onDone: () {
        _socket = null;
        _connection.add(false);
      },
      onError: (_) {
        _socket = null;
        _connection.add(false);
      },
      cancelOnError: false,
    );
  }

  bool send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null) return false;
    try {
      socket.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> closeSocketOnly() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // Best effort shutdown.
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await closeSocketOnly();
    await _messages.close();
    await _connection.close();
  }
}
