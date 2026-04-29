import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/spaces_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';

class CreateSpaceScreen extends ConsumerStatefulWidget {
  const CreateSpaceScreen({super.key});

  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  bool _isCreating = false;
  bool _isNameFocused = false;
  bool _isDescriptionFocused = false;
  String? _selectedEmoji;
  String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_onNameFocusChange);
    _descriptionFocusNode.addListener(_onDescriptionFocusChange);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.removeListener(_onNameFocusChange);
    _descriptionFocusNode.removeListener(_onDescriptionFocusChange);
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  void _onNameFocusChange() {
    setState(() {
      _isNameFocused = _nameFocusNode.hasFocus;
    });
  }

  void _onDescriptionFocusChange() {
    setState(() {
      _isDescriptionFocused = _descriptionFocusNode.hasFocus;
    });
  }

  Future<void> _handleCreateSpace() async {
    if (!_formKey.currentState!.validate()) {
      AppHaptics.error();
      return;
    }

    AppHaptics.light();
    setState(() {
      _isCreating = true;
    });

    final space = await ref.read(spacesProvider.notifier).createSpace(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          emoji: _selectedEmoji,
          accentColor: _selectedColor,
        );

    setState(() {
      _isCreating = false;
    });

    if (!mounted) return;

    if (space != null) {
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Space "${space.name}" created successfully!'),
          backgroundColor: AppConstants.successColor,
        ),
      );
      context.pop();
    } else {
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create space'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        title: 'Create Space',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon with gradient border - reflects selected emoji/color
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _selectedColor != null
                          ? [_parseHexColor(_selectedColor!), _parseHexColor(_selectedColor!).withValues(alpha: 0.7)]
                          : AppConstants.primaryGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.white,
                    ),
                    child: _selectedEmoji != null
                        ? Center(child: Text(_selectedEmoji!, style: const TextStyle(fontSize: 56)))
                        : const Icon(
                            Icons.folder,
                            size: AppConstants.iconMassive,
                            color: AppConstants.primaryColor,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // Info text
              const Text(
                'Create a shared space to organize and collaborate on content with your team.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppConstants.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // Name field
              TextFormField(
                controller: _nameController,
                focusNode: _nameFocusNode,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(
                  color: AppConstants.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Space Name *',
                  hintStyle: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.title,
                    color: _isNameFocused
                        ? AppConstants.primaryColor
                        : AppConstants.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingM,
                    vertical: AppConstants.spacingM,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.primaryColor,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.errorColor,
                      width: 1.5,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.errorColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: AppConstants.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a space name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppConstants.spacingL),

              // Description field
              TextFormField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                style: const TextStyle(
                  color: AppConstants.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Description *',
                  hintStyle: const TextStyle(
                    color: AppConstants.textSecondary,
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.description,
                    color: _isDescriptionFocused
                        ? AppConstants.primaryColor
                        : AppConstants.textSecondary,
                  ),
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingM,
                    vertical: AppConstants.spacingM,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.primaryColor,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.errorColor,
                      width: 1.5,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    borderSide: const BorderSide(
                      color: AppConstants.errorColor,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: AppConstants.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppConstants.spacingL),

              // Emoji picker
              Text(
                'Choose an Icon',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  '📁', '📚', '🚀', '⭐', '💡', '🧠', '🎯', '🔬',
                  '💻', '🎨', '📝', '🏠', '🌍', '🎵', '📸', '🛠️',
                  '💰', '🏋️', '🍳', '✈️', '📊', '🔒', '❤️', '🎮',
                ].map((emoji) => GestureDetector(
                  onTap: () => setState(() {
                    _selectedEmoji = _selectedEmoji == emoji ? null : emoji;
                  }),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _selectedEmoji == emoji
                          ? AppConstants.primaryColor.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedEmoji == emoji
                            ? AppConstants.primaryColor
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                )).toList(),
              ),
              const SizedBox(height: AppConstants.spacingL),

              // Color picker
              Text(
                'Accent Color',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  '#6C5CE7', // Purple
                  '#0984E3', // Blue
                  '#00B894', // Green
                  '#E17055', // Coral
                  '#FDCB6E', // Yellow
                  '#E84393', // Pink
                  '#00CEC9', // Teal
                  '#2D3436', // Dark
                  '#D63031', // Red
                  '#6AB04C', // Leaf
                ].map((hex) => GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = _selectedColor == hex ? null : hex;
                  }),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _parseHexColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColor == hex
                            ? AppConstants.textPrimary
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: _selectedColor == hex
                          ? [BoxShadow(
                              color: _parseHexColor(hex).withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )]
                          : [],
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // Info card
              Container(
                padding: const EdgeInsets.all(AppConstants.spacingM),
                decoration: BoxDecoration(
                  color: AppConstants.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  border: Border.all(
                    color: AppConstants.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppConstants.accentColor,
                      size: 20,
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      child: Text(
                        'After creating the space, you can invite members using the invite link.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppConstants.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // Create button
              PremiumButton.primary(
                onPressed: _isCreating ? null : _handleCreateSpace,
                isLoading: _isCreating,
                fullWidth: true,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: AppConstants.spacingS),
                    Text(
                      'Create Space',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
