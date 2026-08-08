import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/account_page.dart';
import 'package:openfield/pages/chat/chat_page.dart';
import 'package:openfield/widgets/app_shell.dart';

GoRouter createRouter(AuthService authService, GlobalKey<NavigatorState> navigatorKey) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/chat',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
        ),
        branches: [
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
        path: '/posts',
        redirect: (context, state) => '/chat',
      ),
    ],
  );
}
