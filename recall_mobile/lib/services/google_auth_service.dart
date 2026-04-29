import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;

  // Configure GoogleSignIn with scopes and server client ID
  late final GoogleSignIn _googleSignIn;

  GoogleAuthService._internal() {
    // Initialize with configuration
    // MANDATORY: Use the "Web Client ID" from Firebase Console (OAuth 2.0 Client ID for Web application)
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: '786553632548-opddbund7n62t8309h2tr53er8h8tgdb.apps.googleusercontent.com',
    );
  }

  /// Initialize service (optional for compatibility, config is done in constructor)
  Future<void> initialize() async {
    debugPrint('[GoogleAuth] Service initialized');
  }

  Future<String?> signIn() async {
    try {
      debugPrint('[GoogleAuth] Starting sign-in...');
      debugPrint('[GoogleAuth] Server Client ID: ${_googleSignIn.clientId}');

      // 1. Sign in with Google
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        debugPrint('[GoogleAuth] User cancelled sign-in');
        return null;
      }

      debugPrint('[GoogleAuth] Account obtained: ${account.email}');

      // 2. Retrieve authentication tokens
      final GoogleSignInAuthentication auth = await account.authentication;

      if (auth.idToken == null) {
        debugPrint('[GoogleAuth] ❌ No ID token received');
        debugPrint('[GoogleAuth] This usually means:');
        debugPrint('[GoogleAuth] 1. SHA-1 certificate not added to Firebase Console');
        debugPrint('[GoogleAuth] 2. Wrong or missing serverClientId');
        debugPrint('[GoogleAuth] 3. OAuth consent screen not configured');
        return null;
      }

      debugPrint('[GoogleAuth] ✓ Sign-in successful: ${account.email}');
      debugPrint('[GoogleAuth] ✓ ID token obtained');
      return auth.idToken;
    } catch (e, stackTrace) {
      debugPrint('[GoogleAuth] ❌ Sign-in error: $e');
      debugPrint('[GoogleAuth] Error type: ${e.runtimeType}');
      debugPrint('[GoogleAuth] Stack trace: $stackTrace');

      // Common errors:
      // - PlatformException(sign_in_failed, ...) = Configuration issue
      // - PlatformException(network_error, ...) = Network issue
      // - DEVELOPER_ERROR = Wrong serverClientId or missing SHA-1
      // - API_DISABLED = OAuth consent screen or API not enabled
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('[GoogleAuth] Signed out successfully');
    } catch (e) {
      debugPrint('[GoogleAuth] Sign-out error: $e');
    }
  }

  /// Check if user is currently signed in
  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      debugPrint('[GoogleAuth] Error checking sign-in status: $e');
      return false;
    }
  }

  /// Silently sign in if user was previously signed in
  Future<String?> signInSilently() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account == null) {
        return null;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      return auth.idToken;
    } catch (e) {
      debugPrint('[GoogleAuth] Silent sign-in error: $e');
      return null;
    }
  }

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
}
