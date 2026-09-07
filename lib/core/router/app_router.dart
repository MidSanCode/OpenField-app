import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/account_page.dart';
import 'package:openfield/pages/account/app_announcement_page.dart';
import 'package:openfield/pages/chat/chat_page.dart';
import 'package:openfield/pages/posts/camps_page.dart';
import 'package:openfield/pages/posts/posts_page.dart';
import 'package:openfield/widgets/app_shell.dart';

/// Builds the app's [GoRouter]: a bottom-shell [StatefulShellRoute] with the
/// four tab branches (`/posts`, `/camps`, `/chat`, `/account`) plus the
/// standalone `/announcements` page. Starts on `/posts`; no auth redirects
/// here.
GoRouter createRouter(AuthService authService, GlobalKey<NavigatorState> navigatorKey) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/posts',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/posts', name: 'posts', builder: (context, state) => const PostsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/camps', name: 'camps', builder: (context, state) => const CampsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/chat', name: 'chat', builder: (context, state) => const ChatPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/account', name: 'account', builder: (context, state) => const AccountPage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/announcements',
        name: 'announcements',
        builder: (context, state) => const AppAnnouncementPage(),
      ),
    ],
  );
}
