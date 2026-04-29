import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/spaces_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';

/// Screen that handles invite token deep links
/// Automatically joins the user to a space using the provided token
class InviteHandlerScreen extends ConsumerStatefulWidget {
  final String token;

  const InviteHandlerScreen({
    super.key,
    required this.token,
  });

  @override
  ConsumerState<InviteHandlerScreen> createState() => _InviteHandlerScreenState();
}

class _InviteHandlerScreenState extends ConsumerState<InviteHandlerScreen> {
  bool _isProcessing = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _processInvite();
  }

  Future<void> _processInvite() async {
    setState(() {
      _isProcessing = true;
      _hasError = false;
      _errorMessage = null;
    });

    // Check if user is authenticated
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated) {
      // Save invite token for later and redirect to login
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.keyPendingInviteToken, widget.token);

        AppHaptics.light();
        setState(() {
          _isProcessing = false;
          _hasError = true;
          _errorMessage = 'Please sign in or create an account to accept this invitation';
        });
      } catch (e) {
        AppHaptics.error();
        setState(() {
          _isProcessing = false;
          _hasError = true;
          _errorMessage = 'Failed to save invitation. Please try again.';
        });
      }
      return;
    }

    // Attempt to join the space
    try {
      final space = await ref.read(spacesProvider.notifier).joinSpace(widget.token);

      if (space != null) {
        AppHaptics.success();
        setState(() {
          _isProcessing = false;
        });

        // Auto-navigate to space after a brief delay
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          // Navigate to space detail (user can go back to feed from there)
          context.go('/spaces/${space.id}');
        }
      } else {
        AppHaptics.error();
        setState(() {
          _isProcessing = false;
          _hasError = true;
          _errorMessage = ref.read(spacesProvider).errorMessage ??
              'Failed to join space. The invitation may be invalid or expired.';
        });
      }
    } catch (e) {
      AppHaptics.error();
      setState(() {
        _isProcessing = false;
        _hasError = true;
        _errorMessage = 'An error occurred while processing the invitation';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.white,
      appBar: PremiumAppBar.glassmorphic(
        leading: _hasError
            ? PremiumIconButton(
                icon: Icons.close,
                onPressed: () {
                  AppHaptics.buttonPress();
                  context.go('/');
                },
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isProcessing) ...[
                // Processing state
                Container(
                  padding: const EdgeInsets.all(AppConstants.spacingXL),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXL),
                const Text(
                  'Processing Invitation',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacingM),
                const Text(
                  'Please wait while we add you to the space...',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else if (_hasError) ...[
                // Error state with gradient border
                Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppConstants.errorColor,
                        AppConstants.errorColor.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.white,
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      size: AppConstants.iconMassive,
                      color: AppConstants.errorColor,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXL),
                const Text(
                  'Invitation Failed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacingM),
                Text(
                  _errorMessage ?? 'Something went wrong',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacingXL),
                PremiumButton.primary(
                  onPressed: () {
                    AppHaptics.buttonPress();
                    final authState = ref.read(authProvider);
                    if (authState.status != AuthStatus.authenticated) {
                      // Redirect to onboarding/sign-in
                      context.go('/onboarding');
                    } else {
                      // Try again
                      _processInvite();
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ref.read(authProvider).status != AuthStatus.authenticated
                            ? Icons.login
                            : Icons.refresh,
                        size: 20,
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      Text(
                        ref.read(authProvider).status != AuthStatus.authenticated
                            ? 'Sign In'
                            : 'Try Again',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                TextButton(
                  onPressed: () {
                    AppHaptics.buttonPress();
                    context.go('/');
                  },
                  child: const Text('Go to Home'),
                ),
              ] else ...[
                // Success state with gradient border
                Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppConstants.successColor,
                        const Color(0xFF34D399),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.white,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: AppConstants.iconMassive,
                      color: AppConstants.successColor,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXL),
                const Text(
                  'Successfully Joined!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacingM),
                const Text(
                  'Redirecting to space...',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppConstants.spacingL),
                const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppConstants.successColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
