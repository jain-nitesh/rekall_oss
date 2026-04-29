import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/personal_info.dart';
import '../../providers/personal_info_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';

class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final _bioController = TextEditingController();
  final _linkedinController = TextEditingController();
  final _twitterController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _githubController = TextEditingController();
  final _websiteController = TextEditingController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Load personal info on screen open
    Future.microtask(() {
      ref.read(personalInfoProvider.notifier).loadPersonalInfo();
    });
  }

  @override
  void dispose() {
    _bioController.dispose();
    _linkedinController.dispose();
    _twitterController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _githubController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _populateFields() {
    final info = ref.read(personalInfoProvider).info;
    if (info != null && !_initialized) {
      _bioController.text = info.bio ?? '';
      final links = info.socialLinks ?? {};
      _linkedinController.text = links['linkedin'] ?? '';
      _twitterController.text = links['twitter'] ?? '';
      _facebookController.text = links['facebook'] ?? '';
      _instagramController.text = links['instagram'] ?? '';
      _githubController.text = links['github'] ?? '';
      _websiteController.text = links['website'] ?? '';
      _initialized = true;
    }
  }

  Future<void> _save() async {
    AppHaptics.buttonPress();

    final socialLinks = <String, String>{};
    if (_linkedinController.text.trim().isNotEmpty) {
      socialLinks['linkedin'] = _linkedinController.text.trim();
    }
    if (_twitterController.text.trim().isNotEmpty) {
      socialLinks['twitter'] = _twitterController.text.trim();
    }
    if (_facebookController.text.trim().isNotEmpty) {
      socialLinks['facebook'] = _facebookController.text.trim();
    }
    if (_instagramController.text.trim().isNotEmpty) {
      socialLinks['instagram'] = _instagramController.text.trim();
    }
    if (_githubController.text.trim().isNotEmpty) {
      socialLinks['github'] = _githubController.text.trim();
    }
    if (_websiteController.text.trim().isNotEmpty) {
      socialLinks['website'] = _websiteController.text.trim();
    }

    await ref.read(personalInfoProvider.notifier).savePersonalInfo(
      bio: _bioController.text.trim(),
      socialLinks: socialLinks.isNotEmpty ? socialLinks : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(personalInfoProvider);

    // Populate fields once data loads
    if (!state.isLoading && state.info != null) {
      _populateFields();
    }

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        title: 'About You',
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Explanation
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spacingM),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: AppConstants.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        Expanded(
                          child: Text(
                            'Tell ReKall about yourself to personalize your knowledge graph and improve content attribution.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppConstants.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // Bio Section
                  const Text(
                    'Bio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingS),
                  TextField(
                    controller: _bioController,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: 'Your role, interests, expertise...',
                      hintStyle: TextStyle(color: AppConstants.textSecondary.withValues(alpha: 0.5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppConstants.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppConstants.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.all(AppConstants.spacingM),
                    ),
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // Social Links Section
                  const Text(
                    'Social Links',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXS),
                  Text(
                    'We\'ll fetch your public profile data to enrich your knowledge graph.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppConstants.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingM),

                  _buildSocialField(
                    controller: _linkedinController,
                    icon: Icons.work_outline,
                    label: 'LinkedIn',
                    hint: 'https://linkedin.com/in/username',
                  ),
                  _buildSocialField(
                    controller: _twitterController,
                    icon: Icons.alternate_email,
                    label: 'Twitter / X',
                    hint: 'https://x.com/username',
                  ),
                  _buildSocialField(
                    controller: _facebookController,
                    icon: Icons.facebook,
                    label: 'Facebook',
                    hint: 'https://facebook.com/username',
                  ),
                  _buildSocialField(
                    controller: _instagramController,
                    icon: Icons.camera_alt_outlined,
                    label: 'Instagram',
                    hint: 'https://instagram.com/username',
                  ),
                  _buildSocialField(
                    controller: _githubController,
                    icon: Icons.code,
                    label: 'GitHub',
                    hint: 'https://github.com/username',
                  ),
                  _buildSocialField(
                    controller: _websiteController,
                    icon: Icons.language,
                    label: 'Personal Website',
                    hint: 'https://yoursite.com',
                  ),

                  const SizedBox(height: AppConstants.spacingXL),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: PremiumButton(
                      onPressed: state.isSaving ? null : _save,
                      isLoading: state.isSaving,
                      gradient: const LinearGradient(
                        colors: AppConstants.primaryGradient,
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // Status messages
                  if (state.successMessage != null) ...[
                    const SizedBox(height: AppConstants.spacingM),
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spacingM),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          const SizedBox(width: AppConstants.spacingS),
                          Expanded(
                            child: Text(
                              state.successMessage!,
                              style: const TextStyle(color: Colors.green, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (state.errorMessage != null) ...[
                    const SizedBox(height: AppConstants.spacingM),
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spacingM),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: AppConstants.spacingS),
                          Expanded(
                            child: Text(
                              state.errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Enriched Data Preview
                  if (state.info?.hasEnrichedData == true) ...[
                    const SizedBox(height: AppConstants.spacingXL),
                    _buildEnrichedDataSection(state.info!),
                  ],

                  // Last refreshed
                  if (state.info?.lastRefreshedAt != null) ...[
                    const SizedBox(height: AppConstants.spacingM),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sync, size: 14, color: AppConstants.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Last updated: ${_formatDate(state.info!.lastRefreshedAt!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppConstants.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        GestureDetector(
                          onTap: state.isSaving ? null : _save,
                          child: Text(
                            'Refresh',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: AppConstants.spacingXL),
                ],
              ),
            ),
    );
  }

  Widget _buildSocialField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20, color: AppConstants.textSecondary),
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: AppConstants.textSecondary.withValues(alpha: 0.4), fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppConstants.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppConstants.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppConstants.primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
            vertical: AppConstants.spacingS,
          ),
        ),
      ),
    );
  }

  Widget _buildEnrichedDataSection(PersonalInfo personalInfo) {
    final enriched = personalInfo.enrichedData as Map<String, dynamic>;
    final validEntries = enriched.entries
        .where((e) => e.value is Map && !(e.value as Map).containsKey('error'))
        .toList();

    if (validEntries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fetched Profile Data',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppConstants.textPrimary,
          ),
        ),
        const SizedBox(height: AppConstants.spacingS),
        ...validEntries.map((entry) {
          final platform = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final displayName = platform[0].toUpperCase() + platform.substring(1);

          // Pick the most meaningful field to show
          String? snippet;
          if (data.containsKey('headline')) { snippet = data['headline']; }
          else if (data.containsKey('bio')) { snippet = data['bio']; }
          else if (data.containsKey('about')) { snippet = data['about']; }
          else if (data.containsKey('summary')) { snippet = data['summary']; }

          if (snippet == null) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppConstants.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppConstants.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppConstants.textPrimary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
