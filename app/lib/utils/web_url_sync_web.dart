// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebUrlSync {
  const WebUrlSync();

  void replace(String path) {
    try {
      // Ensure path starts with / if it doesn't already
      final cleanPath = path.startsWith('/') ? path : '/$path';
      // Add hash prefix if not present
      final location = cleanPath.startsWith('/#') ? cleanPath : '/#$cleanPath';
      html.window.history.replaceState(html.window.history.state, '', location);
    } catch (e) {
      // Ignore failures; URL sync is best-effort on web.
      print('WebUrlSync error: $e');
    }
  }
}
