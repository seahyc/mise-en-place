import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/job.dart';
import '../models/recipe.dart';
import '../models/session.dart';
import '../models/user.dart';

class ApiClient {
  ApiClient({
    String baseUrl = 'https://api.mise.seahyingcong.com',
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(AuthInterceptor(_dio, _storage));
  }

  late final Dio _dio;
  final FlutterSecureStorage _storage;

  // ── Auth ──────────────────────────────────────────────────────────────

  Future<TokenPair> register(
    String email,
    String password,
    String displayName,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'display_name': displayName,
      },
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<TokenPair> login(String email, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<TokenPair> loginWithGoogle(String idToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'id_token': idToken},
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<User> getCurrentUser() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return User.fromJson(response.data!);
  }

  // ── Recipes ───────────────────────────────────────────────────────────

  Future<List<Recipe>> getRecipes({int page = 1, int pageSize = 20}) async {
    final response = await _dio.get<dynamic>(
      '/recipes',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    final data = response.data;
    List<dynamic> items;
    if (data is List) {
      items = data;
    } else if (data is Map<String, dynamic> && data.containsKey('recipes')) {
      items = data['recipes'] as List<dynamic>;
    } else {
      items = [];
    }
    return items
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Recipe> getRecipe(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/recipes/$id');
    return Recipe.fromJson(response.data!);
  }

  Future<Recipe> createRecipe({
    required String title,
    String description = '',
    String sourceType = 'manual',
    String? cuisine,
    List<String> ingredients = const [],
    List<Map<String, dynamic>> steps = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/recipes',
      data: {
        'title': title,
        'description': description,
        'source_type': sourceType,
        if (cuisine != null) 'cuisine': cuisine,
        'ingredients': ingredients,
        'steps': steps,
      },
    );
    return Recipe.fromJson(response.data!);
  }

  Future<void> updateRecipe(
    String id, {
    String? title,
    String? description,
    String? cuisine,
    List<String>? ingredients,
    List<Map<String, dynamic>>? steps,
  }) async {
    await _dio.patch<dynamic>(
      '/recipes/$id',
      data: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (cuisine != null) 'cuisine': cuisine,
        if (ingredients != null) 'ingredients': ingredients,
        if (steps != null) 'steps': steps,
      },
    );
  }

  Future<void> deleteRecipe(String id) async {
    await _dio.delete<dynamic>('/recipes/$id');
  }

  // ── Sessions ──────────────────────────────────────────────────────────

  Future<CookingSession> createSession(List<String> recipeIds) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/sessions',
      data: {'recipe_ids': recipeIds},
    );
    return CookingSession.fromJson(response.data!);
  }

  Future<CookingSession> getSession(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/sessions/$id');
    return CookingSession.fromJson(response.data!);
  }

  Future<void> startSession(String id) async {
    await _dio.post<dynamic>('/sessions/$id/start');
  }

  Future<void> pauseSession(String id) async {
    await _dio.post<dynamic>('/sessions/$id/pause');
  }

  Future<void> resumeSession(String id) async {
    await _dio.post<dynamic>('/sessions/$id/resume');
  }

  Future<void> completeStep(String sessionId, String stepId) async {
    await _dio.post<dynamic>('/sessions/$sessionId/steps/$stepId/complete');
  }

  Future<List<CookingSession>> listSessions() async {
    final response = await _dio.get<dynamic>('/sessions');
    final data = response.data;
    List<dynamic> items;
    if (data is List) {
      items = data;
    } else if (data is Map<String, dynamic> && data.containsKey('sessions')) {
      items = data['sessions'] as List<dynamic>;
    } else {
      items = [];
    }
    return items
        .map((e) => CookingSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Jobs ──────────────────────────────────────────────────────────────

  Future<String> ingestUrl(String url) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/ingest',
      data: {'url': url},
    );
    return response.data!['id'] as String;
  }

  Future<Job> getJob(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/jobs/$id');
    return Job.fromJson(response.data!);
  }
}

// ── Auth Interceptor ──────────────────────────────────────────────────────

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._storage);

  final Dio _dio;
  final FlutterSecureStorage _storage;
  bool _isRefreshing = false;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth header for auth endpoints
    final path = options.path;
    if (path.startsWith('/auth/') && path != '/auth/me') {
      return handler.next(options);
    }

    final token = await _storage.read(key: _accessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 || _isRefreshing) {
      return handler.next(err);
    }

    _isRefreshing = true;
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken == null) {
        return handler.next(err);
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final tokens = TokenPair.fromJson(response.data!);
      await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
      await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);

      // Retry the original request with new token
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      final retryResponse = await _dio.fetch<dynamic>(options);
      return handler.resolve(retryResponse);
    } on DioException {
      // Refresh failed, propagate original error
      return handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}
