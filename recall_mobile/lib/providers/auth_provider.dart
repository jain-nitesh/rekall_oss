import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/analytics_service.dart';
import '../services/google_auth_service.dart';
import '../services/apple_auth_service.dart';
import '../services/shared_storage_service.dart';

/// Authentication state
class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory AuthState.initial() {
    return const AuthState(status: AuthStatus.initial);
  }

  factory AuthState.loading() {
    return const AuthState(status: AuthStatus.loading);
  }

  factory AuthState.authenticated(User user) {
    return AuthState(status: AuthStatus.authenticated, user: user);
  }

  factory AuthState.unauthenticated([String? error]) {
    return AuthState(
      status: AuthStatus.unauthenticated,
      errorMessage: error,
    );
  }

  factory AuthState.error(String message) {
    return AuthState(
      status: AuthStatus.error,
      errorMessage: message,
    );
  }
}

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

/// Auth provider notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final _secureStorage = const FlutterSecureStorage();

  AuthNotifier() : super(AuthState.initial()) {
    // Register 401 callback so Dio interceptor can trigger logout
    ApiService().onUnauthorized = _onUnauthorized;
    _checkAuthStatus();
  }

  /// Called by ApiService when a 401 response is received.
  /// Clears local auth state so user is redirected to login.
  void _onUnauthorized() {
    if (state.status == AuthStatus.authenticated) {
      debugPrint('[Auth] 401 received - clearing session');
      _clearLocalAuth();
    }
  }

  /// Clear all local auth data and set state to unauthenticated.
  Future<void> _clearLocalAuth() async {
    await _secureStorage.delete(key: AppConstants.keyAuthToken);
    await _secureStorage.delete(key: AppConstants.keyRefreshToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyUserId);
    await prefs.remove(AppConstants.keyUserEmail);
    await prefs.remove(AppConstants.keyUserName);
    await prefs.remove(AppConstants.keyUserAvatarUrl);
    await SharedStorageService.clearFromAppGroup();
    AnalyticsService().clearUser();
    state = AuthState.unauthenticated('Session expired. Please login again.');
  }

  /// Check if user is already authenticated
  Future<void> _checkAuthStatus() async {
    try {
      // One-time migration: move tokens from SharedPreferences to secure storage
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(AppConstants.keyAuthToken);
      if (legacyToken != null) {
        await _secureStorage.write(key: AppConstants.keyAuthToken, value: legacyToken);
        await prefs.remove(AppConstants.keyAuthToken);
        final legacyRefresh = prefs.getString(AppConstants.keyRefreshToken);
        if (legacyRefresh != null) {
          await _secureStorage.write(key: AppConstants.keyRefreshToken, value: legacyRefresh);
          await prefs.remove(AppConstants.keyRefreshToken);
        }
      }

      final token = await _secureStorage.read(key: AppConstants.keyAuthToken);
      final userId = prefs.getString(AppConstants.keyUserId);
      final userEmail = prefs.getString(AppConstants.keyUserEmail);
      final userName = prefs.getString(AppConstants.keyUserName);

      if (token != null && userId != null && userEmail != null && userName != null) {
        // Validate token against backend before considering user authenticated
        try {
          final user = await ApiService().getCurrentUser();
          state = AuthState.authenticated(user);

          // Set analytics user properties
          AnalyticsService().setUserId(user.id);
          AnalyticsService().setUserProperties(email: user.email, name: user.name);

          // Register FCM token with backend (important for app restarts)
          FCMService().refreshToken().catchError((error) {
            debugPrint('[Auth] FCM token refresh failed on app startup: $error');
          });
        } catch (e) {
          // Token is invalid/expired - clear local state
          debugPrint('[Auth] Token validation failed: $e - clearing session');
          await _clearLocalAuth();
        }
      } else {
        state = AuthState.unauthenticated();
      }
    } catch (e) {
      state = AuthState.error('Failed to check auth status: $e');
    }
  }


  /// Login with Google OAuth.
  ///
  /// Flow:
  /// 1. Trigger Google Sign-In
  /// 2. Get ID token from Google
  /// 3. Send to backend for verification
  /// 4. Backend returns JWT token
  /// 5. Save user info and authenticate
  Future<bool> loginWithGoogle() async {
    state = AuthState.loading();

    try {
      // Step 1: Get Google ID token
      final googleAuthService = GoogleAuthService();
      final idToken = await googleAuthService.signIn();

      if (idToken == null) {
        // User cancelled or error occurred
        state = AuthState.unauthenticated('Google sign-in cancelled');
        return false;
      }

      // Step 2: Send to backend
      final response = await ApiService().googleOAuthLogin(
        idToken: idToken,
      );

      // Extract user from response
      final user = User.fromJson(response['user']);

      // Save user info to SharedPreferences
      // (JWT token is already saved by ApiService)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserId, user.id);
      await prefs.setString(AppConstants.keyUserEmail, user.email);
      await prefs.setString(AppConstants.keyUserName, user.name);
      if (user.avatarUrl != null) {
        await prefs.setString(AppConstants.keyUserAvatarUrl, user.avatarUrl!);
      }

      state = AuthState.authenticated(user);

      // Set analytics user properties and log success
      AnalyticsService().setUserId(user.id);
      AnalyticsService().setUserProperties(email: user.email, name: user.name);
      AnalyticsService().logAuthenticationSuccess('google');

      // Register FCM token with backend after successful login
      FCMService().refreshToken().catchError((error) {
        debugPrint('[Auth] FCM token refresh failed: $error');
        // Don't fail login if FCM registration fails
      });

      return true;
    } catch (e) {
      state = AuthState.error('Google sign-in failed: $e');
      return false;
    }
  }

  /// Login with Apple Sign-In.
  ///
  /// Flow:
  /// 1. Trigger Apple Sign-In
  /// 2. Get identity token from Apple
  /// 3. Send to backend for verification
  /// 4. Backend returns JWT token
  /// 5. Save user info and authenticate
  Future<bool> loginWithApple() async {
    state = AuthState.loading();

    try {
      // Step 1: Get Apple identity token
      final appleAuthService = AppleAuthService();
      final result = await appleAuthService.signIn();

      if (result == null) {
        // User cancelled or error occurred
        state = AuthState.unauthenticated('Apple sign-in cancelled');
        return false;
      }

      // Step 2: Send to backend
      final response = await ApiService().appleOAuthLogin(
        idToken: result.identityToken,
        name: result.fullName,
      );

      // Extract user from response
      final user = User.fromJson(response['user']);

      // Save user info to SharedPreferences
      // (JWT token is already saved by ApiService)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserId, user.id);
      await prefs.setString(AppConstants.keyUserEmail, user.email);
      await prefs.setString(AppConstants.keyUserName, user.name);
      if (user.avatarUrl != null) {
        await prefs.setString(AppConstants.keyUserAvatarUrl, user.avatarUrl!);
      }

      state = AuthState.authenticated(user);

      // Set analytics user properties and log success
      AnalyticsService().setUserId(user.id);
      AnalyticsService().setUserProperties(email: user.email, name: user.name);
      AnalyticsService().logAuthenticationSuccess('apple');

      // Register FCM token with backend after successful login
      FCMService().refreshToken().catchError((error) {
        debugPrint('[Auth] FCM token refresh failed: $error');
      });

      return true;
    } catch (e) {
      state = AuthState.error('Apple sign-in failed: $e');
      return false;
    }
  }

  /// Login with email and password (self-hosted backends only).
  Future<bool> loginWithEmail(String email, String password) async {
    state = AuthState.loading();

    try {
      final response = await ApiService().emailLogin(
        email: email,
        password: password,
      );

      final user = User.fromJson(response['user']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserId, user.id);
      await prefs.setString(AppConstants.keyUserEmail, user.email);
      await prefs.setString(AppConstants.keyUserName, user.name);
      if (user.avatarUrl != null) {
        await prefs.setString(AppConstants.keyUserAvatarUrl, user.avatarUrl!);
      }

      state = AuthState.authenticated(user);

      AnalyticsService().setUserId(user.id);
      AnalyticsService().setUserProperties(email: user.email, name: user.name);
      AnalyticsService().logAuthenticationSuccess('email');

      FCMService().refreshToken().catchError((error) {
        debugPrint('[Auth] FCM token refresh failed: $error');
      });

      return true;
    } catch (e) {
      state = AuthState.error('Login failed: $e');
      return false;
    }
  }

  /// Register with email and password (self-hosted backends only).
  Future<bool> registerWithEmail(String email, String password, String name) async {
    state = AuthState.loading();

    try {
      final response = await ApiService().emailSignup(
        email: email,
        password: password,
        name: name,
      );

      final user = User.fromJson(response['user']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserId, user.id);
      await prefs.setString(AppConstants.keyUserEmail, user.email);
      await prefs.setString(AppConstants.keyUserName, user.name);
      if (user.avatarUrl != null) {
        await prefs.setString(AppConstants.keyUserAvatarUrl, user.avatarUrl!);
      }

      state = AuthState.authenticated(user);

      AnalyticsService().setUserId(user.id);
      AnalyticsService().setUserProperties(email: user.email, name: user.name);
      AnalyticsService().logAuthenticationSuccess('email_signup');

      FCMService().refreshToken().catchError((error) {
        debugPrint('[Auth] FCM token refresh failed: $error');
      });

      return true;
    } catch (e) {
      state = AuthState.error('Registration failed: $e');
      return false;
    }
  }

  /// Delete account permanently.
  ///
  /// Calls backend to delete all user data, then clears local state.
  Future<bool> deleteAccount(String confirmationEmail) async {
    try {
      await ApiService().deleteAccount(confirmationEmail: confirmationEmail);

      // Sign out from Google if signed in
      final googleAuthService = GoogleAuthService();
      if (await googleAuthService.isSignedIn()) {
        await googleAuthService.signOut();
      }

      // Clear all local data
      await _clearLocalAuth();
      return true;
    } catch (e) {
      state = AuthState.error('Account deletion failed: $e');
      return false;
    }
  }

  /// Logout
  ///
  /// Clears JWT token and user info from local storage.
  /// Also signs out from Google if signed in.
  Future<void> logout() async {
    try {
      // Sign out from Google if signed in
      final googleAuthService = GoogleAuthService();
      if (await googleAuthService.isSignedIn()) {
        await googleAuthService.signOut();
      }

      // Clear all local auth data
      await _clearLocalAuth();
    } catch (e) {
      state = AuthState.error('Logout failed: $e');
    }
  }

}

/// Auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// Current user provider (derived from auth state)
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

/// Is authenticated provider (derived from auth state)
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).status == AuthStatus.authenticated;
});
