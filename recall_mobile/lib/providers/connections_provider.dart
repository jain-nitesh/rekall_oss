import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_connection.dart';
import '../models/connection_cluster.dart';
import '../services/api_service.dart';

/// Connections for a specific content item
final connectionsByItemProvider = FutureProvider.family<List<ContentConnection>, String>((ref, contentId) async {
  try {
    final apiService = ApiService();
    final data = await apiService.getConnections(contentId);
    return data.map((json) => ContentConnection.fromJson(json as Map<String, dynamic>)).toList();
  } catch (e) {
    debugPrint('[Connections] Failed to load connections for $contentId: $e');
    return [];
  }
});

/// All connections state
class AllConnectionsState {
  final List<ContentConnection> connections;
  final bool isLoading;
  final bool hasMore;
  final int page;

  const AllConnectionsState({
    this.connections = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
  });

  AllConnectionsState copyWith({
    List<ContentConnection>? connections,
    bool? isLoading,
    bool? hasMore,
    int? page,
  }) {
    return AllConnectionsState(
      connections: connections ?? this.connections,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
    );
  }
}

class AllConnectionsNotifier extends StateNotifier<AllConnectionsState> {
  AllConnectionsNotifier() : super(const AllConnectionsState());

  final _apiService = ApiService();

  Future<void> loadConnections({bool refresh = false}) async {
    if (state.isLoading) return;

    final page = refresh ? 1 : state.page;
    state = state.copyWith(isLoading: true);

    try {
      final data = await _apiService.getAllConnections(page: page);
      final connections = (data['connections'] as List)
          .map((json) => ContentConnection.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        connections: refresh ? connections : [...state.connections, ...connections],
        isLoading: false,
        hasMore: data['has_more'] as bool,
        page: page + 1,
      );
    } catch (e) {
      debugPrint('[Connections] Failed to load: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> dismissConnection(String connectionId) async {
    try {
      await _apiService.dismissConnection(connectionId);
      state = state.copyWith(
        connections: state.connections.where((c) => c.id != connectionId).toList(),
      );
    } catch (e) {
      debugPrint('[Connections] Failed to dismiss: $e');
    }
  }
}

final allConnectionsProvider =
    StateNotifierProvider<AllConnectionsNotifier, AllConnectionsState>((ref) {
  return AllConnectionsNotifier();
});

/// Daily connection provider
final dailyConnectionProvider = FutureProvider<ContentConnection?>((ref) async {
  try {
    final apiService = ApiService();
    final data = await apiService.getDailyConnection();
    if (data == null) return null;
    return ContentConnection.fromJson(data);
  } catch (e) {
    debugPrint('[Connections] Failed to load daily connection: $e');
    return null;
  }
});

/// Clusters state
class ClustersState {
  final List<ConnectionCluster> clusters;
  final bool isLoading;
  final String? searchQuery;
  final String? categoryFilter;

  const ClustersState({
    this.clusters = const [],
    this.isLoading = false,
    this.searchQuery,
    this.categoryFilter,
  });

  ClustersState copyWith({
    List<ConnectionCluster>? clusters,
    bool? isLoading,
    String? searchQuery,
    String? categoryFilter,
  }) {
    return ClustersState(
      clusters: clusters ?? this.clusters,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter: categoryFilter ?? this.categoryFilter,
    );
  }
}

class ClustersNotifier extends StateNotifier<ClustersState> {
  ClustersNotifier() : super(const ClustersState());

  final _apiService = ApiService();

  Future<void> loadClusters({bool refresh = false}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);

    try {
      final data = await _apiService.getClusters(
        search: state.searchQuery,
        category: state.categoryFilter,
      );
      final clusters = (data['clusters'] as List)
          .map((json) => ConnectionCluster.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        clusters: clusters,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[Clusters] Failed to load: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> search(String query) async {
    state = state.copyWith(searchQuery: query.isEmpty ? null : query);
    await loadClusters(refresh: true);
  }

  Future<void> filterByCategory(String? category) async {
    state = state.copyWith(categoryFilter: category);
    await loadClusters(refresh: true);
  }

  Future<void> dismissCluster(String clusterId) async {
    try {
      await _apiService.dismissCluster(clusterId);
      state = state.copyWith(
        clusters: state.clusters.where((c) => c.id != clusterId).toList(),
      );
    } catch (e) {
      debugPrint('[Clusters] Failed to dismiss: $e');
    }
  }
}

final clustersProvider =
    StateNotifierProvider<ClustersNotifier, ClustersState>((ref) {
  return ClustersNotifier();
});

/// Cluster detail provider
final clusterDetailProvider = FutureProvider.family<ConnectionClusterDetail?, String>((ref, clusterId) async {
  try {
    final apiService = ApiService();
    final data = await apiService.getClusterDetail(clusterId);
    return ConnectionClusterDetail.fromJson(data);
  } catch (e) {
    debugPrint('[Clusters] Failed to load detail for $clusterId: $e');
    return null;
  }
});
