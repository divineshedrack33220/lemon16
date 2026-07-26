import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'auth_service.dart';

class WebSocketService {
  static WebSocketChannel? _channel;
  static Timer? _reconnectTimer;
  static int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  static String get wsUrl {
    return ApiService.baseUrl
        .replaceFirst('http', 'ws')
        .replaceAll('/api', '/ws');
  }

  static Stream<Map<String, dynamic>> get stream => _controller.stream;
  static bool get isConnected => _channel != null;

  static Future<void> connect() async {
    if (_channel != null) return;
    final token = await ApiService.getToken();
    if (token == null) return;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _channel!.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            _controller.add(message);
            _reconnectAttempts = 0;
          } catch (e) {
            // ignore malformed messages
          }
        },
        onDone: () {
          _channel = null;
          _scheduleReconnect();
        },
        onError: (error) {
          _channel = null;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  static void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    _reconnectTimer?.cancel();

    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 30));
    _reconnectAttempts++;

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  static void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  static void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = _maxReconnectAttempts;
    _channel?.sink.close();
    _channel = null;
  }

  static void resetReconnect() {
    _reconnectAttempts = 0;
  }
}
