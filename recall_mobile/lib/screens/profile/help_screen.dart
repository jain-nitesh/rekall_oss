import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const String supportEmail = 'support@YOUR_DOMAIN.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        title: 'Help & Support',
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppConstants.spacingL),

            // Support Section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              padding: const EdgeInsets.all(AppConstants.spacingL),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusL),
                border: Border.all(
                  color: AppConstants.primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.support_agent,
                    size: 48,
                    color: AppConstants.primaryColor,
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  const Text(
                    'Need Help?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingS),
                  const Text(
                    'Contact our support team',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppConstants.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  PremiumButton.primary(
                    onPressed: () {
                      AppHaptics.buttonPress();
                      _sendEmail();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.email, size: 20),
                        const SizedBox(width: AppConstants.spacingS),
                        Text(supportEmail),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.spacingXL),

            // FAQ Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              child: Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: AppConstants.spacingM),

            // FAQ Items
            _buildFAQItem(
              question: 'How do I save content to ReKall?',
              answer:
                  'Use the Share button in any app and select ReKall. The content will be automatically saved and organized with AI-powered categorization.',
            ),
            _buildFAQItem(
              question: 'What are Spaces?',
              answer:
                  'Spaces are shared collections where you can organize and collaborate on content with others. Create a space for projects, interests, or any topic you want to organize.',
            ),
            _buildFAQItem(
              question: 'How does AI categorization work?',
              answer:
                  'ReKall uses advanced AI to automatically analyze your content, extract key information, generate summaries, and categorize it for easy retrieval.',
            ),
            _buildFAQItem(
              question: 'Can I search my saved content?',
              answer:
                  'Yes! Use the search feature to find content by keywords, tags, or semantic similarity. ReKall understands context and meaning, not just exact matches.',
            ),
            _buildFAQItem(
              question: 'How do I mark content as done?',
              answer:
                  'Tap the checkmark icon in the content detail screen or on a content card. This helps you track which items you\'ve reviewed or completed.',
            ),
            _buildFAQItem(
              question: 'What is the Memory Feed?',
              answer:
                  'The Memory Feed resurfaces your saved content based on when you saved it (7 days, 30 days, 1 year ago), helping you rediscover valuable information.',
            ),
            _buildFAQItem(
              question: 'Can I delete content?',
              answer:
                  'Yes, tap the three-dot menu on any content card or in the detail screen and select Delete. This action cannot be undone.',
            ),
            _buildFAQItem(
              question: 'How do I change the app theme?',
              answer:
                  'Go to Settings from your Profile and select your preferred theme: Light, Dark, or Auto (follows system settings).',
            ),
            _buildFAQItem(
              question: 'Is my data secure?',
              answer:
                  'Yes, all your data is encrypted and stored securely. We take privacy seriously and never share your content with third parties.',
            ),
            _buildFAQItem(
              question: 'How do I invite others to a Space?',
              answer:
                  'Open a Space, tap the Share icon, and send the invite link to collaborators. They can join and contribute content to the shared space.',
            ),

            const SizedBox(height: AppConstants.spacingXL),

            // Still need help section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
              padding: const EdgeInsets.all(AppConstants.spacingL),
              decoration: BoxDecoration(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(AppConstants.radiusL),
                border: Border.all(color: AppConstants.borderColor),
              ),
              child: Column(
                children: [
                  const Text(
                    'Still need help?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingS),
                  Text(
                    'Reach out to us at $supportEmail',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
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

  Widget _buildFAQItem({
    required String question,
    required String answer,
  }) {
    return Container(
      margin: const EdgeInsets.only(
        left: AppConstants.spacingL,
        right: AppConstants.spacingL,
        bottom: AppConstants.spacingM,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingL,
          vertical: AppConstants.spacingS,
        ),
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppConstants.textPrimary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingL,
              0,
              AppConstants.spacingL,
              AppConstants.spacingL,
            ),
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppConstants.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=ReKall Support Request',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      }
    } catch (e) {
      // If can't launch email, copy to clipboard
      await Clipboard.setData(const ClipboardData(text: supportEmail));
    }
  }
}
