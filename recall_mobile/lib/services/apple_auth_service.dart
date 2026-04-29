import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Result of Apple Sign-In containing the identity token and optional name.
class AppleSignInResult {
  final String identityToken;
  final String? fullName;

  AppleSignInResult({required this.identityToken, this.fullName});
}

class AppleAuthService {
  static final AppleAuthService _instance = AppleAuthService._internal();
  factory AppleAuthService() => _instance;
  AppleAuthService._internal();

  /// Check if Apple Sign-In is available on this device.
  /// Returns true on iOS 13+, false on Android and other platforms.
  static Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    return await SignInWithApple.isAvailable();
  }

  /// Sign in with Apple.
  ///
  /// Returns [AppleSignInResult] with identity token and optional name,
  /// or null if the user cancelled or an error occurred.
  ///
  /// Note: Apple only provides the user's name on the FIRST authorization.
  /// Subsequent sign-ins will have null name fields.
  Future<AppleSignInResult?> signIn() async {
    try {
      debugPrint('[AppleAuth] Starting sign-in...');

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      if (credential.identityToken == null) {
        debugPrint('[AppleAuth] No identity token received');
        return null;
      }

      // Build full name from given + family name (only available on first auth)
      String? fullName;
      if (credential.givenName != null || credential.familyName != null) {
        final parts = [
          if (credential.givenName != null) credential.givenName!,
          if (credential.familyName != null) credential.familyName!,
        ];
        if (parts.isNotEmpty) {
          fullName = parts.join(' ');
        }
      }

      debugPrint('[AppleAuth] Sign-in successful');
      debugPrint('[AppleAuth] Identity token obtained');
      if (fullName != null) {
        debugPrint('[AppleAuth] Name: $fullName');
      }

      return AppleSignInResult(
        identityToken: credential.identityToken!,
        fullName: fullName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        debugPrint('[AppleAuth] User cancelled sign-in');
        return null;
      }
      debugPrint('[AppleAuth] Authorization error: ${e.code} - ${e.message}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('[AppleAuth] Sign-in error: $e');
      debugPrint('[AppleAuth] Stack trace: $stackTrace');
      return null;
    }
  }
}
