import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _displayName;

  User? get currentUser => _supabase.auth.currentUser;
  Session? get currentSession => _supabase.auth.currentSession;

  bool get isAuthenticated => currentSession != null;

  /// The user's display name (first name for the chef to call)
  String? get displayName => _displayName;

  AuthService() {
    _supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        // Load display name when user signs in
        await loadDisplayName();
      } else {
        _displayName = null;
      }
      notifyListeners();
    });
    // Load display name if already signed in
    if (isAuthenticated) {
      loadDisplayName();
    }
  }

  Future<AuthResponse> signIn(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResponse> signUp(String email, String password, {String? displayName}) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      // Create profile with display name if provided
      if (response.user != null && displayName != null && displayName.isNotEmpty) {
        await _createOrUpdateProfile(response.user!.id, displayName);
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      final redirect = kIsWeb ? Uri.base.origin : 'io.supabase.flutter://signin-callback';
      return await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirect,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    _displayName = null;
    await _supabase.auth.signOut();
  }

  /// Load the user's display name from the profiles table
  Future<void> loadDisplayName() async {
    final user = currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();

      _displayName = response?['display_name'] as String?;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading display name: $e');
    }
  }

  /// Update the user's display name
  Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _createOrUpdateProfile(user.id, name);
      _displayName = name;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating display name: $e');
      rethrow;
    }
  }

  Future<void> _createOrUpdateProfile(String userId, String displayName) async {
    await _supabase.from('profiles').upsert({
      'id': userId,
      'display_name': displayName,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
