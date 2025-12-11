import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_redirect_stub.dart'
    if (dart.library.html) 'auth_redirect_web.dart';

/// Handle Supabase auth redirect on web (code/provider query params) and
/// clean the URL afterwards. No-op on other platforms.
Future<void> handleAuthRedirect() async {
  await performAuthRedirectCleanup(Supabase.instance.client);
}
