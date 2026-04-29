import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_config_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;
    final serverConfig = ref.watch(serverConfigProvider).value;
    final isSelfHosted = serverConfig?.mode == ServerMode.selfHosted;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  color: AppConstants.textSecondary,
                  onPressed: () => context.go('/server-select'),
                ),
              ),
              const SizedBox(height: 16),
              // Logo
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('ReCall.png', width: 36, height: 36, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'ReKall',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              const Text(
                'Sign in to continue',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              if (isSelfHosted)
                _EmailButton(isLoading: isLoading)
              else
                Column(
                  children: [
                    if (Platform.isIOS) ...[
                      _AppleButton(isLoading: isLoading),
                      const SizedBox(height: 12),
                    ],
                    _GoogleButton(isLoading: isLoading),
                  ],
                ),
              const SizedBox(height: 24),
              Text(
                'By signing in, you agree to our Terms of Service and Privacy Policy',
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.textSecondary.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (authState.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  authState.errorMessage!,
                  style: const TextStyle(color: AppConstants.errorColor, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends ConsumerWidget {
  final bool isLoading;
  const _GoogleButton({required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        child: InkWell(
          onTap: isLoading ? null : () async {
            AppHaptics.buttonPress();
            final success = await ref.read(authProvider.notifier).loginWithGoogle();
            if (!context.mounted) return;
            if (success) {
              AppHaptics.success();
              context.go('/');
            } else {
              AppHaptics.error();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ref.read(authProvider).errorMessage ?? 'Google sign-in failed'),
                  backgroundColor: AppConstants.errorColor,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spacingL,
              horizontal: AppConstants.spacingXL,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppConstants.textSecondary.withValues(alpha: 0.2),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
                    ),
                  )
                else ...[
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFFDB4437)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.g_mobiledata, color: AppConstants.white, size: 20),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppleButton extends ConsumerWidget {
  final bool isLoading;
  const _AppleButton({required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        boxShadow: [
          BoxShadow(
            color: AppConstants.deepSpace.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        child: InkWell(
          onTap: isLoading ? null : () async {
            AppHaptics.buttonPress();
            final success = await ref.read(authProvider.notifier).loginWithApple();
            if (!context.mounted) return;
            if (success) {
              AppHaptics.success();
              context.go('/');
            } else {
              AppHaptics.error();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ref.read(authProvider).errorMessage ?? 'Apple sign-in failed'),
                  backgroundColor: AppConstants.errorColor,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spacingL,
              horizontal: AppConstants.spacingXL,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  const Icon(Icons.apple, color: Colors.white, size: 24),
                  const SizedBox(width: AppConstants.spacingM),
                  const Text(
                    'Continue with Apple',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailButton extends StatelessWidget {
  final bool isLoading;
  const _EmailButton({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : () => context.push('/auth/email'),
        style: FilledButton.styleFrom(
          backgroundColor: AppConstants.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
        ),
        child: const Text(
          'Continue with Email',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
