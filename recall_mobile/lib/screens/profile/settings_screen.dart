import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_config_provider.dart';
import '../../providers/ui_providers.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/app_logo_header.dart';
import '../../widgets/premium_appbar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppConstants.spacingL),

            // Appearance Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              child: Text(
                'Appearance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),

            // Theme selector
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              padding: const EdgeInsets.all(AppConstants.spacingL),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusL),
                border: Border.all(color: AppConstants.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Theme Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  _buildThemeSelector(ref),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.spacingXL),

            // Data Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              child: Text(
                'Data',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),

            // Import Bookmarks
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusL),
                border: Border.all(color: AppConstants.borderColor),
              ),
              child: ListTile(
                leading: Icon(Icons.file_upload_outlined, color: AppConstants.primaryBlueCyan),
                title: const Text(
                  'Import Bookmarks',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text('Chrome, Pocket, Raindrop.io'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  AppHaptics.buttonPress();
                  context.push('/import');
                },
              ),
            ),

            const SizedBox(height: AppConstants.spacingXL),

            // Server Section
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingL),
              child: Text(
                'Server',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),

            Consumer(
              builder: (context, ref, _) {
                final serverConfig =
                    ref.watch(serverConfigProvider).value;
                final url = serverConfig?.url ?? '—';
                final modeLabel = serverConfig == null
                    ? '—'
                    : serverConfig.mode == ServerMode.cloud
                        ? 'ReKall Cloud'
                        : 'Self-hosted';

                return Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingL),
                  padding: const EdgeInsets.all(AppConstants.spacingL),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusL),
                    border: Border.all(color: AppConstants.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modeLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        url,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppConstants.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppConstants.spacingM),
                      GestureDetector(
                        onTap: () async {
                          await ref
                              .read(serverConfigProvider.notifier)
                              .clear();
                          await ref
                              .read(authProvider.notifier)
                              .logout();
                          if (context.mounted) {
                            context.go('/server-select');
                          }
                        },
                        child: const Text(
                          'Switch server',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppConstants.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppConstants.spacingXL),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelector(WidgetRef ref) {
    final currentTheme = ref.watch(themeModeProvider);

    return Row(
      children: [
        Expanded(
          child: _buildThemeOption(
            ref,
            ThemeMode.light,
            Icons.light_mode,
            'Light',
            currentTheme == ThemeMode.light,
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: _buildThemeOption(
            ref,
            ThemeMode.dark,
            Icons.dark_mode,
            'Dark',
            currentTheme == ThemeMode.dark,
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: _buildThemeOption(
            ref,
            ThemeMode.system,
            Icons.brightness_auto,
            'Auto',
            currentTheme == ThemeMode.system,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOption(
    WidgetRef ref,
    ThemeMode mode,
    IconData icon,
    String label,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () {
        AppHaptics.selection();
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingM),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: AppConstants.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : AppConstants.borderColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          border: Border.all(
            color: isSelected ? AppConstants.primaryColor : AppConstants.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppConstants.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : AppConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
