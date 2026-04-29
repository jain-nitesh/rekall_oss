import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for logo glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _navigateToNext();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    // Wait for authentication check
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final authState = ref.read(authProvider);

    if (authState.status == AuthStatus.authenticated) {
      // Check for pending invite token
      final pendingInviteToken = prefs.getString(AppConstants.keyPendingInviteToken);

      if (pendingInviteToken != null && pendingInviteToken.isNotEmpty) {
        debugPrint('[Splash] Found pending invite token, redirecting to invite handler');
        // Clear the pending invite token
        await prefs.remove(AppConstants.keyPendingInviteToken);
        // Redirect to invite handler
        if (!mounted) return;
        context.go('/invite/$pendingInviteToken');
      } else {
        context.go('/');
      }
    } else {
      // For unauthenticated users, always show welcome screen first
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.deepSpace,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppConstants.deepSpace,
              AppConstants.deepSpace.withValues(alpha: 0.95),
              AppConstants.synapseIndigo.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ReKall Logo with pulsing glow effect
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(AppConstants.spacingL),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppConstants.synapseIndigo.withValues(alpha: 0.15 * _pulseAnimation.value),
                          Colors.transparent,
                        ],
                        stops: const [0.3, 1.0],
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.white,
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.recallCyan.withValues(alpha: 0.3 * _pulseAnimation.value),
                            blurRadius: 30 * _pulseAnimation.value,
                            spreadRadius: 5 * _pulseAnimation.value,
                          ),
                          BoxShadow(
                            color: AppConstants.synapseIndigo.withValues(alpha: 0.2 * _pulseAnimation.value),
                            blurRadius: 50 * _pulseAnimation.value,
                            spreadRadius: 10 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'ReCall.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // ReKall Text with gradient
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    AppConstants.starlight,
                    AppConstants.recallCyan,
                  ],
                ).createShader(bounds),
                child: const Text(
                  'ReKall',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingM),

              // Tagline
              Text(
                'Your Memory, Organized.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.slateGray,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: AppConstants.spacingXXL),

              // Progress indicator with Recall Cyan
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppConstants.recallCyan,
                  ),
                  backgroundColor: AppConstants.slateGray.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
