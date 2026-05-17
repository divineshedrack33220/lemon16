import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class WebSocketService {
  static WebSocketChannel? _channel;
  static final StreamController<Map<String, dynamic>> _controller = StreamController<Map<String, dynamic>>.broadcast();
  static String get wsUrl {
    return ApiService.baseUrl.replaceFirst('http', 'ws').replaceAll('/api', '/ws');
  }

  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  static Future<void> connect() async {
    if (_channel != null) return;
    final token = await ApiService.getToken();
    if (token == null) return;
    
    _channel = WebSocketChannel.connect(Uri.parse('$wsUrl?token=$token'));
    _channel!.stream.listen(
      (data) {
        try {
          final message = jsonDecode(data);
          _controller.add(message);
        } catch (e) {
          print('Error decoding WebSocket message: $e');
        }
      },
      onDone: () {
        print('WebSocket closed');
        _channel = null;
      },
      onError: (error) {
        print('WebSocket error: $error');
        _channel = null;
      },
    );
  }

  static void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  static void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
