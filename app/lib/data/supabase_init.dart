import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Load environment file if present; ignore missing file so we can rely on
/// dart-define values in web builds.
Future<void> loadEnvIfPresent() async {
  try {
    await dotenv.load(fileName: ".env");
  } on Exception catch (e) {
    debugPrint('[Env] .env not loaded ($e). Falling back to dart-define values.');
  }
}

String? _getEnv(String key) {
  final fromDotEnv = dotenv.maybeGet(key);
  if (fromDotEnv != null && fromDotEnv.isNotEmpty) return fromDotEnv;

  switch (key) {
    case 'SUPABASE_URL':
      const url = String.fromEnvironment('SUPABASE_URL');
      return url.isEmpty ? null : url;
    case 'SUPABASE_ANON_KEY':
      const keyVal = String.fromEnvironment('SUPABASE_ANON_KEY');
      return keyVal.isEmpty ? null : keyVal;
    default:
      return null;
  }
}

Future<void> initSupabase() async {
  final url = _getEnv('SUPABASE_URL');
  final anonKey = _getEnv('SUPABASE_ANON_KEY');

  if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
    throw Exception('Supabase credentials missing. Ensure SUPABASE_URL and SUPABASE_ANON_KEY are set in .env');
  }

  try {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  } catch (e, st) {
    debugPrint('Failed to initialize Supabase: $e\n$st');
    rethrow;
  }
}

final supabase = Supabase.instance.client;
