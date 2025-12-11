import 'dart:html' as html;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> performAuthRedirectCleanup(SupabaseClient client) async {
  final uri = Uri.base;

  if (uri.queryParameters.containsKey('code')) {
    try {
      await client.auth.getSessionFromUrl(uri);
    } catch (_) {
      // Ignore; Supabase will emit auth errors separately if needed.
    }

    final cleaned = uri.replace(queryParameters: {});
    try {
      html.window.history.replaceState(html.window.history.state, '', cleaned.toString());
    } catch (_) {
      // Best-effort URL cleanup.
    }
  }
}
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
