import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/onboarding_progress_provider.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';
import 'share_guide_dialog.dart';

/// Interactive onboarding checklist card shown on the home feed
class OnboardingChecklist extends ConsumerWidget {
  const OnboardingChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final progress = ref.watch(onboardingStateProvider);

    if (!progress.isLoaded || progress.isComplete) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [
                  AppConstants.surfaceDark,
                  AppConstants.synapseIndigo.withValues(alpha: 0.08),
                ]
              : [
                  AppConstants.white,
                  AppConstants.synapseIndigo.withValues(alpha: 0.04),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: isDarkMode
              ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
              : AppConstants.synapseIndigo.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withValues(alpha: 0.3)
                : AppConstants.synapseIndigo.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
                        : AppConstants.synapseIndigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  child: Icon(
                    Icons.rocket_launch_outlined,
                    size: 20,
                    color: isDarkMode
                        ? AppConstants.synapseIndigoLight
                        : AppConstants.synapseIndigo,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get Started with ReKall',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppConstants.starlight
                              : AppConstants.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${progress.completedCount} of ${progress.totalCount} complete',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Skip button
                GestureDetector(
                  onTap: () {
                    AppHaptics.light();
                    ref
                        .read(onboardingProgressProvider.notifier)
                        .dismiss();
                  },
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode
                          ? AppConstants.slateGray
                          : AppConstants.textTertiary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppConstants.spacingM),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.completedCount / progress.totalCount,
                minHeight: 4,
                backgroundColor: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppConstants.borderColor.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDarkMode
                      ? AppConstants.primaryBlueCyan
                      : AppConstants.synapseIndigo,
                ),
              ),
            ),

            const SizedBox(height: AppConstants.spacingM),

            // Task list
            ...progress.tasks.map((task) => _buildTaskItem(
                  context,
                  ref,
                  task,
                  isDarkMode,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(
    BuildContext context,
    WidgetRef ref,
    OnboardingTask task,
    bool isDarkMode,
  ) {
    return InkWell(
      onTap: task.isComplete
          ? null
          : () => _navigateToTask(context, ref, task.key),
      borderRadius: BorderRadius.circular(AppConstants.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spacingS,
        ),
        child: Row(
          children: [
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: task.isComplete
                    ? (isDarkMode
                        ? AppConstants.primaryBlueCyan
                        : AppConstants.synapseIndigo)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: task.isComplete
                      ? (isDarkMode
                          ? AppConstants.primaryBlueCyan
                          : AppConstants.synapseIndigo)
                      : (isDarkMode
                          ? AppConstants.slateGray.withValues(alpha: 0.5)
                          : AppConstants.borderColor),
                  width: 2,
                ),
              ),
              child: task.isComplete
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: AppConstants.spacingM),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: task.isComplete
                          ? (isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textTertiary)
                          : (isDarkMode
                              ? AppConstants.starlight
                              : AppConstants.textPrimary),
                      decoration:
                          task.isComplete ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (!task.isComplete)
                    Text(
                      task.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDarkMode
                            ? AppConstants.slateGray
                            : AppConstants.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            // Arrow for incomplete tasks
            if (!task.isComplete)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDarkMode
                    ? AppConstants.slateGray
                    : AppConstants.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToTask(BuildContext context, WidgetRef ref, String taskKey) {
    AppHaptics.light();
    switch (taskKey) {
      case 'share':
        showShareGuideDialog(context);
        break;
      case 'search':
        // Push to search screen
        context.push('/search');
        break;
      case 'space':
        // Go to Spaces tab or directly to create
        context.push('/spaces/create');
        break;
    }
  }
}
