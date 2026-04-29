import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/spaces_provider.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';
import 'custom_button.dart';

/// Bottom sheet for sharing content to one or more spaces
class ShareToSpaceSheet extends ConsumerStatefulWidget {
  final String contentId;
  final String contentTitle;

  const ShareToSpaceSheet({
    super.key,
    required this.contentId,
    required this.contentTitle,
  });

  @override
  ConsumerState<ShareToSpaceSheet> createState() => _ShareToSpaceSheetState();
}

class _ShareToSpaceSheetState extends ConsumerState<ShareToSpaceSheet> {
  final Set<String> _selectedSpaceIds = {};
  bool _isSharing = false;
  bool _showCreateForm = false;
  bool _isCreating = false;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    final notifier = ref.read(spacesProvider.notifier);
    final space = await notifier.createSpace(
      name: name,
      description: _descriptionController.text.trim(),
    );

    if (space != null) {
      final success = await notifier.addContentToSpace(
        space.id,
        widget.contentId,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Created "${space.name}" and added content'
                : 'Created "${space.name}" but failed to add content',
          ),
          backgroundColor: success
              ? AppConstants.successColor
              : Colors.orange,
        ),
      );
    } else {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create space'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  Future<void> _handleShare() async {
    if (_selectedSpaceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one space'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isSharing = true;
    });

    final notifier = ref.read(spacesProvider.notifier);
    int successCount = 0;
    int failureCount = 0;

    for (final spaceId in _selectedSpaceIds) {
      final success = await notifier.addContentToSpace(
        spaceId,
        widget.contentId,
      );

      if (success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    setState(() {
      _isSharing = false;
    });

    if (!mounted) return;

    if (failureCount == 0) {
      // All successful
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successCount == 1
                ? 'Shared to 1 space'
                : 'Shared to $successCount spaces',
          ),
          backgroundColor: AppConstants.successColor,
        ),
      );
    } else if (successCount > 0) {
      // Partial success
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shared to $successCount spaces. $failureCount failed.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      // All failed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to share content'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final spacesState = ref.watch(spacesProvider);
    final eligibleSpaces = spacesState.spaces
        .where((space) => space.canAddContent)
        .toList();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppConstants.surfaceDark : AppConstants.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXL),
        ),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.05)
              : AppConstants.borderColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppConstants.spacingM),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? AppConstants.slateGray.withValues(alpha: 0.3)
                    : AppConstants.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spacingS),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
                            : AppConstants.synapseIndigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        color: isDarkMode
                            ? AppConstants.synapseIndigoLight
                            : AppConstants.synapseIndigo,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add to Space',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isDarkMode
                                  ? AppConstants.starlight
                                  : AppConstants.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.contentTitle,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDarkMode
                                  ? AppConstants.slateGray
                                  : AppConstants.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDarkMode
                            ? AppConstants.slateGray
                            : AppConstants.textSecondary,
                      ),
                      onPressed: () {
                        AppHaptics.light();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            thickness: 1,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.borderColor.withValues(alpha: 0.3),
          ),

          // Body
          if (spacesState.isLoading)
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingXXL),
              child: Center(
                child: CircularProgressIndicator(
                  color: isDarkMode
                      ? AppConstants.primaryBlueCyan
                      : AppConstants.synapseIndigo,
                ),
              ),
            )
          else if (eligibleSpaces.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingXXL),
              child: _showCreateForm
                  ? _buildInlineCreateForm(isDarkMode)
                  : Column(
                      children: [
                        Icon(
                          Icons.folder_off_outlined,
                          size: 64,
                          color: isDarkMode
                              ? AppConstants.slateGray.withValues(alpha: 0.5)
                              : AppConstants.textTertiary,
                        ),
                        const SizedBox(height: AppConstants.spacingL),
                        Text(
                          'No spaces yet',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? AppConstants.starlight
                                : AppConstants.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingS),
                        Text(
                          'Create a space to organize and share your content.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDarkMode
                                ? AppConstants.slateGray
                                : AppConstants.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingL),
                        CustomButton(
                          label: 'Create a Space',
                          onPressed: () {
                            AppHaptics.light();
                            setState(() => _showCreateForm = true);
                          },
                          icon: Icons.add,
                          backgroundColor: isDarkMode
                              ? AppConstants.primaryBlueCyan
                              : AppConstants.synapseIndigo,
                        ),
                      ],
                    ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spacingS,
                  horizontal: AppConstants.spacingM,
                ),
                itemCount: eligibleSpaces.length,
                itemBuilder: (context, index) {
                  final space = eligibleSpaces[index];
                  final isSelected = _selectedSpaceIds.contains(space.id);
                  final alreadyInSpace = space.contentItems
                      .any((item) => item.id == widget.contentId);

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: AppConstants.spacingXS,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? (isSelected
                              ? AppConstants.synapseIndigo.withValues(alpha: 0.1)
                              : Colors.transparent)
                          : (isSelected
                              ? AppConstants.synapseIndigo.withValues(alpha: 0.05)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      border: Border.all(
                        color: isDarkMode
                            ? (isSelected
                                ? AppConstants.synapseIndigo.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.05))
                            : (isSelected
                                ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
                                : AppConstants.borderColor.withValues(alpha: 0.3)),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: alreadyInSpace
                          ? null
                          : () {
                              AppHaptics.light();
                              setState(() {
                                if (isSelected) {
                                  _selectedSpaceIds.remove(space.id);
                                } else {
                                  _selectedSpaceIds.add(space.id);
                                }
                              });
                            },
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      child: Padding(
                        padding: const EdgeInsets.all(AppConstants.spacingM),
                        child: Row(
                          children: [
                            // Space icon
                            Container(
                              padding: const EdgeInsets.all(AppConstants.spacingS + 2),
                              decoration: BoxDecoration(
                                color: alreadyInSpace
                                    ? (isDarkMode
                                        ? AppConstants.slateGray.withValues(alpha: 0.2)
                                        : AppConstants.borderColor)
                                    : (isDarkMode
                                        ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
                                        : AppConstants.synapseIndigo.withValues(alpha: 0.1)),
                                borderRadius: BorderRadius.circular(AppConstants.radiusS),
                              ),
                              child: Icon(
                                Icons.folder,
                                color: alreadyInSpace
                                    ? (isDarkMode
                                        ? AppConstants.slateGray
                                        : AppConstants.textTertiary)
                                    : (isDarkMode
                                        ? AppConstants.synapseIndigoLight
                                        : AppConstants.synapseIndigo),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingM),

                            // Space info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    space.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: alreadyInSpace
                                          ? (isDarkMode
                                              ? AppConstants.slateGray
                                              : AppConstants.textTertiary)
                                          : (isDarkMode
                                              ? AppConstants.starlight
                                              : AppConstants.textPrimary),
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    alreadyInSpace
                                        ? 'Already in this space'
                                        : '${space.memberCount} members • ${space.contentCount} items',
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

                            // Checkbox
                            if (!alreadyInSpace)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDarkMode
                                          ? AppConstants.primaryBlueCyan
                                          : AppConstants.synapseIndigo)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isDarkMode
                                            ? AppConstants.primaryBlueCyan
                                            : AppConstants.synapseIndigo)
                                        : (isDarkMode
                                            ? AppConstants.slateGray
                                            : AppConstants.borderColor),
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: AppConstants.white,
                                      )
                                    : null,
                              )
                            else
                              Icon(
                                Icons.check_circle,
                                color: isDarkMode
                                    ? AppConstants.slateGray
                                    : AppConstants.textTertiary,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // "+ Create Space" link when spaces exist
          if (!spacesState.isLoading && eligibleSpaces.isNotEmpty && !_showCreateForm)
            InkWell(
              onTap: () {
                AppHaptics.light();
                setState(() => _showCreateForm = true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingL,
                  vertical: AppConstants.spacingS,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: isDarkMode
                          ? AppConstants.primaryBlueCyan
                          : AppConstants.synapseIndigo,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Text(
                      'Create a new space',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode
                            ? AppConstants.primaryBlueCyan
                            : AppConstants.synapseIndigo,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Inline create form (shown above footer when toggled from space list)
          if (!spacesState.isLoading && eligibleSpaces.isNotEmpty && _showCreateForm)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingL,
                vertical: AppConstants.spacingS,
              ),
              child: _buildInlineCreateForm(isDarkMode),
            ),

          // Footer
          if (!spacesState.isLoading && eligibleSpaces.isNotEmpty && !_showCreateForm)
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingL),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.02)
                    : AppConstants.softWhite,
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppConstants.borderColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedSpaceIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppConstants.spacingM,
                      ),
                      child: Text(
                        '${_selectedSpaceIds.length} space${_selectedSpaceIds.length == 1 ? '' : 's'} selected',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  CustomButton(
                    label: 'Add to Spaces',
                    onPressed: _isSharing ? null : _handleShare,
                    isLoading: _isSharing,
                    icon: Icons.add,
                    backgroundColor: isDarkMode
                        ? AppConstants.primaryBlueCyan
                        : AppConstants.synapseIndigo,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  Widget _buildInlineCreateForm(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 20,
              color: isDarkMode
                  ? AppConstants.primaryBlueCyan
                  : AppConstants.synapseIndigo,
            ),
            const SizedBox(width: AppConstants.spacingS),
            Text(
              'Create a new space',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode
                    ? AppConstants.starlight
                    : AppConstants.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingM),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: isDarkMode
                ? AppConstants.starlight
                : AppConstants.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Space name',
            hintStyle: GoogleFonts.inter(
              color: isDarkMode
                  ? AppConstants.slateGray
                  : AppConstants.textTertiary,
            ),
            filled: true,
            fillColor: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.softWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppConstants.borderColor,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppConstants.borderColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? AppConstants.primaryBlueCyan
                    : AppConstants.synapseIndigo,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: AppConstants.spacingS,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingS),
        TextField(
          controller: _descriptionController,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: isDarkMode
                ? AppConstants.starlight
                : AppConstants.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Description (optional)',
            hintStyle: GoogleFonts.inter(
              color: isDarkMode
                  ? AppConstants.slateGray
                  : AppConstants.textTertiary,
            ),
            filled: true,
            fillColor: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.softWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppConstants.borderColor,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppConstants.borderColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              borderSide: BorderSide(
                color: isDarkMode
                    ? AppConstants.primaryBlueCyan
                    : AppConstants.synapseIndigo,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: AppConstants.spacingS,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _isCreating
                    ? null
                    : () {
                        setState(() {
                          _showCreateForm = false;
                          _nameController.clear();
                          _descriptionController.clear();
                        });
                      },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: isDarkMode
                        ? AppConstants.slateGray
                        : AppConstants.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingS),
            Expanded(
              flex: 2,
              child: CustomButton(
                label: 'Create & Add',
                onPressed: _isCreating ? null : _handleCreateAndAdd,
                isLoading: _isCreating,
                icon: Icons.check,
                backgroundColor: isDarkMode
                    ? AppConstants.primaryBlueCyan
                    : AppConstants.synapseIndigo,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Helper function to show the share to space sheet
Future<bool?> showShareToSpaceSheet(
  BuildContext context, {
  required String contentId,
  required String contentTitle,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ShareToSpaceSheet(
      contentId: contentId,
      contentTitle: contentTitle,
    ),
  );
}
