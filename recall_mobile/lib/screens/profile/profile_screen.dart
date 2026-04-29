import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_config_provider.dart';
import '../../providers/usage_stats_provider.dart';
import '../../providers/user_preferences_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/app_logo_header.dart';
import '../../widgets/premium_appbar.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final usageStatsState = ref.watch(usageStatsProvider);
    final preferencesState = ref.watch(userPreferencesProvider);

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
      ),
      body: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Profile header with editable photo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppConstants.spacingXL),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppConstants.primaryColor.withValues(alpha: 0.1),
                          AppConstants.primaryColor.withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        // User avatar with gradient border
                        Container(
                          width: 106,
                          height: 106,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: AppConstants.primaryGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppConstants.white,
                            ),
                            child: ClipOval(
                              child: currentUser.avatarUrl != null && currentUser.avatarUrl!.isNotEmpty
                                  ? Image.network(
                                      currentUser.avatarUrl!,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback to initial if image fails to load
                                        return Center(
                                          child: Text(
                                            currentUser.name[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.bold,
                                              color: AppConstants.primaryColor,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : Center(
                                      child: Text(
                                        currentUser.name[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          color: AppConstants.primaryColor,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        Text(
                          currentUser.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingXS),
                        Text(
                          currentUser.email,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppConstants.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppConstants.spacingL),

                  // Usage Tracker Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
                    child: _buildUsageTracker(usageStatsState),
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // About You Section
                  _buildSettingsSection(
                    'About You',
                    [
                      _buildSettingItem(
                        icon: Icons.person_outline,
                        iconColor: AppConstants.primaryColor,
                        title: 'Personal Info',
                        subtitle: 'Bio and social links for your knowledge graph',
                        onTap: () {
                          AppHaptics.buttonPress();
                          context.push('/personal-info');
                        },
                        trailing: const Icon(Icons.chevron_right, size: 20, color: AppConstants.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // Daily Gems Section
                  _buildSettingsSection(
                    'Daily Gems',
                    [
                      _buildSettingItem(
                        icon: Icons.diamond,
                        iconColor: AppConstants.primaryColor,
                        title: 'Enable Daily Gems',
                        subtitle: 'Get personalized content reminders',
                        trailing: Switch(
                          value: preferencesState.preferences?.dailyGemsEnabled ?? false,
                          onChanged: (value) {
                            AppHaptics.buttonPress();
                            ref.read(userPreferencesProvider.notifier).updatePreferences(
                              dailyGemsEnabled: value,
                            );
                          },
                          activeTrackColor: AppConstants.primaryColor.withValues(alpha: 0.5),
                          activeThumbColor: AppConstants.primaryColor,
                        ),
                      ),
                      if (preferencesState.preferences?.dailyGemsEnabled ?? false)
                        _buildSettingItem(
                          icon: Icons.access_time,
                          iconColor: Colors.blue,
                          title: 'Daily Gems Time',
                          subtitle: preferencesState.preferences?.dailyGemsTime ?? '9:00 AM',
                          onTap: () {
                            AppHaptics.buttonPress();
                            _showTimePickerDialog(context);
                          },
                          trailing: const Icon(Icons.chevron_right, size: 20),
                        ),
                    ],
                  ),

                  const SizedBox(height: AppConstants.spacingL),

                  // Account Section
                  _buildSettingsSection(
                    'Account',
                    [
                      _buildSettingItem(
                        icon: Icons.help_outline,
                        iconColor: Colors.blue,
                        title: 'Help & Support',
                        subtitle: 'FAQs and contact support',
                        onTap: () {
                          AppHaptics.buttonPress();
                          context.push('/help');
                        },
                        trailing: const Icon(Icons.chevron_right, size: 20),
                      ),
                      const Divider(height: 1),
                      _buildSettingItem(
                        icon: Icons.logout,
                        iconColor: AppConstants.errorColor,
                        title: 'Log Out',
                        subtitle: 'Sign out of your account',
                        onTap: () {
                          AppHaptics.warning();
                          _showLogoutDialog(context, ref);
                        },
                        trailing: const Icon(Icons.chevron_right, size: 20),
                      ),
                      const Divider(height: 1),
                      _buildSettingItem(
                        icon: Icons.delete_forever,
                        iconColor: AppConstants.errorColor,
                        title: 'Delete Account',
                        subtitle: 'Permanently delete your account and data',
                        onTap: () {
                          AppHaptics.warning();
                          _showDeleteAccountDialog(context, ref);
                        },
                        trailing: const Icon(Icons.chevron_right, size: 20),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // Version Information
                  if (_packageInfo != null)
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Version ${_packageInfo!.version}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppConstants.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: AppConstants.spacingXS),
                          Text(
                            'Build ${_packageInfo!.buildNumber}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppConstants.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppConstants.spacingXXL),
                ],
              ),
            ),
    );
  }

  Widget _buildUsageTracker(UsageStatsState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = state.stats;
    if (stats == null) {
      return const SizedBox.shrink();
    }

    final usagePercentage = (stats.aiSummariesUsed / stats.monthlyLimit) * 100;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppConstants.dividerColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: AppConstants.dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppConstants.primaryGradient,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppConstants.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Summaries',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.textPrimary,
                      ),
                    ),
                    Text(
                      '${stats.aiSummariesUsed} of ${stats.monthlyLimit} used',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppConstants.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${usagePercentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingM),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusS),
            child: LinearProgressIndicator(
              value: usagePercentage / 100,
              minHeight: 8,
              backgroundColor: AppConstants.dividerColor.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                usagePercentage > 80
                    ? AppConstants.errorColor
                    : AppConstants.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppConstants.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingS),
        Container(
          decoration: BoxDecoration(
            color: AppConstants.dividerColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: iconColor == AppConstants.errorColor
              ? AppConstants.errorColor
              : AppConstants.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: AppConstants.textSecondary,
        ),
      ),
      trailing: trailing,
    );
  }

  void _showTimePickerDialog(BuildContext context) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppConstants.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      AppHaptics.buttonPress();
      if (!context.mounted) return;
      final formattedTime = pickedTime.format(context);
      ref.read(userPreferencesProvider.notifier).updatePreferences(
        dailyGemsTime: formattedTime,
      );
    }
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action is permanent. All your saved content, connections, categories, and account data will be permanently deleted.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showDeleteAccountConfirmation(context, ref, currentUser.email);
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirmation(BuildContext context, WidgetRef ref, String userEmail) {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final emailMatches = emailController.text.toLowerCase() == userEmail.toLowerCase();
          return AlertDialog(
            title: const Text('Confirm Deletion'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Type your email address to confirm:',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  userEmail,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'Enter your email',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  AppHaptics.buttonPress();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: emailMatches
                    ? () async {
                        AppHaptics.heavy();
                        Navigator.of(context).pop();
                        // Show loading
                        showDialog(
                          context: this.context,
                          barrierDismissible: false,
                          builder: (_) => const Center(child: CircularProgressIndicator()),
                        );
                        final success = await ref.read(authProvider.notifier).deleteAccount(userEmail);
                        if (!mounted) return;
                        Navigator.of(this.context).pop(); // dismiss loading
                        if (success) {
                          this.context.go('/onboarding');
                        } else {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to delete account. Please try again.'),
                              backgroundColor: AppConstants.errorColor,
                            ),
                          );
                        }
                      }
                    : null,
                style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
                child: const Text('Delete My Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              AppHaptics.heavy();
              Navigator.of(context).pop();
              await ref.read(serverConfigProvider.notifier).clear();
              await ref.read(authProvider.notifier).logout();
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
