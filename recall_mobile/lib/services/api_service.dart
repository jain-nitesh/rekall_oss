import 'package:flutter/foundation.dart' hide Category;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import '../config/environment.dart';
import 'shared_storage_service.dart';
import '../models/user.dart';
import '../models/content_item.dart';
import '../models/shared_space.dart';
import '../models/category.dart';
import '../models/filter_option.dart';

/// API Service for backend communication.
///
/// For beginners:
/// - This is a "singleton" - only one instance exists in the app
/// - It uses Dio (HTTP client) to make requests to the backend
/// - JWT tokens are automatically added to requests via an interceptor
/// - Errors are automatically converted to user-friendly messages
class ApiService {
  late final Dio _dio;
  final _secureStorage = const FlutterSecureStorage();
  static final ApiService _instance = ApiService._internal();

  /// Callback triggered when a 401 response is received.
  /// Set by AuthNotifier to trigger automatic logout.
  void Function()? onUnauthorized;

  factory ApiService() => _instance;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: Environment.apiBaseUrl, // Use environment-based URL
      connectTimeout: const Duration(milliseconds: AppConstants.apiTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.apiTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add JWT interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  /// Updates the Dio base URL. Called when the user selects a server.
  void updateBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// Returns the current base URL (used for iOS app group sync).
  String get baseUrl => _dio.options.baseUrl;

  /// Login with email and password (self-hosted backends).
  Future<Map<String, dynamic>> emailLogin({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final token = response.data['access_token'] as String;
      final refreshToken = response.data['refresh_token'] as String;
      await _secureStorage.write(key: AppConstants.keyAuthToken, value: token);
      await _secureStorage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      await SharedStorageService.syncToAppGroup(token, baseUrl);

      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Register with email and password (self-hosted backends).
  Future<Map<String, dynamic>> emailSignup({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'name': name,
      });

      final token = response.data['access_token'] as String;
      final refreshToken = response.data['refresh_token'] as String;
      await _secureStorage.write(key: AppConstants.keyAuthToken, value: token);
      await _secureStorage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      await SharedStorageService.syncToAppGroup(token, baseUrl);

      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Add JWT token to headers if available
    final token = await _secureStorage.read(key: AppConstants.keyAuthToken);

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  bool _isRefreshing = false;

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    // Handle 401 Unauthorized - try to refresh token first
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      // Don't try to refresh if the failing request was the refresh endpoint itself
      final isRefreshRequest = err.requestOptions.path.contains('/auth/refresh');
      if (isRefreshRequest) {
        debugPrint('[API] Refresh token rejected - triggering logout');
        onUnauthorized?.call();
        handler.next(err);
        return;
      }

      _isRefreshing = true;
      try {
        final refreshToken = await _secureStorage.read(key: AppConstants.keyRefreshToken);

        if (refreshToken != null) {
          debugPrint('[API] 401 received - attempting token refresh');
          final response = await _dio.post('/auth/refresh', data: {
            'refresh_token': refreshToken,
          });

          // Save new tokens
          final newAccessToken = response.data['access_token'] as String;
          final newRefreshToken = response.data['refresh_token'] as String;
          await _secureStorage.write(key: AppConstants.keyAuthToken, value: newAccessToken);
          await _secureStorage.write(key: AppConstants.keyRefreshToken, value: newRefreshToken);
          await SharedStorageService.syncToAppGroup(newAccessToken, baseUrl);

          debugPrint('[API] Token refreshed successfully');

          // Retry the original request with new token
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newAccessToken';
          final retryResponse = await _dio.fetch(opts);
          _isRefreshing = false;
          handler.resolve(retryResponse);
          return;
        } else {
          debugPrint('[API] No refresh token available - triggering logout');
          onUnauthorized?.call();
        }
      } catch (e) {
        debugPrint('[API] Token refresh failed: $e - triggering logout');
        onUnauthorized?.call();
      }
      _isRefreshing = false;
    }

    // Log other errors for debugging
    if (err.response != null) {
      debugPrint('[API] Error ${err.response?.statusCode}: ${err.response?.data}');
    } else {
      debugPrint('[API] Network error: ${err.message}');
    }

    handler.next(err);
  }

  // ===== Authentication APIs =====


  /// Logout user by clearing JWT token.
  ///
  /// This removes the token from local storage.
  /// The interceptor will no longer add Authorization header to requests.
  Future<void> logout() async {
    await _secureStorage.delete(key: AppConstants.keyAuthToken);
    await _secureStorage.delete(key: AppConstants.keyRefreshToken);
  }

  /// Get current user
  Future<User> getCurrentUser() async {
    try {
      final response = await _dio.get('/auth/me');
      // Backend returns user object directly, not nested in 'user' key
      return User.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Login with Google OAuth.
  ///
  /// Flow:
  /// 1. Mobile gets Google ID token from google_sign_in package
  /// 2. Send ID token to backend
  /// 3. Backend verifies token with Google
  /// 4. Backend returns JWT token + user info
  /// 5. Save JWT token locally
  ///
  /// Returns:
  ///   Map with 'access_token', 'token_type', and 'user' data
  Future<Map<String, dynamic>> googleOAuthLogin({
    required String idToken,
  }) async {
    try {
      final response = await _dio.post('/auth/google-auth', data: {
        'id_token': idToken,
      });

      // Save JWT tokens to secure storage
      final token = response.data['access_token'] as String;
      final refreshToken = response.data['refresh_token'] as String;
      await _secureStorage.write(key: AppConstants.keyAuthToken, value: token);
      await _secureStorage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      // Sync token to iOS app group so Share Extension can upload in background
      await SharedStorageService.syncToAppGroup(token, baseUrl);

      // Return the full response (token + user)
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }


  /// Login with Apple Sign-In.
  ///
  /// Flow:
  /// 1. Mobile gets Apple identity token from sign_in_with_apple package
  /// 2. Send identity token to backend
  /// 3. Backend verifies token with Apple
  /// 4. Backend returns JWT token + user info
  /// 5. Save JWT token locally
  Future<Map<String, dynamic>> appleOAuthLogin({
    required String idToken,
    String? name,
  }) async {
    try {
      final response = await _dio.post('/auth/apple-auth', data: {
        'id_token': idToken,
        if (name != null) 'name': name,
      });

      // Save JWT tokens to secure storage
      final token = response.data['access_token'] as String;
      final refreshToken = response.data['refresh_token'] as String;
      await _secureStorage.write(key: AppConstants.keyAuthToken, value: token);
      await _secureStorage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      // Sync token to iOS app group so Share Extension can upload in background
      await SharedStorageService.syncToAppGroup(token, baseUrl);

      // Return the full response (token + user)
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete user account permanently.
  Future<void> deleteAccount({required String confirmationEmail}) async {
    try {
      await _dio.delete('/user/account', data: {
        'confirmation_email': confirmationEmail,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Content APIs =====

  /// Ingest content (from share extension)
  /// Note: created_at is always set by the backend to current time
  Future<ContentItem> ingestContent({
    required String url,
    String? title,
    String? sourceAppName,
    String? sourceAppPackage,
    String? sharedText,  // NEW: Full text from share intent (fallback for private content)
  }) async {
    // Build request data outside try block so it's accessible in catch
    final requestData = <String, dynamic>{
      'url': url,
      if (title != null && title.isNotEmpty) 'title': title,
      if (sourceAppName != null && sourceAppName.isNotEmpty) 'source_app_name': sourceAppName,
      if (sourceAppPackage != null && sourceAppPackage.isNotEmpty) 'source_app_package': sourceAppPackage,
      if (sharedText != null && sharedText.isNotEmpty) 'shared_text': sharedText,  // NEW
    };

    try {
      debugPrint('╔════════════════════════════════════════════════════╗');
      debugPrint('║  API SERVICE - INGEST CONTENT                     ║');
      debugPrint('╚════════════════════════════════════════════════════╝');
      debugPrint('Timestamp: ${DateTime.now().toIso8601String()}');
      debugPrint('URL: $url');
      debugPrint('Title: $title');
      debugPrint('Request payload: $requestData');

      final response = await _dio.post('/content/ingest', data: requestData);

      debugPrint('✓ Ingest successful!');
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response data type: ${response.data.runtimeType}');
      debugPrint('Response data: ${response.data}');

      // Backend returns content directly, not nested under 'content' key
      return ContentItem.fromJson(response.data);
    } on DioException catch (e) {
      // Log the actual error response for debugging
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('❌ INGEST ERROR');
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('URL: $url');
      debugPrint('Title: $title');
      debugPrint('Request payload: $requestData');
      if (e.response != null) {
        debugPrint('Backend error status: ${e.response?.statusCode}');
        debugPrint('Backend error response: ${e.response?.data}');
        debugPrint('Backend error headers: ${e.response?.headers}');

        // Parse backend error detail if available
        if (e.response?.data is Map && e.response?.data['detail'] != null) {
          debugPrint('Backend error detail: ${e.response?.data['detail']}');
        }
      } else {
        debugPrint('No response from server - network error');
        debugPrint('Error type: ${e.type}');
        debugPrint('Error message: ${e.message}');
      }
      debugPrint('═══════════════════════════════════════════════════');
      throw _handleError(e);
    }
  }

  // ===== Media Upload =====

  /// Upload a media file (image or video) and create a content item.
  /// Returns the created ContentItem with media_url set.
  Future<ContentItem> uploadMedia({
    required String filePath,
    required String contentType, // 'image' or 'video'
    String? title,
    String? notes,
  }) async {
    try {
      debugPrint('[API] Uploading media: $contentType from $filePath');

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'content_type': contentType,
        if (title != null && title.isNotEmpty) 'title': title,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

      final response = await _dio.post(
        '/content/upload-media',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 120),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            debugPrint('[API] Upload progress: ${(sent / total * 100).toStringAsFixed(0)}%');
          }
        },
      );

      debugPrint('[API] Upload successful: ${response.statusCode}');
      return ContentItem.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('[API] Upload error: ${e.response?.statusCode} ${e.response?.data}');
      throw _handleError(e);
    }
  }

  // ===== Categories =====

  Future<List<Category>> getCategories() async {
    try {
      final response = await _dio.get('/categories');
      final data = response.data as List<dynamic>;
      return data
          .map<Category>((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get all content for user with pagination and optional filters
  Future<Map<String, dynamic>> getAllContent({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };

      // Add filter parameters if provided
      if (filters != null) {
        queryParams.addAll(filters);
      }

      final response = await _dio.get('/content', queryParameters: queryParams);

      final items = (response.data['content'] as List)
          .map((item) => ContentItem.fromJson(item))
          .toList();

      return {
        'content': items,
        'total': response.data['total'] as int,
        'page': response.data['page'] as int,
        'page_size': response.data['page_size'] as int,
        'has_more': response.data['has_more'] as bool,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get memory feed content for specific days ago
  Future<Map<String, dynamic>> getMemoryFeedContent(
    int days, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get('/content/memory-feed', queryParameters: {
        'days': days,
        'page': page,
        'page_size': pageSize,
      });
      
      final items = (response.data['content'] as List)
          .map((item) => ContentItem.fromJson(item))
          .toList();

      return {
        'content': items,
        'total': response.data['total'] as int,
        'page': response.data['page'] as int,
        'page_size': response.data['page_size'] as int,
        'has_more': response.data['has_more'] as bool,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get content by ID
  Future<ContentItem> getContentById(String id) async {
    try {
      final response = await _dio.get('/content/$id');
      // Backend returns ContentResponse directly, not wrapped in 'content' key
      return ContentItem.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete content
  Future<void> deleteContent(String id) async {
    try {
      await _dio.delete('/content/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update content (mark as done, favorite, tags)
  Future<ContentItem> updateContent(
    String id, {
    bool? isDone,
    bool? isFavorite,
    List<String>? tags,
    String? notes,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (isDone != null) data['is_done'] = isDone;
      if (isFavorite != null) data['is_favorite'] = isFavorite;
      if (tags != null) data['tags'] = tags;
      if (notes != null) data['notes'] = notes;

      final response = await _dio.patch('/content/$id', data: data);
      return ContentItem.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get filter options with counts
  Future<FilterOptions> getFilterOptions() async {
    try {
      final response = await _dio.get('/content/filter-options');
      return FilterOptions.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Search content with multi-select filters
  Future<Map<String, dynamic>> searchContent({
    String? query,
    List<String>? categories,
    List<String>? userCategoryIds,
    List<String>? sourceApps,
    int? days,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.post('/content/search', data: {
        if (query != null && query.isNotEmpty) 'query': query,
        if (categories != null && categories.isNotEmpty) 'categories': categories,
        if (userCategoryIds != null && userCategoryIds.isNotEmpty)
          'user_category_ids': userCategoryIds,
        if (sourceApps != null && sourceApps.isNotEmpty) 'source_apps': sourceApps,
        if (days != null) 'days': days,
        'page': page,
        'page_size': pageSize,
      });

      final items = (response.data['content'] as List)
          .map((item) => ContentItem.fromJson(item))
          .toList();

      return {
        'content': items,
        'total': response.data['total'] as int,
        'page': response.data['page'] as int,
        'page_size': response.data['page_size'] as int,
        'has_more': response.data['has_more'] as bool,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Semantic Search API =====

  /// Semantic search using AI embeddings.
  ///
  /// Finds content similar in meaning to the query, not just keyword matches.
  Future<List<ContentItem>> semanticSearch(
    String query, {
    int limit = 20,
    double threshold = 0.3,
  }) async {
    try {
      final response = await _dio.post('/search/semantic', data: {
        'query': query,
        'limit': limit,
        'threshold': threshold,
      });

      return (response.data as List)
          .map((item) => ContentItem.fromJson(item))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Connections APIs =====

  /// Get connections for a specific content item.
  Future<List<dynamic>> getConnections(String contentId) async {
    try {
      final response = await _dio.get('/connections/$contentId');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get all connections for user (paginated).
  Future<Map<String, dynamic>> getAllConnections({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get('/connections', queryParameters: {
        'page': page,
        'page_size': pageSize,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Dismiss a connection.
  Future<void> dismissConnection(String connectionId) async {
    try {
      await _dio.post('/connections/$connectionId/dismiss');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get today's best undiscovered connection pair.
  Future<Map<String, dynamic>?> getDailyConnection() async {
    try {
      final response = await _dio.get('/connections/daily');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleError(e);
    }
  }

  /// Get clusters for current user.
  Future<Map<String, dynamic>> getClusters({String? search, String? category}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (category != null && category.isNotEmpty) queryParams['category'] = category;
      final response = await _dio.get('/clusters', queryParameters: queryParams);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get cluster detail.
  Future<Map<String, dynamic>> getClusterDetail(String clusterId) async {
    try {
      final response = await _dio.get('/clusters/$clusterId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Dismiss a cluster.
  Future<void> dismissCluster(String clusterId) async {
    try {
      await _dio.delete('/clusters/$clusterId/dismiss');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Track connection exploration (fire-and-forget).
  Future<void> exploreConnection(String connectionId) async {
    try {
      await _dio.post('/connections/$connectionId/explore');
    } on DioException catch (e) {
      // Fire-and-forget, don't throw
      debugPrint('[API] Failed to track explore: $e');
    }
  }

  // ===== Import APIs =====

  /// Import Chrome bookmarks HTML file.
  Future<Map<String, dynamic>> importChromeBookmarks(List<int> fileBytes, String fileName) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      });
      final response = await _dio.post('/import/chrome', data: formData);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Import Pocket export file.
  Future<Map<String, dynamic>> importPocketBookmarks(List<int> fileBytes, String fileName) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      });
      final response = await _dio.post('/import/pocket', data: formData);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Import Raindrop.io export file.
  Future<Map<String, dynamic>> importRaindropBookmarks(List<int> fileBytes, String fileName) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      });
      final response = await _dio.post('/import/raindrop', data: formData);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Check import job status.
  Future<Map<String, dynamic>> getImportStatus(String importId) async {
    try {
      final response = await _dio.get('/import/status/$importId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Collections APIs =====

  /// Create a public collection.
  Future<Map<String, dynamic>> createCollection({
    required String title,
    String? description,
  }) async {
    try {
      final response = await _dio.post('/collections', data: {
        'title': title,
        if (description != null) 'description': description,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get my collections.
  Future<List<dynamic>> getMyCollections() async {
    try {
      final response = await _dio.get('/collections');
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Explore public collections.
  Future<List<dynamic>> exploreCollections({int page = 1, int pageSize = 20}) async {
    try {
      final response = await _dio.get('/collections/explore', queryParameters: {
        'page': page,
        'page_size': pageSize,
      });
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get collection by slug.
  Future<Map<String, dynamic>> getCollection(String slug) async {
    try {
      final response = await _dio.get('/collections/$slug');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Add item to collection.
  Future<void> addItemToCollection(String collectionId, String contentItemId, {String? curatorNote}) async {
    try {
      await _dio.post('/collections/$collectionId/items', data: {
        'content_item_id': contentItemId,
        if (curatorNote != null) 'curator_note': curatorNote,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Remove item from collection.
  Future<void> removeItemFromCollection(String collectionId, String itemId) async {
    try {
      await _dio.delete('/collections/$collectionId/items/$itemId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Fork a collection to user's library.
  Future<Map<String, dynamic>> forkCollection(String collectionId) async {
    try {
      final response = await _dio.post('/collections/$collectionId/fork');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Spaces APIs =====

  /// Get all spaces for user
  Future<List<SharedSpace>> getAllSpaces() async {
    try {
      final response = await _dio.get('/spaces');
      final spaces = (response.data['spaces'] as List)
          .map((space) => SharedSpace.fromJson(space))
          .toList();

      return spaces;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create space
  Future<SharedSpace> createSpace({
    required String name,
    required String description,
    String? emoji,
    String? accentColor,
  }) async {
    try {
      final response = await _dio.post('/spaces', data: {
        'name': name,
        'description': description,
        if (emoji != null) 'emoji': emoji,
        if (accentColor != null) 'accent_color': accentColor,
      });

      return SharedSpace.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get space by ID
  Future<SharedSpace> getSpaceById(
    String id, {
    int contentPage = 1,
    int contentPageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/spaces/$id',
        queryParameters: {
          'content_page': contentPage,
          'content_page_size': contentPageSize,
        },
      );
      return SharedSpace.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update space
  Future<SharedSpace> updateSpace(
    String id, {
    String? name,
    String? description,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;

      final response = await _dio.patch('/spaces/$id', data: data);
      return SharedSpace.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Add content to space
  Future<void> addContentToSpace(String spaceId, String contentId) async {
    try {
      await _dio.post('/spaces/$spaceId/content', data: {
        'content_id': contentId,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Remove content from space
  Future<void> removeContentFromSpace(String spaceId, String contentId) async {
    try {
      await _dio.delete('/spaces/$spaceId/content/$contentId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete space
  Future<void> deleteSpace(String id) async {
    try {
      await _dio.delete('/spaces/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Invite member to space
  Future<void> inviteMember(
    String spaceId,
    String email, {
    String role = 'member',
  }) async {
    try {
      await _dio.post('/spaces/$spaceId/members', data: {
        'email': email,
        'role': role,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Join space via invitation token
  Future<SharedSpace> joinSpaceViaToken(String token) async {
    try {
      final response = await _dio.post('/spaces/join/$token');
      return SharedSpace.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Remove member from space
  Future<void> removeMember(String spaceId, String userId) async {
    try {
      await _dio.delete('/spaces/$spaceId/members/$userId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update member role
  Future<void> updateMemberRole(
    String spaceId,
    String userId,
    String role,
  ) async {
    try {
      await _dio.patch('/spaces/$spaceId/members/$userId', data: {
        'role': role,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Regenerate invite link for space (invalidates old links)
  Future<Map<String, dynamic>> regenerateInviteLink(String spaceId) async {
    try {
      final response = await _dio.post('/spaces/$spaceId/regenerate-invite');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get invite link for space
  Future<Map<String, dynamic>> getInviteLink(String spaceId) async {
    try {
      final response = await _dio.get('/spaces/$spaceId/invite-link');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Error Handling =====

  /// Convert Dio exceptions to user-friendly error messages.
  ///
  /// FastAPI returns errors in this format:
  /// {
  ///   "detail": "Error message here"
  /// }
  ///
  /// We extract the "detail" field and provide context based on status code.
  // ===== Notification APIs =====

  /// Register FCM device token with backend.
  Future<void> registerFcmToken({
    required String fcmToken,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) async {
    try {
      await _dio.post('/notifications/devices', data: {
        'fcm_token': fcmToken,
        'platform': platform,
        'device_name': deviceName,
        'app_version': appVersion ?? '1.0.0',
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get notification settings.
  ///
  /// Returns current user's notification settings.
  /// Creates default settings if they don't exist.
  Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      final response = await _dio.get('/notifications/settings');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update notification settings.
  ///
  /// Parameters:
  /// - isEnabled: Enable/disable notifications
  /// - notificationTimeLocal: Local time in "HH:MM" format (e.g., "09:30")
  /// - utcOffsetMinutes: UTC offset in minutes (e.g., -300 for EST)
  Future<Map<String, dynamic>> updateNotificationSettings({
    bool? isEnabled,
    String? notificationTimeLocal,
    int? utcOffsetMinutes,
  }) async {
    try {
      final response = await _dio.put('/notifications/settings', data: {
        if (isEnabled != null) 'is_enabled': isEnabled,
        if (notificationTimeLocal != null)
          'notification_time_local': notificationTimeLocal,
        if (utcOffsetMinutes != null) 'utc_offset_minutes': utcOffsetMinutes,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Timeline Content APIs (NEW UX) =====

  /// Get content timeline with calendar-based time sections.
  ///
  /// Returns content organized by time periods for the new feed UX.
  /// Sections: just_in (last 3h), today (midnight to now), yesterday (previous day), this_week, this_month
  Future<Map<String, dynamic>> getContentTimeline({
    List<String> sections = const ['just_in', 'today', 'yesterday'],
    int page = 1,
    int pageSize = 20,
    String? readStatus,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'sections': sections.join(','),
        'page': page,
        'page_size': pageSize,
      };
      if (readStatus != null) queryParams['read_status'] = readStatus;
      final response = await _dio.get('/content/timeline', queryParameters: queryParams);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Search History APIs =====

  /// Get user's recent searches with timestamps.
  Future<List<dynamic>> getSearchHistory({int limit = 10}) async {
    try {
      final response = await _dio.get('/search/history', queryParameters: {
        'limit': limit,
      });
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Save a search to history.
  Future<Map<String, dynamic>> saveSearch(String query) async {
    try {
      final response = await _dio.post('/search/history', data: {
        'query': query,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Clear all search history for current user.
  Future<void> clearSearchHistory() async {
    try {
      await _dio.delete('/search/history');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Explore Spaces API =====

  /// Get recommended/trending public spaces.
  ///
  /// Used in the Search screen's "Explore Spaces" section.
  Future<List<dynamic>> getExploreSpaces({int limit = 20}) async {
    try {
      final response = await _dio.get('/spaces/explore', queryParameters: {
        'limit': limit,
      });
      // Response is SpaceListResponse with 'spaces' array
      return (response.data['spaces'] as List<dynamic>?) ?? [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Trending News API =====

  /// Get trending tech/AI news for empty feed.
  /// No auth required — cached on backend.
  Future<List<Map<String, dynamic>>> getTrendingNews() async {
    try {
      final response = await _dio.get('/trending/news');
      final items = response.data['items'] as List<dynamic>? ?? [];
      return items.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== User Preferences & Usage Stats APIs =====

  /// Get user's AI usage statistics.
  Future<Map<String, dynamic>> getUsageStats() async {
    try {
      final response = await _dio.get('/user/usage-stats');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get user preferences (summary style, auto-categorize, etc.).
  Future<Map<String, dynamic>> getUserPreferences() async {
    try {
      final response = await _dio.get('/user/preferences');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update user preferences.
  ///
  /// Only updates fields that are provided.
  Future<Map<String, dynamic>> updateUserPreferences({
    String? summaryStyle,
    bool? autoCategorize,
    List<String>? connectedSources,
    bool? dailyGemsEnabled,
    String? dailyGemsTime,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (summaryStyle != null) data['summary_style'] = summaryStyle;
      if (autoCategorize != null) data['auto_categorize'] = autoCategorize;
      if (connectedSources != null) data['connected_sources'] = connectedSources;
      if (dailyGemsEnabled != null) data['daily_gems_enabled'] = dailyGemsEnabled;
      if (dailyGemsTime != null) data['daily_gems_time'] = dailyGemsTime;

      final response = await _dio.put('/user/preferences', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Personal Info APIs =====

  /// Get user's personal info (self-entity bio, social links, enriched data).
  Future<Map<String, dynamic>> getPersonalInfo() async {
    try {
      final response = await _dio.get('/user/personal-info');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Seed or update personal info (bio, social links).
  /// Creates/updates the user's self-entity in the knowledge graph.
  Future<Map<String, dynamic>> seedPersonalInfo({
    String? bio,
    Map<String, String>? socialLinks,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (bio != null) data['bio'] = bio;
      if (socialLinks != null) data['social_links'] = socialLinks;

      final response = await _dio.post('/user/personal-info', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Entity APIs =====

  /// Get entities list (paginated).
  Future<Map<String, dynamic>> getEntities({
    int page = 1,
    int pageSize = 20,
    String? entityType,
    String sortBy = 'mention_count',
    String? search,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        'sort_by': sortBy,
      };
      if (entityType != null) params['entity_type'] = entityType;
      if (search != null) params['search'] = search;
      final response = await _dio.get('/entities', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get entity detail.
  Future<Map<String, dynamic>> getEntityDetail(String entityId) async {
    try {
      final response = await _dio.get('/entities/$entityId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Wiki APIs =====

  /// Get wiki pages list (paginated).
  Future<Map<String, dynamic>> getWikiPages({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? search,
  }) async {
    try {
      final params = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };
      if (status != null) params['status'] = status;
      if (search != null) params['search'] = search;
      final response = await _dio.get('/wiki', queryParameters: params);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get wiki page by slug.
  Future<Map<String, dynamic>> getWikiPage(String slug) async {
    try {
      final response = await _dio.get('/wiki/$slug');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }


  /// Delete a wiki page by ID.
  Future<void> deleteWikiPage(String wikiId) async {
    try {
      await _dio.delete('/wiki/$wikiId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Search wiki pages semantically.
  Future<List<dynamic>> searchWikiPages(String query) async {
    try {
      final response = await _dio.get('/wiki/search', queryParameters: {'q': query});
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Chat APIs =====

  /// Send a chat message.
  Future<Map<String, dynamic>> sendChatMessage({
    required String question,
    String? conversationId,
  }) async {
    try {
      final data = <String, dynamic>{'question': question};
      if (conversationId != null) data['conversation_id'] = conversationId;
      final response = await _dio.post('/chat', data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get conversation list with count info.
  Future<Map<String, dynamic>> getConversations({int limit = 50}) async {
    try {
      final response = await _dio.get('/chat/conversations', queryParameters: {'limit': limit});
      final data = response.data;
      // Handle both new Map format and legacy List format
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is List) {
        return {
          'conversations': data,
          'total': data.length,
          'max_allowed': 50,
        };
      }
      return {'conversations': [], 'total': 0, 'max_allowed': 50};
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get conversation with messages.
  Future<Map<String, dynamic>> getConversation(String conversationId) async {
    try {
      final response = await _dio.get('/chat/conversations/$conversationId');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete a conversation.
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _dio.delete('/chat/conversations/$conversationId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // ===== Health Check APIs =====

  /// Get health check insights.
  Future<List<dynamic>> getHealthChecks({String? checkType}) async {
    try {
      final params = <String, dynamic>{};
      if (checkType != null) params['check_type'] = checkType;
      final response = await _dio.get('/health-checks', queryParameters: params);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Dismiss a health check.
  Future<void> dismissHealthCheck(String checkId) async {
    try {
      await _dio.post('/health-checks/$checkId/dismiss');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;

      // Try to extract error message from response
      // FastAPI uses "detail" field for error messages
      String? message;
      if (e.response!.data is Map) {
        message = e.response!.data['detail'] ??
            e.response!.data['message'] ??
            e.response!.data['error'];
      }

      switch (statusCode) {
        case 400:
          return message ?? 'Invalid request. Please check your input.';
        case 401:
          return message ?? 'Session expired. Please login again.';
        case 403:
          return message ?? 'You don\'t have permission to perform this action.';
        case 404:
          return message ?? 'The requested resource was not found.';
        case 409:
          return message ?? 'Conflict. This resource already exists.';
        case 422:
          return message ?? 'Validation error. Please check your input.';
        case 429:
          return 'Too many requests. Please wait a moment and try again.';
        case 500:
        case 502:
        case 503:
          return 'Server error. Please try again later.';
        default:
          return message ?? 'An error occurred (Status: $statusCode)';
      }
    } else if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Please check your internet connection.';
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return 'Server took too long to respond. Please try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      return 'Cannot connect to server. Please check your internet connection and try again.';
    } else if (e.type == DioExceptionType.badResponse) {
      return 'Invalid response from server. Please try again.';
    } else if (e.type == DioExceptionType.cancel) {
      return 'Request was cancelled.';
    } else {
      return 'Network error. Please check your connection and try again.';
    }
  }
}
