import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_button.dart';

/// Welcome screen - matching mobile_mocks/welcome_to_rekall design
/// Landing page for unauthenticated users with CTAs to start using ReKall
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      AppHaptics.buttonPress();
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: Stack(
        children: [
          // Top gradient overlay for subtle depth
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppConstants.primaryColor.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header with logo
                Padding(
                  padding: const EdgeInsets.only(top: 32, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ReKall logo image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'ReCall.png',
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
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
                ),

                // Carousel with pages
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (int page) {
                      setState(() {
                        _currentPage = page;
                      });
                      AppHaptics.selection();
                    },
                    children: [
                      _buildOnboardingPage(
                        visualWidget: _buildCollectionVisual(),
                        title: 'Your Memory,',
                        highlightedTitle: 'Organized',
                        description:
                            'Save articles, capture photos and videos, or share from any app. ReKall builds your personal knowledge graph automatically.',
                      ),
                      _buildOnboardingPage(
                        visualWidget: _buildAIBrainVisual(),
                        title: 'AI Finds',
                        highlightedTitle: 'The Thread',
                        description:
                            'AI reads your photos, extracts text, and connects everything. Your brain says "I saw something about this..." — ReKall finds it.',
                      ),
                      _buildOnboardingPage(
                        visualWidget: _buildCollaborationVisual(),
                        title: 'Never Forget',
                        highlightedTitle: 'What You Saved',
                        description:
                            'Search by what you remember — not exact keywords. Find text in photos, revisit articles, and connect years of knowledge.',
                      ),
                    ],
                  ),
                ),

                // Page indicator
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SmoothPageIndicator(
                    controller: _pageController,
                    count: 3,
                    effect: ExpandingDotsEffect(
                      activeDotColor: AppConstants.primaryColor,
                      dotColor: AppConstants.textSecondary.withValues(alpha: 0.3),
                      dotHeight: 6,
                      dotWidth: 6,
                      expansionFactor: 4,
                      spacing: 8,
                    ),
                  ),
                ),

                // Bottom action area
                Padding(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: 32,
                    top: 12,
                  ),
                  child: Column(
                    children: [
                      PremiumButton.primary(
                        onPressed: _currentPage < 2 ? _nextPage : () => context.go('/server-select'),
                        fullWidth: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage < 2 ? 'Continue' : 'Get Started',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 20),
                          ],
                        ),
                      ),

                      // Home indicator safe area
                      const SizedBox(height: 24),
                      Container(
                        width: 120,
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppConstants.textSecondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingPage({
    required Widget visualWidget,
    required String title,
    required String highlightedTitle,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Visual - constrained size
          Flexible(
            flex: 3,
            child: Center(child: visualWidget),
          ),

          const SizedBox(height: 24),

          // Headline
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5,
              ),
              children: [
                TextSpan(
                  text: '$title\n',
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                  ),
                ),
                TextSpan(
                  text: highlightedTitle,
                  style: const TextStyle(
                    color: AppConstants.primaryColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 15,
                color: AppConstants.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Visual 1: Content Collection - Floating content cards
  Widget _buildCollectionVisual() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
      child: Stack(
          children: [
            // Decorative glow
            Center(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.primaryColor.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
            ),

            // Floating content cards
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Card 1 - Top left
                  Positioned(
                    top: 20,
                    left: 10,
                    child: _buildFloatingCard(
                      icon: Icons.article,
                      delay: 0,
                    ),
                  ),
                  // Card 2 - Top right
                  Positioned(
                    top: 35,
                    right: 15,
                    child: _buildFloatingCard(
                      icon: Icons.link,
                      delay: 0.2,
                    ),
                  ),
                  // Card 3 - Center
                  _buildFloatingCard(
                    icon: Icons.video_library,
                    delay: 0.4,
                    isLarge: true,
                  ),
                  // Card 4 - Bottom left
                  Positioned(
                    bottom: 35,
                    left: 20,
                    child: _buildFloatingCard(
                      icon: Icons.photo,
                      delay: 0.6,
                    ),
                  ),
                  // Card 5 - Bottom right
                  Positioned(
                    bottom: 45,
                    right: 25,
                    child: _buildFloatingCard(
                      icon: Icons.notes,
                      delay: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildFloatingCard({
    required IconData icon,
    required double delay,
    bool isLarge = false,
  }) {
    final size = isLarge ? 70.0 : 50.0;
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: (1000 + delay * 1000).toInt()),
      curve: Curves.easeOut,
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppConstants.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.primaryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: AppConstants.primaryColor,
                  size: isLarge ? 32 : 24,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Visual 2: AI Brain - Neural network visualization
  Widget _buildAIBrainVisual() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
      child: Stack(
          children: [
            // Decorative glow effect
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.primaryColor.withValues(alpha: 0.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 60,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),

            // Main image container with network visualization
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.deepSpace.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppConstants.primaryColor.withValues(alpha: 0.3),
                        AppConstants.backgroundColor,
                      ],
                      center: Alignment.center,
                      radius: 0.8,
                    ),
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Animated pulsing rings
                        for (int i = 0; i < 3; i++)
                          _buildPulsingRing(
                            size: 100.0 + (i * 40),
                            delay: i * 0.3,
                          ),
                        // Center brain icon with glow
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppConstants.primaryColor,
                                AppConstants.primaryColor.withValues(alpha: 0.6),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppConstants.primaryColor.withValues(alpha: 0.5),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.psychology,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                        // Orbiting dots (synapses)
                        for (int i = 0; i < 6; i++)
                          _buildOrbitingDot(
                            angle: i * 60.0,
                            radius: 75.0,
                            delay: i * 0.2,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildPulsingRing({required double size, required double delay}) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeInOut,
      builder: (context, double value, child) {
        return Opacity(
          opacity: (1 - value) * 0.3,
          child: Container(
            width: size * (0.5 + value * 0.5),
            height: size * (0.5 + value * 0.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppConstants.primaryColor,
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrbitingDot({
    required double angle,
    required double radius,
    required double delay,
  }) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOut,
      builder: (context, double value, child) {
        final radian = (angle + value * 360) * 3.14159 / 180;
        final x = radius * value * 0.8;
        return Transform.translate(
          offset: Offset(
            x * (radian.isNaN ? 0 : (angle / 180)),
            x * (radian.isNaN ? 0 : ((angle - 90) / 180)),
          ),
          child: Opacity(
            opacity: value,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryColor.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Visual 3: Collaboration - Connected nodes/spaces
  Widget _buildCollaborationVisual() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
      child: Stack(
          children: [
            // Decorative glow
            Center(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.primaryColor.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
            ),

            // Network of connected spaces
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Connection lines
                  CustomPaint(
                    size: const Size(240, 240),
                    painter: _ConnectionLinesPainter(),
                  ),
                  // Center space
                  _buildSpaceNode(
                    icon: Icons.workspaces,
                    delay: 0,
                    offset: Offset.zero,
                  ),
                  // Surrounding spaces
                  _buildSpaceNode(
                    icon: Icons.people,
                    delay: 0.2,
                    offset: const Offset(-65, -50),
                  ),
                  _buildSpaceNode(
                    icon: Icons.folder,
                    delay: 0.4,
                    offset: const Offset(65, -50),
                  ),
                  _buildSpaceNode(
                    icon: Icons.share,
                    delay: 0.6,
                    offset: const Offset(-65, 50),
                  ),
                  _buildSpaceNode(
                    icon: Icons.group,
                    delay: 0.8,
                    offset: const Offset(65, 50),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildSpaceNode({
    required IconData icon,
    required double delay,
    required Offset offset,
  }) {
    final isCenter = offset == Offset.zero;
    final size = isCenter ? 70.0 : 50.0;
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: (1000 + delay * 1000).toInt()),
      curve: Curves.elasticOut,
      builder: (context, double value, child) {
        return Transform.translate(
          offset: offset * value,
          child: Opacity(
            opacity: value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isCenter
                      ? [
                          AppConstants.primaryColor,
                          AppConstants.primaryColor.withValues(alpha: 0.7),
                        ]
                      : [
                          AppConstants.surfaceColor,
                          AppConstants.surfaceColor,
                        ],
                ),
                border: Border.all(
                  color: AppConstants.primaryColor.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isCenter ? Colors.white : AppConstants.primaryColor,
                  size: isCenter ? 32 : 24,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

}

// Custom painter for connection lines
class _ConnectionLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryColor.withValues(alpha: 0.2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final points = [
      Offset(center.dx - 65, center.dy - 50),
      Offset(center.dx + 65, center.dy - 50),
      Offset(center.dx - 65, center.dy + 50),
      Offset(center.dx + 65, center.dy + 50),
    ];

    for (final point in points) {
      canvas.drawLine(center, point, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
