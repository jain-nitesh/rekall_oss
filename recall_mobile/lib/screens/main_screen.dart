import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ui_providers.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';
import 'home/home_screen.dart';
import 'spaces/spaces_list_screen.dart';
import 'brain/brain_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with TickerProviderStateMixin {
  late List<AnimationController> _iconControllers;
  late List<Animation<double>> _iconScaleAnimations;

  @override
  void initState() {
    super.initState();
    // Create animation controllers for each tab icon (4 tabs)
    _iconControllers = List.generate(
      4,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      ),
    );

    _iconScaleAnimations = _iconControllers.map((controller) {
      return Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOutBack),
      );
    }).toList();

    // Animate the first icon (Feed) as it's selected by default
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iconControllers[0].forward();
    });
  }

  @override
  void dispose() {
    for (var controller in _iconControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTabTapped(int index, int currentIndex) {
    AppHaptics.selection();

    // Reverse previous tab animation
    if (currentIndex < _iconControllers.length) {
      _iconControllers[currentIndex].reverse();
    }

    // Forward new tab animation
    _iconControllers[index].forward();

    ref.read(bottomNavProvider.notifier).setIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(bottomNavProvider);

    // 4 tabs: Feed, Brain, Spaces, Profile
    const screens = [
      HomeScreen(),           // Tab 0: Feed
      BrainScreen(),          // Tab 1: Brain (promoted!)
      SpacesListScreen(),     // Tab 2: Spaces
      ProfileScreen(),        // Tab 3: Profile
    ];

    // Guard against stale index from previous session with 5 tabs
    final safeIndex = currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      extendBody: false,
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
      bottomNavigationBar: _buildGlassmorphicBottomNav(safeIndex),
    );
  }

  Widget _buildGlassmorphicBottomNav(int currentIndex) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final navItems = [
      _NavItem(
        icon: Icons.feed_outlined,
        activeIcon: Icons.feed,
        label: 'Feed',
      ),
      _NavItem(
        icon: Icons.psychology_outlined,
        activeIcon: Icons.psychology,
        label: 'Brain',
      ),
      _NavItem(
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view,
        label: 'Spaces',
      ),
      _NavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
      ),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppConstants.blurElevated,
          sigmaY: AppConstants.blurElevated,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? AppConstants.surfaceDark.withValues(alpha: 0.95)
                : AppConstants.white.withValues(alpha: 0.95),
            border: Border(
              top: BorderSide(
                width: 1,
                color: isDarkMode
                    ? AppConstants.starlight.withValues(alpha: 0.05)
                    : AppConstants.borderColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: SafeArea(
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingS,
                vertical: AppConstants.spacingXS,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = index == currentIndex;

                  return Expanded(
                    child: InkWell(
                      onTap: () => _onTabTapped(index, currentIndex),
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ScaleTransition(
                            scale: _iconScaleAnimations[index],
                            child: Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: isSelected
                                  ? AppConstants.primaryBlueCyan
                                  : (isDarkMode
                                      ? AppConstants.slateGray
                                      : AppConstants.textSecondary),
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Active indicator dot
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: isSelected ? 4 : 0,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppConstants.primaryBlueCyan,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected
                                  ? AppConstants.primaryBlueCyan
                                  : (isDarkMode
                                      ? AppConstants.slateGray
                                      : AppConstants.textSecondary),
                            ),
                            child: Text(item.label),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
