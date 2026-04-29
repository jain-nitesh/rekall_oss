import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'content_provider.dart';
import 'spaces_provider.dart';

/// Keys for SharedPreferences
const _kDismissed = 'onboarding_checklist_dismissed';
const _kHasUsedSearch = 'onboarding_has_used_search';

/// Onboarding task definition
class OnboardingTask {
  final String key;
  final String title;
  final String subtitle;
  final bool isComplete;

  const OnboardingTask({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.isComplete,
  });
}

/// Persisted state (only stores things that need SharedPreferences)
class OnboardingPersistedState {
  final bool hasUsedSearch;
  final bool dismissed;
  final bool isLoaded;

  const OnboardingPersistedState({
    this.hasUsedSearch = false,
    this.dismissed = false,
    this.isLoaded = false,
  });

  OnboardingPersistedState copyWith({
    bool? hasUsedSearch,
    bool? dismissed,
    bool? isLoaded,
  }) {
    return OnboardingPersistedState(
      hasUsedSearch: hasUsedSearch ?? this.hasUsedSearch,
      dismissed: dismissed ?? this.dismissed,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// Notifier for persisted onboarding flags
class OnboardingProgressNotifier
    extends StateNotifier<OnboardingPersistedState> {
  OnboardingProgressNotifier() : super(const OnboardingPersistedState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      hasUsedSearch: prefs.getBool(_kHasUsedSearch) ?? false,
      dismissed: prefs.getBool(_kDismissed) ?? false,
      isLoaded: true,
    );
  }

  Future<void> markSearchUsed() async {
    if (state.hasUsedSearch) return;
    state = state.copyWith(hasUsedSearch: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasUsedSearch, true);
  }

  Future<void> dismiss() async {
    state = state.copyWith(dismissed: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDismissed, true);
  }
}

final onboardingProgressProvider = StateNotifierProvider<
    OnboardingProgressNotifier, OnboardingPersistedState>(
  (ref) => OnboardingProgressNotifier(),
);

/// Fully derived onboarding state — combines persisted flags with live provider data.
/// This is a pure computation with no side effects.
class OnboardingProgressState {
  final bool hasSharedContent;
  final bool hasUsedSearch;
  final bool hasSpace;
  final bool dismissed;
  final bool isLoaded;

  const OnboardingProgressState({
    this.hasSharedContent = false,
    this.hasUsedSearch = false,
    this.hasSpace = false,
    this.dismissed = false,
    this.isLoaded = false,
  });

  bool get isComplete =>
      dismissed ||
      (hasSharedContent && hasUsedSearch && hasSpace);

  int get completedCount =>
      (hasSharedContent ? 1 : 0) +
      (hasUsedSearch ? 1 : 0) +
      (hasSpace ? 1 : 0);

  int get totalCount => 3;

  List<OnboardingTask> get tasks => [
        OnboardingTask(
          key: 'share',
          title: 'Share your first link',
          subtitle: 'Use the share button in any app',
          isComplete: hasSharedContent,
        ),
        OnboardingTask(
          key: 'search',
          title: 'Try AI Search',
          subtitle: 'Search by meaning, not just keywords',
          isComplete: hasUsedSearch,
        ),
        OnboardingTask(
          key: 'space',
          title: 'Create or join a Space',
          subtitle: 'Organize content into collections',
          isComplete: hasSpace,
        ),
      ];
}

/// Derived provider that combines persisted state + live content/spaces data.
/// Pure read-only — no mutations.
final onboardingStateProvider = Provider<OnboardingProgressState>((ref) {
  final persisted = ref.watch(onboardingProgressProvider);
  final contentState = ref.watch(contentProvider);
  final spacesState = ref.watch(spacesProvider);

  return OnboardingProgressState(
    hasSharedContent: contentState.items.isNotEmpty,
    hasUsedSearch: persisted.hasUsedSearch,
    hasSpace: spacesState.spaces.isNotEmpty,
    dismissed: persisted.dismissed,
    isLoaded: persisted.isLoaded,
  );
});

/// Whether the checklist should be visible
final onboardingVisibleProvider = Provider<bool>((ref) {
  final state = ref.watch(onboardingStateProvider);
  return state.isLoaded && !state.isComplete;
});
