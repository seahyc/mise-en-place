import 'package:flutter_test/flutter_test.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'helpers/testable_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Happy Path - Session Start with AgentId', () {
    test(
      'successfully starts session and transitions through states',
      () async {
        final statuses = <ConversationStatus>[];
        String? connectedConversationId;

        final client = TestableConversationClient(
          callbacks: ConversationCallbacks(
            onStatusChange: ({required status}) {
              statuses.add(status);
            },
            onConnect: ({required conversationId}) {
              connectedConversationId = conversationId;
            },
          ),
        );

        // Initial state
        expect(client.status, ConversationStatus.disconnected);
        expect(client.isMuted, true);
        expect(client.conversationId, null);

        // Start session with agentId
        await client.startSession(
          agentId: 'test-agent-123',
          userId: 'user-456',
        );

        // Verify state transitions
        expect(statuses, [
          ConversationStatus.connecting,
          ConversationStatus.connected,
        ]);

        // Verify final state
        expect(client.status, ConversationStatus.connected);
        expect(client.conversationId, isNotNull);
        expect(connectedConversationId, equals(client.conversationId));
        expect(client.isMuted, false);

        await client.endSession();
        client.dispose();
      },
    );

    test('successfully starts session with token', () async {
      final statuses = <ConversationStatus>[];

      final client = TestableConversationClient(
        callbacks: ConversationCallbacks(
          onStatusChange: ({required status}) {
            statuses.add(status);
          },
        ),
      );

      // Start session with token
      await client.startSession(
        conversationToken: 'custom-token-xyz',
        userId: 'user-789',
      );

      // Verify state transitions
      expect(statuses, [
        ConversationStatus.connecting,
        ConversationStatus.connected,
      ]);

      expect(client.status, ConversationStatus.connected);

      await client.endSession();
      client.dispose();
    });

    test('starts session with full configuration', () async {
      final events = <String>[];

      final client = TestableConversationClient(
        callbacks: ConversationCallbacks(
          onStatusChange: ({required status}) {
            events.add('status:${status.name}');
          },
          onConnect: ({required conversationId}) {
            events.add('connected:$conversationId');
          },
        ),
      );

      final overrides = ConversationOverrides(
        agent: AgentOverrides(
          firstMessage: 'Hello! How can I help you?',
          prompt: 'You are a helpful assistant',
          temperature: 0.7,
        ),
        tts: TtsOverrides(voiceId: 'voice-123', stability: 0.5),
      );

      await client.startSession(
        agentId: 'test-agent',
        userId: 'user-123',
        overrides: overrides,
        dynamicVariables: {'user_name': 'Alice', 'tier': 'premium'},
      );

      expect(events, contains('status:connecting'));
      expect(events, contains('status:connected'));
      expect(events, contains('connected:test-conversation-123'));
      expect(client.status, ConversationStatus.connected);

      await client.endSession();
      client.dispose();
    });
  });

  group('Happy Path - Messaging During Session', () {
    test('sends and receives messages while connected', () async {
      final messages = <String>[];
      final sentMessages = <Map<String, dynamic>>[];

      final mockLiveKit = MockLiveKitManager();

      final client = TestableConversationClient(
        liveKitManager: mockLiveKit,
        callbacks: ConversationCallbacks(
          onMessage: ({required message, required source}) {
            messages.add('${source.name}:$message');
          },
        ),
      );

      // Listen to sent messages
      mockLiveKit.messagesStream.listen(sentMessages.add);

      await client.startSession(agentId: 'test-agent');

      // Send user message
      client.sendUserMessage('Hello, agent!');

      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages, isNotEmpty);
      expect(sentMessages.last['type'], 'user_message');
      expect(sentMessages.last['text'], 'Hello, agent!');
      expect(messages, contains('user:Hello, agent!'));

      // Simulate agent response
      client.simulateAgentMessage('Hi! How can I help?');
      expect(messages, contains('ai:Hi! How can I help?'));

      await client.endSession();
      client.dispose();
    });

    test('sends contextual updates', () async {
      final sentMessages = <Map<String, dynamic>>[];
      final mockLiveKit = MockLiveKitManager();

      final client = TestableConversationClient(liveKitManager: mockLiveKit);

      mockLiveKit.messagesStream.listen(sentMessages.add);
      await client.startSession(conversationToken: 'test-token');

      client.sendContextualUpdate('User viewing product page');

      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages.last['type'], 'contextual_update');
      expect(sentMessages.last['text'], 'User viewing product page');

      await client.endSession();
      client.dispose();
    });

    test('sends user activity signals', () async {
      final sentMessages = <Map<String, dynamic>>[];
      final mockLiveKit = MockLiveKitManager();

      final client = TestableConversationClient(liveKitManager: mockLiveKit);

      mockLiveKit.messagesStream.listen(sentMessages.add);
      await client.startSession(conversationToken: 'test-token');

      client.sendUserActivity();

      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages.last['type'], 'user_activity');

      await client.endSession();
      client.dispose();
    });

    test('sends feedback when available', () async {
      final sentMessages = <Map<String, dynamic>>[];
      final mockLiveKit = MockLiveKitManager();

      final client = TestableConversationClient(liveKitManager: mockLiveKit);

      mockLiveKit.messagesStream.listen(sentMessages.add);
      await client.startSession(conversationToken: 'test-token');

      // Simulate feedback becoming available
      client.simulateFeedbackAvailable();
      expect(client.canSendFeedback, true);

      // Send positive feedback
      client.sendFeedback(isPositive: true);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(sentMessages.last['type'], 'feedback');
      expect(sentMessages.last['score'], 'like');

      await client.endSession();
      client.dispose();
    });
  });

  group('Happy Path - Mode Changes', () {
    test('detects when agent starts and stops speaking', () async {
      final modes = <ConversationMode>[];

      final client = TestableConversationClient(
        callbacks: ConversationCallbacks(
          onModeChange: ({required mode}) {
            modes.add(mode);
          },
        ),
      );

      await client.startSession(agentId: 'test-agent');

      // Initially listening
      expect(client.isSpeaking, false);

      // Agent starts speaking
      client.simulateAgentSpeaking();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(modes, contains(ConversationMode.speaking));
      expect(client.isSpeaking, true);

      // Agent stops speaking
      client.simulateAgentStoppedSpeaking();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(modes, contains(ConversationMode.listening));
      expect(client.isSpeaking, false);

      await client.endSession();
      client.dispose();
    });
  });

  group('Happy Path - Audio Controls', () {
    test('mutes and unmutes microphone during session', () async {
      final client = TestableConversationClient();

      await client.startSession(agentId: 'test-agent');

      expect(client.isMuted, false); // Unmuted when connected

      // Mute
      await client.setMicMuted(true);
      expect(client.isMuted, true);

      // Unmute
      await client.setMicMuted(false);
      expect(client.isMuted, false);

      // Toggle
      await client.toggleMute();
      expect(client.isMuted, true);

      await client.toggleMute();
      expect(client.isMuted, false);

      await client.endSession();
      client.dispose();
    });
  });

  group('Happy Path - Session Lifecycle', () {
    test('completes full lifecycle: start, interact, end', () async {
      final events = <String>[];
      final messages = <String>[];

      final client = TestableConversationClient(
        callbacks: ConversationCallbacks(
          onStatusChange: ({required status}) {
            events.add('status:${status.name}');
          },
          onConnect: ({required conversationId}) {
            events.add('connect:$conversationId');
          },
          onDisconnect: (details) {
            events.add('disconnect:${details.reason}');
          },
          onMessage: ({required message, required source}) {
            messages.add('${source.name}:$message');
          },
          onModeChange: ({required mode}) {
            events.add('mode:${mode.name}');
          },
        ),
      );

      // Start
      await client.startSession(agentId: 'test-agent', userId: 'user-123');

      expect(events, contains('status:connecting'));
      expect(events, contains('status:connected'));
      expect(events, contains('connect:test-conversation-123'));

      // Interact
      client.sendUserMessage('Hello');
      expect(messages, contains('user:Hello'));

      client.simulateAgentSpeaking();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, contains('mode:speaking'));

      client.simulateAgentMessage('Hi there!');
      expect(messages, contains('ai:Hi there!'));

      client.simulateAgentStoppedSpeaking();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(events, contains('mode:listening'));

      // End
      await client.endSession();
      expect(events, contains('status:disconnecting'));
      expect(events, contains('status:disconnected'));
      expect(events, contains('disconnect:Session ended by user'));
      expect(client.status, ConversationStatus.disconnected);
      expect(client.conversationId, null);

      client.dispose();
    });

    test('handles multiple sessions sequentially', () async {
      final statuses = <ConversationStatus>[];

      final client = TestableConversationClient(
        callbacks: ConversationCallbacks(
          onStatusChange: ({required status}) {
            statuses.add(status);
          },
        ),
      );

      // First session
      await client.startSession(agentId: 'agent-1');
      expect(client.status, ConversationStatus.connected);

      await client.endSession();
      expect(client.status, ConversationStatus.disconnected);

      // Second session
      await client.startSession(agentId: 'agent-2');
      expect(client.status, ConversationStatus.connected);

      await client.endSession();
      expect(client.status, ConversationStatus.disconnected);

      // Verify state transitions for both sessions
      expect(statuses, [
        ConversationStatus.connecting,
        ConversationStatus.connected,
        ConversationStatus.disconnecting,
        ConversationStatus.disconnected,
        ConversationStatus.connecting,
        ConversationStatus.connected,
        ConversationStatus.disconnecting,
        ConversationStatus.disconnected,
      ]);

      client.dispose();
    });
  });

  group('Happy Path - Listener Notifications', () {
    test('notifies listeners on state changes', () async {
      int notifyCount = 0;

      final client = TestableConversationClient();

      void listener() {
        notifyCount++;
      }

      client.addListener(listener);

      // Start session triggers notifications
      final initialCount = notifyCount;
      await client.startSession(agentId: 'test-agent');
      expect(notifyCount, greaterThan(initialCount));

      // Mute triggers notification
      final beforeMute = notifyCount;
      await client.setMicMuted(true);
      expect(notifyCount, greaterThan(beforeMute));

      // Speaking state change triggers notification
      final beforeSpeaking = notifyCount;
      client.simulateAgentSpeaking();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(notifyCount, greaterThan(beforeSpeaking));

      client.removeListener(listener);
      await client.endSession();
      client.dispose();
    });
  });
}
