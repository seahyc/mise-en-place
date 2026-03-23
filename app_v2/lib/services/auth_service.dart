import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._apiClient, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();

  Stream<User?> get authStateStream => _authStateController.stream;

  Future<User> login(String email, String password) async {
    final tokens = await _apiClient.login(email, password);
    await _storeTokens(tokens.accessToken, tokens.refreshToken);
    final user = await _apiClient.getCurrentUser();
    _authStateController.add(user);
    return user;
  }

  Future<User> register(
    String email,
    String password,
    String displayName,
  ) async {
    final tokens = await _apiClient.register(email, password, displayName);
    await _storeTokens(tokens.accessToken, tokens.refreshToken);
    final user = await _apiClient.getCurrentUser();
    _authStateController.add(user);
    return user;
  }

  Future<User> loginWithGoogle(String idToken) async {
    final tokens = await _apiClient.loginWithGoogle(idToken);
    await _storeTokens(tokens.accessToken, tokens.refreshToken);
    final user = await _apiClient.getCurrentUser();
    _authStateController.add(user);
    return user;
  }

  Future<void> logout() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    _authStateController.add(null);
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null;
  }

  Future<User?> getCurrentUser() async {
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return null;
    try {
      final user = await _apiClient.getCurrentUser();
      _authStateController.add(user);
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  void dispose() {
    _authStateController.close();
  }
}
