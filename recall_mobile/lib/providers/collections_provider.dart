import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_collection.dart';
import '../services/api_service.dart';

final myCollectionsProvider = FutureProvider<List<PublicCollection>>((ref) async {
  final apiService = ApiService();
  final result = await apiService.getMyCollections();
  return result.map((e) => PublicCollection.fromJson(e as Map<String, dynamic>)).toList();
});

final exploreCollectionsProvider = FutureProvider.family<List<PublicCollection>, int>((ref, page) async {
  final apiService = ApiService();
  final result = await apiService.exploreCollections(page: page);
  return result.map((e) => PublicCollection.fromJson(e as Map<String, dynamic>)).toList();
});

final collectionDetailProvider = FutureProvider.family<PublicCollection, String>((ref, slug) async {
  final apiService = ApiService();
  final result = await apiService.getCollection(slug);
  return PublicCollection.fromJson(result);
});

class MyCollectionsNotifier extends StateNotifier<AsyncValue<List<PublicCollection>>> {
  final Ref ref;

  MyCollectionsNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadCollections();
  }

  Future<void> loadCollections() async {
    state = const AsyncValue.loading();
    try {
      final apiService = ApiService();
      final result = await apiService.getMyCollections();
      final collections = result
          .map((e) => PublicCollection.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(collections);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<PublicCollection?> createCollection(String title, {String? description}) async {
    try {
      final apiService = ApiService();
      final result = await apiService.createCollection(title: title, description: description);
      final collection = PublicCollection.fromJson(result);
      await loadCollections();
      return collection;
    } catch (e) {
      return null;
    }
  }

  Future<bool> addItem(String collectionId, String contentItemId, {String? curatorNote}) async {
    try {
      final apiService = ApiService();
      await apiService.addItemToCollection(collectionId, contentItemId, curatorNote: curatorNote);
      await loadCollections();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeItem(String collectionId, String itemId) async {
    try {
      final apiService = ApiService();
      await apiService.removeItemFromCollection(collectionId, itemId);
      await loadCollections();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> forkCollection(String collectionId) async {
    try {
      final apiService = ApiService();
      final result = await apiService.forkCollection(collectionId);
      return result;
    } catch (e) {
      return null;
    }
  }
}

final myCollectionsNotifierProvider =
    StateNotifierProvider<MyCollectionsNotifier, AsyncValue<List<PublicCollection>>>((ref) {
  return MyCollectionsNotifier(ref);
});
