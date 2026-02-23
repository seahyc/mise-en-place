import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/enums.dart';

/// Service for generating and playing atmospheric music using ElevenLabs Music API
class MusicService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Get music prompt based on cuisine type
  String _getMusicPrompt(Cuisine cuisine) {
    switch (cuisine) {
      case Cuisine.italian:
        return "Upbeat Italian cafe instrumental, accordion and mandolin, warm inviting";
      case Cuisine.mexican:
        return "Festive mariachi instrumental, celebratory mood";
      case Cuisine.thai:
        return "Uplifting Thai traditional instrumental, aromatic atmosphere";
      case Cuisine.asian:
        return "Calm traditional Asian instrumental, peaceful zen atmosphere";
      case Cuisine.vegan:
        return "Fresh organic cafe music instrumental, light earthy atmosphere";
      case Cuisine.western:
        return "Classic American diner instrumental, upbeat friendly atmosphere";
      default:
        return "Warm celebratory dinner music instrumental, sophisticated inviting";
    }
  }

  /// Play atmospheric music for the given cuisine and duration
  Future<void> playAtmosphericMusic({
    required Cuisine cuisine,
    int durationSeconds = 30,
  }) async {
    try {
      // Clamp duration between 10 and 60 seconds
      final clampedDuration = durationSeconds.clamp(10, 60);

      debugPrint('[MusicService] Generating ${clampedDuration}s of $cuisine music...');

      final audioBytes = await _generateMusic(cuisine, clampedDuration);

      // Play the audio
      await _player.play(BytesSource(audioBytes));
      _isPlaying = true;

      debugPrint('[MusicService] Music started playing');

      // Auto-stop after duration
      Future.delayed(Duration(seconds: clampedDuration), () {
        _player.stop();
        _isPlaying = false;
        debugPrint('[MusicService] Music playback complete');
      });
    } catch (e, stack) {
      debugPrint('[MusicService] Failed to generate/play music: $e\n$stack');
      _isPlaying = false;
      // Graceful degradation - music failure shouldn't break cooking experience
    }
  }

  /// Generate music using ElevenLabs Music API
  Future<Uint8List> _generateMusic(Cuisine cuisine, int durationSeconds) async {
    final apiKey = dotenv.env['ELEVENLABS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('ELEVENLABS_API_KEY not set in .env');
    }

    final response = await http.post(
      Uri.parse('https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128'),
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prompt': _getMusicPrompt(cuisine),
        'model_id': 'music_v1',
        'music_length_ms': durationSeconds * 1000,
        'force_instrumental': true,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Music API failed: ${response.statusCode} - ${response.body}');
    }

    return response.bodyBytes;
  }

  /// Stop currently playing music
  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    debugPrint('[MusicService] Music stopped');
  }

  /// Dispose of the service
  void dispose() {
    _player.dispose();
  }
}
