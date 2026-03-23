import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/voice_client.dart';

final voiceClientProvider = Provider<VoiceClient>((ref) {
  final client = VoiceClient();
  ref.onDispose(client.dispose);
  return client;
});

final voiceEventsProvider = StreamProvider<VoiceEvent>((ref) {
  return ref.watch(voiceClientProvider).events;
});
