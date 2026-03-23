import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal WebSocket client for session-level events.
///
/// Receives JSON events like `step_completed`, `session_started`, etc.
/// Primary session updates come through the voice pipeline's tool calls;
/// this provides a fallback / sync channel.
class SessionWsClient {
  WebSocketChannel? _channel;
  final _events = StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  void connect(String sessionId, String baseUrl) {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(
      Uri.parse('$wsUrl/ws/session/$sessionId'),
    );

    _channel!.stream.listen(
      (data) {
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String? ?? '';
          _events.add(SessionEvent(type: type, data: json));
        }
      },
      onDone: () => _events.add(
        const SessionEvent(type: 'disconnected', data: {}),
      ),
      onError: (Object e) => _events.add(
        SessionEvent(type: 'error', data: {'message': e.toString()}),
      ),
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _events.close();
  }
}

class SessionEvent {
  const SessionEvent({required this.type, required this.data});
  final String type;
  final Map<String, dynamic> data;
}
