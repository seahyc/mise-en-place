import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

class VoiceClient {
  WebSocketChannel? _channel;
  final _events = StreamController<VoiceEvent>.broadcast();
  Stream<VoiceEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String sessionId, String token, String baseUrl) async {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/voice'));

    // Send session_start
    _channel!.sink.add(jsonEncode({
      'type': 'session_start',
      'session_id': sessionId,
      'token': token,
    }));

    _channel!.stream.listen(
      (data) {
        if (data is Uint8List) {
          _events.add(AudioEvent(data));
        } else if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          _events.add(parseEvent(json));
        }
      },
      onDone: () => _events.add(DisconnectedEvent()),
      onError: (Object e) =>
          _events.add(ErrorEvent('connection', e.toString())),
    );
  }

  void sendAudio(Uint8List frame) => _channel?.sink.add(frame);

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _events.close();
  }

  /// Parses a JSON message into a [VoiceEvent].
  /// Visible for testing.
  static VoiceEvent parseEvent(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'transcript':
        return TranscriptEvent(
          json['text'] as String? ?? '',
          json['is_final'] as bool? ?? false,
        );
      case 'agent_response':
        return AgentResponseEvent(json['text'] as String? ?? '');
      case 'tool_call':
        return ToolCallEvent(
          json['tool'] as String? ?? '',
          Map<String, dynamic>.from(
              json['args'] as Map<String, dynamic>? ?? {}),
        );
      case 'tts_start':
        return TTSStartEvent();
      case 'tts_end':
        return TTSEndEvent();
      case 'error':
        return ErrorEvent(
          json['code'] as String? ?? '',
          json['message'] as String? ?? '',
        );
      default:
        return ErrorEvent('unknown', 'Unknown event type: ${json['type']}');
    }
  }
}

// ── Voice Events ──────────────────────────────────────────────────────────────

sealed class VoiceEvent {}

class TranscriptEvent extends VoiceEvent {
  TranscriptEvent(this.text, this.isFinal);
  final String text;
  final bool isFinal;
}

class AgentResponseEvent extends VoiceEvent {
  AgentResponseEvent(this.text);
  final String text;
}

class ToolCallEvent extends VoiceEvent {
  ToolCallEvent(this.tool, this.args);
  final String tool;
  final Map<String, dynamic> args;
}

class TTSStartEvent extends VoiceEvent {}

class TTSEndEvent extends VoiceEvent {}

class AudioEvent extends VoiceEvent {
  AudioEvent(this.data);
  final Uint8List data;
}

class ErrorEvent extends VoiceEvent {
  ErrorEvent(this.code, this.message);
  final String code;
  final String message;
}

class DisconnectedEvent extends VoiceEvent {}
