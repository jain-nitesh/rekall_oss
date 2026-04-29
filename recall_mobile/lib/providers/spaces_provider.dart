import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shared_space.dart';
import '../services/api_service.dart';
import '../services/analytics_service.dart';
import 'auth_provider.dart';

/// Spaces state
class SpacesState {
  final List<SharedSpace> spaces;
  final bool isLoading;
  final String? errorMessage;

  const SpacesState({
    required this.spaces,
    this.isLoading = false,
    this.errorMessage,
  });

  SpacesState copyWith({
    List<SharedSpace>? spaces,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SpacesState(
      spaces: spaces ?? this.spaces,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory SpacesState.initial() {
    return const SpacesState(spaces: [], isLoading: true);
  }

  factory SpacesState.loading() {
    return const SpacesState(spaces: [], isLoading: true);
  }

  factory SpacesState.loaded(List<SharedSpace> spaces) {
    return SpacesState(spaces: spaces, isLoading: false);
  }

  factory SpacesState.error(String message) {
    return SpacesState(
      spaces: const [],
      isLoading: false,
      errorMessage: message,
    );
  }
}

/// Spaces provider notifier
class SpacesNotifier extends StateNotifier<SpacesState> {
  final Ref ref;
  final ApiService _apiService = ApiService();

  SpacesNotifier(this.ref) : super(SpacesState.initial()) {
    loadSpaces();
  }

  /// Load all spaces for current user
  Future<void> loadSpaces() async {
    state = SpacesState.loading();

    try {
      final spaces = await _apiService.getAllSpaces();
      state = SpacesState.loaded(spaces);
    } catch (e) {
      state = SpacesState.error('Failed to load spaces: $e');
    }
  }

  /// Create a new space
  Future<SharedSpace?> createSpace({
    required String name,
    required String description,
    String? emoji,
    String? accentColor,
  }) async {
    try {
      final space = await _apiService.createSpace(
        name: name,
        description: description,
        emoji: emoji,
        accentColor: accentColor,
      );

      // Log analytics event
      AnalyticsService().logSpaceCreated(space.id, space.name);

      // Add to state
      final updatedSpaces = [...state.spaces, space];
      state = state.copyWith(spaces: updatedSpaces);

      return space;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to create space: $e');
      return null;
    }
  }

  /// Add content to space
  Future<bool> addContentToSpace(String spaceId, String contentId) async {
    try {
      await _apiService.addContentToSpace(spaceId, contentId);

      // Refresh the space to get updated content list (first page only)
      final updatedSpace = await _apiService.getSpaceById(spaceId, contentPage: 1);

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to add content: $e');
      return false;
    }
  }

  /// Remove content from space
  Future<bool> removeContentFromSpace(String spaceId, String contentId) async {
    try {
      await _apiService.removeContentFromSpace(spaceId, contentId);

      // Refresh the space to get updated content list (first page only)
      final updatedSpace = await _apiService.getSpaceById(spaceId, contentPage: 1);

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove content: $e');
      return false;
    }
  }

  /// Delete space
  Future<bool> deleteSpace(String spaceId) async {
    try {
      await _apiService.deleteSpace(spaceId);

      // Remove from state
      final updatedSpaces = state.spaces.where((s) => s.id != spaceId).toList();
      state = state.copyWith(spaces: updatedSpaces);

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete space: $e');
      return false;
    }
  }

  /// Get space by ID
  SharedSpace? getSpaceById(String id) {
    try {
      return state.spaces.firstWhere((space) => space.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Load space details (with pagination)
  Future<SharedSpace?> loadSpaceDetails(String spaceId, {int contentPage = 1, int contentPageSize = 20}) async {
    try {
      final space = await _apiService.getSpaceById(
        spaceId,
        contentPage: contentPage,
        contentPageSize: contentPageSize,
      );

      // Update or add space to state
      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = space;
        state = state.copyWith(spaces: updatedSpaces);
      } else {
        // Add new space to state
        final updatedSpaces = [...state.spaces, space];
        state = state.copyWith(spaces: updatedSpaces);
      }

      return space;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load space details: $e');
      return null;
    }
  }

  /// Load more content for a space (pagination)
  Future<bool> loadMoreSpaceContent(String spaceId) async {
    try {
      final currentSpace = getSpaceById(spaceId);
      if (currentSpace == null) return false;
      
      // Check if there's more content to load
      if (!currentSpace.contentHasMore) return false;

      // Load next page
      final nextPage = currentSpace.contentPage + 1;
      final nextPageSpace = await _apiService.getSpaceById(
        spaceId,
        contentPage: nextPage,
        contentPageSize: currentSpace.contentPageSize,
      );

      // Merge content items
      final mergedContentItems = [
        ...currentSpace.contentItems,
        ...nextPageSpace.contentItems,
      ];

      // Update space with merged content
      final updatedSpace = currentSpace.copyWith(
        contentItems: mergedContentItems,
        contentPage: nextPageSpace.contentPage,
        contentHasMore: nextPageSpace.contentHasMore,
        contentTotal: nextPageSpace.contentTotal,
      );

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load more content: $e');
      return false;
    }
  }

  /// Refresh space content (reload from page 1)
  Future<bool> refreshSpaceContent(String spaceId) async {
    try {
      final currentSpace = getSpaceById(spaceId);
      if (currentSpace == null) return false;

      // Reload first page
      final refreshedSpace = await _apiService.getSpaceById(
        spaceId,
        contentPage: 1,
        contentPageSize: currentSpace.contentPageSize,
      );

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = refreshedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to refresh content: $e');
      return false;
    }
  }

  /// Update space details
  Future<SharedSpace?> updateSpace(
    String spaceId, {
    String? name,
    String? description,
  }) async {
    try {
      final updatedSpace = await _apiService.updateSpace(
        spaceId,
        name: name,
        description: description,
      );

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return updatedSpace;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update space: $e');
      return null;
    }
  }

  /// Invite member to space
  Future<bool> inviteMember(
    String spaceId,
    String email, {
    String role = 'member',
  }) async {
    try {
      await _apiService.inviteMember(spaceId, email, role: role);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to invite member: $e');
      return false;
    }
  }

  /// Join space via invitation token
  Future<SharedSpace?> joinSpace(String token) async {
    try {
      final space = await _apiService.joinSpaceViaToken(token);

      // Add to state
      final updatedSpaces = [...state.spaces, space];
      state = state.copyWith(spaces: updatedSpaces);

      return space;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to join space: $e');
      return null;
    }
  }

  /// Remove member from space
  Future<bool> removeMember(String spaceId, String userId) async {
    try {
      await _apiService.removeMember(spaceId, userId);

      // Refresh the space to get updated member list
      final updatedSpace = await _apiService.getSpaceById(spaceId);

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove member: $e');
      return false;
    }
  }

  /// Update member role
  Future<bool> updateMemberRole(
    String spaceId,
    String userId,
    String role,
  ) async {
    try {
      await _apiService.updateMemberRole(spaceId, userId, role);

      // Refresh the space to get updated member list
      final updatedSpace = await _apiService.getSpaceById(spaceId);

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update member role: $e');
      return false;
    }
  }

  /// Regenerate invite link for space (invalidates old links)
  Future<bool> regenerateInviteLink(String spaceId) async {
    try {
      await _apiService.regenerateInviteLink(spaceId);

      // Refresh space to get new token
      final updatedSpace = await _apiService.getSpaceById(spaceId);

      final spaceIndex = state.spaces.indexWhere((s) => s.id == spaceId);
      if (spaceIndex != -1) {
        final updatedSpaces = [...state.spaces];
        updatedSpaces[spaceIndex] = updatedSpace;
        state = state.copyWith(spaces: updatedSpaces);
      }

      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to regenerate invite link: $e');
      return false;
    }
  }

  /// Refresh spaces
  Future<void> refresh() async {
    await loadSpaces();
  }
}

/// Spaces provider
final spacesProvider = StateNotifierProvider<SpacesNotifier, SpacesState>((ref) {
  return SpacesNotifier(ref);
});

/// All spaces provider (derived)
final allSpacesProvider = Provider<List<SharedSpace>>((ref) {
  return ref.watch(spacesProvider).spaces;
});

/// Space by ID provider
final spaceByIdProvider = Provider.family<SharedSpace?, String>((ref, id) {
  final allSpaces = ref.watch(allSpacesProvider);
  try {
    return allSpaces.firstWhere((space) => space.id == id);
  } catch (e) {
    return null;
  }
});

/// User's owned spaces provider
final ownedSpacesProvider = Provider<List<SharedSpace>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  final allSpaces = ref.watch(allSpacesProvider);
  return allSpaces.where((space) => space.isOwner(currentUser.id)).toList();
});

/// User's member spaces provider (not owner)
final memberSpacesProvider = Provider<List<SharedSpace>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null) return [];

  final allSpaces = ref.watch(allSpacesProvider);
  return allSpaces.where((space) =>
    space.isMember(currentUser.id) && !space.isOwner(currentUser.id)
  ).toList();
});

/// Spaces containing a specific content item
final spacesContainingContentProvider = Provider.family<List<SharedSpace>, String>((ref, contentId) {
  final allSpaces = ref.watch(allSpacesProvider);
  return allSpaces.where((space) {
    return space.contentItems.any((item) => item.id == contentId);
  }).toList();
});