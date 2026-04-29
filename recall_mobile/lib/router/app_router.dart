import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/main_screen.dart';
import '../screens/content/content_detail_screen.dart';
import '../screens/search/enhanced_search_screen.dart';
import '../screens/spaces/spaces_list_screen.dart';
import '../screens/spaces/space_detail_screen.dart';
import '../screens/spaces/space_info_screen.dart';
import '../screens/spaces/create_space_screen.dart';
import '../screens/spaces/invite_handler_screen.dart';
import '../screens/share_handler_screen.dart';
import '../screens/profile/notification_settings_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/help_screen.dart';
import '../models/content_connection.dart';
import '../screens/connections/connections_screen.dart';
import '../screens/connections/cluster_detail_screen.dart';
import '../screens/profile/import_bookmarks_screen.dart';
import '../screens/collections/my_collections_screen.dart';
import '../screens/collections/collection_detail_screen.dart';
import '../screens/collections/explore_collections_screen.dart';
import '../screens/collections/create_collection_screen.dart';
import '../screens/brain/wiki_page_screen.dart';
import '../screens/brain/entity_detail_screen.dart';
import '../screens/brain/chat_screen.dart';
import '../screens/profile/personal_info_screen.dart';
import '../providers/server_config_provider.dart';
import '../screens/onboarding/server_selection_screen.dart';
import '../screens/auth/email_auth_screen.dart';
import '../screens/auth/auth_screen.dart';
import '../services/api_service.dart';

// Notifies GoRouter when auth or server config changes so it re-evaluates
// redirects without recreating the GoRouter (which would reset navigation).
class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(Ref ref) : _ref = ref {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
    ref.listen<AsyncValue<ServerConfig?>>(serverConfigProvider, (_, __) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authProvider);
    final serverConfigAsync = _ref.read(serverConfigProvider);

    final isAuthenticated = authState.status == AuthStatus.authenticated;
    final loc = state.matchedLocation;
    final isSplash = loc == '/splash';
    final isInviteRoute = loc.startsWith('/invite/');
    final isAuthScreen = loc == '/onboarding' ||
        loc == '/server-select' ||
        loc == '/auth' ||
        loc == '/auth/email';

    if (isSplash) return null;
    if (isInviteRoute) return null;

    if (serverConfigAsync.isLoading) return '/splash';

    if (isAuthenticated && isAuthScreen) return '/';

    if (!isAuthenticated) {
      if (isAuthScreen) return null;
      final hasServerConfig = serverConfigAsync.hasValue && serverConfigAsync.value != null;
      return hasServerConfig ? '/auth' : '/onboarding';
    }

    return null;
  }
}

/// App router configuration
final appRouterProvider = Provider<GoRouter>((ref) {
  // Sync ApiService base URL whenever server config loads/changes
  ref.listen<AsyncValue<ServerConfig?>>(serverConfigProvider, (_, next) {
    next.whenData((config) {
      if (config != null) ApiService().updateBaseUrl(config.url);
    });
  });
  ref.read(serverConfigProvider).whenData((config) {
    if (config != null) ApiService().updateBaseUrl(config.url);
  });

  final notifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    observers: [
      AnalyticsService().observer,
    ],
    onException: (BuildContext context, GoRouterState state, GoRouter router) {
      // Handle custom scheme deep links (rekall://invite/TOKEN) on cold start.
      // The platform passes the full URI to GoRouter which can't match it as a route.
      final uri = state.uri;
      if (uri.scheme == 'rekall' && uri.host == 'invite' && uri.pathSegments.isNotEmpty) {
        router.go('/invite/${uri.pathSegments[0]}');
        return;
      }
      // For any other unmatched routes, go home
      router.go('/');
    },
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // Splash
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Onboarding (with Google Sign-In on last page)
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/server-select',
        builder: (context, state) => const ServerSelectionScreen(),
      ),
      GoRoute(
        path: '/auth/email',
        builder: (context, state) => const EmailAuthScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),

      // Main app (with bottom navigation)
      GoRoute(
        path: '/',
        name: 'main',
        builder: (context, state) => const MainScreen(),
      ),

      // Content detail
      GoRoute(
        path: '/content/:id',
        name: 'content-detail',
        builder: (context, state) {
          final contentId = state.pathParameters['id']!;
          return ContentDetailScreen(contentId: contentId);
        },
      ),

      // Connections
      GoRoute(
        path: '/connections',
        name: 'connections',
        builder: (context, state) => const ConnectionsScreen(),
      ),

      // Connection detail (daily discovery)
      GoRoute(
        path: '/connections/:id',
        name: 'connection-detail',
        builder: (context, state) {
          final connection = state.extra as ContentConnection;
          return ConnectionDetailScreen(connection: connection);
        },
      ),

      // Cluster detail
      GoRoute(
        path: '/clusters/:clusterId',
        name: 'cluster-detail',
        builder: (context, state) {
          final clusterId = state.pathParameters['clusterId']!;
          return ClusterDetailScreen(clusterId: clusterId);
        },
      ),

      // Import bookmarks
      GoRoute(
        path: '/import',
        name: 'import',
        builder: (context, state) => const ImportBookmarksScreen(),
      ),

      // Collections
      GoRoute(
        path: '/collections',
        name: 'my-collections',
        builder: (context, state) => const MyCollectionsScreen(),
      ),
      GoRoute(
        path: '/collections/create',
        name: 'create-collection',
        builder: (context, state) => const CreateCollectionScreen(),
      ),
      GoRoute(
        path: '/collections/explore',
        name: 'explore-collections',
        builder: (context, state) => const ExploreCollectionsScreen(),
      ),
      GoRoute(
        path: '/collections/:slug',
        name: 'collection-detail',
        builder: (context, state) {
          final slug = state.pathParameters['slug']!;
          return CollectionDetailScreen(slug: slug);
        },
      ),

      // Enhanced Search
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const EnhancedSearchScreen(),
      ),

      // Notification Settings
      GoRoute(
        path: '/notification-settings',
        name: 'notification-settings',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // Personal Info (self-entity)
      GoRoute(
        path: '/personal-info',
        name: 'personalInfo',
        builder: (context, state) => const PersonalInfoScreen(),
      ),

      // Help & Support
      GoRoute(
        path: '/help',
        name: 'help',
        builder: (context, state) => const HelpScreen(),
      ),

      // Spaces
      GoRoute(
        path: '/spaces',
        name: 'spaces',
        builder: (context, state) => const SpacesListScreen(),
      ),
      // Specific routes must come BEFORE parameterized routes
      GoRoute(
        path: '/spaces/create',
        name: 'create-space',
        builder: (context, state) => const CreateSpaceScreen(),
      ),
      GoRoute(
        path: '/spaces/:id',
        name: 'space-detail',
        builder: (context, state) {
          final spaceId = state.pathParameters['id']!;
          return SpaceDetailScreen(spaceId: spaceId);
        },
      ),
      GoRoute(
        path: '/spaces/:id/info',
        name: 'space-info',
        builder: (context, state) {
          final spaceId = state.pathParameters['id']!;
          return SpaceInfoScreen(spaceId: spaceId);
        },
      ),

      // Brain: Wiki page detail
      GoRoute(
        path: '/wiki/:slug',
        name: 'wiki-page',
        builder: (context, state) {
          final slug = state.pathParameters['slug']!;
          return WikiPageScreen(slug: slug);
        },
      ),

      // Brain: Entity detail
      GoRoute(
        path: '/entities/:id',
        name: 'entity-detail',
        builder: (context, state) {
          final entityId = state.pathParameters['id']!;
          return EntityDetailScreen(entityId: entityId);
        },
      ),

      // Brain: Chat
      GoRoute(
        path: '/chat',
        name: 'chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/chat/:id',
        name: 'chat-detail',
        builder: (context, state) {
          final conversationId = state.pathParameters['id']!;
          return ChatScreen(conversationId: conversationId);
        },
      ),

      // Invite handler (for deep links)
      GoRoute(
        path: '/invite/:token',
        name: 'invite-handler',
        builder: (context, state) {
          final token = state.pathParameters['token']!;
          return InviteHandlerScreen(token: token);
        },
      ),

      // Share handler (for external shares)
      GoRoute(
        path: '/share',
        name: 'share',
        builder: (context, state) => const ShareHandlerScreen(),
      ),
    ],
  );
});
