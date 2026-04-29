import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/notification_settings_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';

/// Notification settings screen.
///
/// Allows users to:
/// - Enable/disable daily notifications
/// - Set notification time (with local time picker)
/// - View last notification sent timestamp
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(notificationSettingsProvider);
    final settings = settingsState.settings;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: PremiumAppBar.glassmorphic(
        title: 'Notification Settings',
      ),
      body: settingsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : settings == null
              ? _buildErrorState(context, settingsState.errorMessage)
              : _buildSettingsContent(context, ref, settings),
    );
  }

  Widget _buildErrorState(BuildContext context, String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppConstants.errorColor,
            ),
            const SizedBox(height: AppConstants.spacingM),
            Text(
              errorMessage ?? 'Failed to load settings',
              style: const TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContent(
    BuildContext context,
    WidgetRef ref,
    settings,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      children: [
        // Info Card
        _buildInfoCard(),
        const SizedBox(height: AppConstants.spacingL),

        // Enable/Disable Toggle
        _buildEnableToggle(context, ref, settings),
        const SizedBox(height: AppConstants.spacingM),

        // Time Picker
        _buildTimePicker(context, ref, settings),
        const SizedBox(height: AppConstants.spacingL),

        // Last Notification
        if (settings.lastNotificationSentAt != null)
          _buildLastNotification(settings),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.electricIndigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        border: Border.all(
          color: AppConstants.electricIndigo.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.diamond_outlined,
            color: AppConstants.electricIndigo,
            size: 32,
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Gem Notifications',
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXS),
                Text(
                  'Get one carefully selected item from your saved content each day',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnableToggle(BuildContext context, WidgetRef ref, settings) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        border: Border.all(
          color: AppConstants.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            settings.isEnabled ? Icons.notifications_active : Icons.notifications_off,
            color: settings.isEnabled ? AppConstants.electricIndigo : AppConstants.textSecondary,
            size: 24,
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Notifications',
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXS),
                Text(
                  settings.isEnabled ? 'Notifications are active' : 'Tap to enable',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: settings.isEnabled,
            onChanged: (enabled) {
              AppHaptics.selection();
              ref.read(notificationSettingsProvider.notifier).setEnabled(enabled);
            },
            activeThumbColor: AppConstants.electricIndigo,
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context, WidgetRef ref, settings) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        border: Border.all(
          color: AppConstants.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time,
            color: AppConstants.electricIndigo,
            size: 24,
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification Time',
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXS),
                Text(
                  settings.notificationTimeLocal,
                  style: const TextStyle(
                    color: AppConstants.electricIndigo,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              _showTimePicker(context, ref, settings);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.electricIndigo,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingM,
                vertical: AppConstants.spacingS,
              ),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildLastNotification(dynamic settings) {
    final formattedDate = DateFormat('MMM d, yyyy \'at\' h:mm a')
        .format(settings.lastNotificationSentAt!.toLocal());

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        border: Border.all(
          color: AppConstants.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            color: AppConstants.textSecondary,
            size: 24,
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Notification',
                  style: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXS),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimePicker(BuildContext context, WidgetRef ref, settings) async {
    // Parse current time
    final timeParts = settings.notificationTimeLocal.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppConstants.electricIndigo,
              onPrimary: AppConstants.white,
              surface: AppConstants.surfaceColor,
              onSurface: AppConstants.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && context.mounted) {
      // Format time as "HH:MM"
      final localTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

      // Calculate UTC offset in minutes
      final now = DateTime.now();
      final utcOffsetMinutes = now.timeZoneOffset.inMinutes;

      // Update settings
      await ref.read(notificationSettingsProvider.notifier).setNotificationTime(
            localTime: localTime,
            utcOffsetMinutes: utcOffsetMinutes,
          );
    }
  }
}
