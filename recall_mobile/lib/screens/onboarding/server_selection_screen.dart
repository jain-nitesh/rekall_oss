import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/server_config_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class ServerSelectionScreen extends ConsumerStatefulWidget {
  const ServerSelectionScreen({super.key});

  @override
  ConsumerState<ServerSelectionScreen> createState() =>
      _ServerSelectionScreenState();
}

class _ServerSelectionScreenState extends ConsumerState<ServerSelectionScreen> {
  final _urlController = TextEditingController();
  bool _showUrlField = false;
  bool _isValidating = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _selectCloud() async {
    AppHaptics.buttonPress();
    await ref.read(serverConfigProvider.notifier).setCloud();
    if (mounted) context.go('/auth');
  }

  Future<void> _connectSelfHosted() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _error = 'Enter your server URL');
      return;
    }

    // Normalise — add http:// if no scheme provided
    var url = rawUrl.startsWith('http') ? rawUrl : 'http://$rawUrl';

    // Android emulator uses 10.0.2.2 to reach the host machine's localhost
    if (Platform.isAndroid) {
      url = url
          .replaceFirst('localhost', '10.0.2.2')
          .replaceFirst('127.0.0.1', '10.0.2.2');
    }
    final healthUrl = '${url.replaceAll(RegExp(r'/api$'), '')}/health';

    setState(() {
      _isValidating = true;
      _error = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final response = await dio.get(healthUrl);
      if (response.statusCode != 200) throw Exception('Unexpected status');

      // Ensure URL ends with /api for the mobile client
      final apiUrl = url.endsWith('/api') ? url : '$url/api';
      await ref.read(serverConfigProvider.notifier).setSelfHosted(apiUrl);

      if (mounted) {
        AppHaptics.success();
        context.go('/auth');
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
        _error = 'Could not reach server — check the URL and try again';
      });
      AppHaptics.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: AppConstants.spacingXXL,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spacingXXL),
              const Text(
                'Where is your\nReKall data?',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppConstants.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: AppConstants.spacingM),
              const Text(
                'Connect to the ReKall Cloud or your own self-hosted backend.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppConstants.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXXL),

              // Cloud card
              _SelectionCard(
                icon: Icons.cloud_outlined,
                title: 'ReKall Cloud',
                subtitle: 'Managed hosting — get started instantly',
                onTap: _selectCloud,
              ),
              const SizedBox(height: AppConstants.spacingM),

              // Self-hosted card
              _SelectionCard(
                icon: Icons.dns_outlined,
                title: 'Connect your server',
                subtitle: 'Self-hosted — your data, your infrastructure',
                onTap: () {
                  AppHaptics.selection();
                  setState(() {
                    _showUrlField = true;
                    _error = null;
                  });
                },
              ),

              if (_showUrlField) ...[
                const SizedBox(height: AppConstants.spacingM),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'localhost:8000  (or 192.168.1.x:8000)',
                    errorText: _error,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusM),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingM,
                      vertical: AppConstants.spacingM,
                    ),
                  ),
                  onSubmitted: (_) => _connectSelfHosted(),
                ),
                const SizedBox(height: AppConstants.spacingM),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isValidating ? null : _connectSelfHosted,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppConstants.spacingM),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusM),
                      ),
                    ),
                    child: _isValidating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Connect',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusL),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          border: Border.all(color: AppConstants.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusM),
              ),
              child: Icon(icon, color: AppConstants.primaryColor, size: 22),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppConstants.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
