import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_en_place/services/voice_client.dart';

void main() {
  group('VoiceClient.parseEvent', () {
    test('parses transcript event', () {
      final event = VoiceClient.parseEvent({
        'type': 'transcript',
        'text': 'hello world',
        'is_final': true,
      });
      expect(event, isA<TranscriptEvent>());
      final t = event as TranscriptEvent;
      expect(t.text, 'hello world');
      expect(t.isFinal, true);
    });

    test('parses transcript event with is_final defaulting to false', () {
      final event = VoiceClient.parseEvent({
        'type': 'transcript',
        'text': 'partial',
      });
      expect(event, isA<TranscriptEvent>());
      expect((event as TranscriptEvent).isFinal, false);
    });

    test('parses agent_response event', () {
      final event = VoiceClient.parseEvent({
        'type': 'agent_response',
        'text': 'About 30 seconds.',
      });
      expect(event, isA<AgentResponseEvent>());
      expect((event as AgentResponseEvent).text, 'About 30 seconds.');
    });

    test('parses tool_call event', () {
      final event = VoiceClient.parseEvent({
        'type': 'tool_call',
        'tool': 'set_timer',
        'args': {'label': 'eggs', 'seconds': 180},
      });
      expect(event, isA<ToolCallEvent>());
      final t = event as ToolCallEvent;
      expect(t.tool, 'set_timer');
      expect(t.args['label'], 'eggs');
      expect(t.args['seconds'], 180);
    });

    test('parses tool_call event without args', () {
      final event = VoiceClient.parseEvent({
        'type': 'tool_call',
        'tool': 'mark_step_complete',
      });
      expect(event, isA<ToolCallEvent>());
      final t = event as ToolCallEvent;
      expect(t.tool, 'mark_step_complete');
      expect(t.args, isEmpty);
    });

    test('parses tts_start event', () {
      final event = VoiceClient.parseEvent({'type': 'tts_start'});
      expect(event, isA<TTSStartEvent>());
    });

    test('parses tts_end event', () {
      final event = VoiceClient.parseEvent({'type': 'tts_end'});
      expect(event, isA<TTSEndEvent>());
    });

    test('parses error event', () {
      final event = VoiceClient.parseEvent({
        'type': 'error',
        'code': 'auth_failed',
        'message': 'Invalid token',
      });
      expect(event, isA<ErrorEvent>());
      final e = event as ErrorEvent;
      expect(e.code, 'auth_failed');
      expect(e.message, 'Invalid token');
    });

    test('returns ErrorEvent for unknown type', () {
      final event = VoiceClient.parseEvent({'type': 'banana'});
      expect(event, isA<ErrorEvent>());
      final e = event as ErrorEvent;
      expect(e.code, 'unknown');
      expect(e.message, contains('banana'));
    });

    test('AudioEvent holds Uint8List data', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final event = AudioEvent(data);
      expect(event.data, data);
    });

    test('DisconnectedEvent is a VoiceEvent', () {
      final event = DisconnectedEvent();
      expect(event, isA<VoiceEvent>());
    });
  });
}
