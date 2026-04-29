import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/personal_info.dart';
import '../services/api_service.dart';

/// State for personal info (self-entity)
class PersonalInfoState {
  final PersonalInfo? info;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;

  PersonalInfoState({
    this.info,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
  });

  PersonalInfoState copyWith({
    PersonalInfo? info,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? successMessage,
  }) {
    return PersonalInfoState(
      info: info ?? this.info,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

/// Notifier for personal info
class PersonalInfoNotifier extends StateNotifier<PersonalInfoState> {
  final ApiService _apiService = ApiService();

  PersonalInfoNotifier() : super(PersonalInfoState());

  Future<void> loadPersonalInfo() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getPersonalInfo();
      final info = PersonalInfo.fromJson(response);

      state = PersonalInfoState(
        info: info,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> savePersonalInfo({
    String? bio,
    Map<String, String>? socialLinks,
  }) async {
    if (state.isSaving) return;

    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);

    try {
      final response = await _apiService.seedPersonalInfo(
        bio: bio,
        socialLinks: socialLinks,
      );
      final info = PersonalInfo.fromJson(response);

      state = PersonalInfoState(
        info: info,
        isSaving: false,
        successMessage: 'Personal info saved! Fetching your profile data...',
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await loadPersonalInfo();
  }
}

/// Provider for personal info (self-entity)
final personalInfoProvider =
    StateNotifierProvider<PersonalInfoNotifier, PersonalInfoState>(
  (ref) => PersonalInfoNotifier(),
);
