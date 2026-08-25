import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/chat_unread_service.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:easy_localization/easy_localization.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      body: Row(
        children: [
          if (isWideScreen)
            _Sidebar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: isWideScreen ? null : _BottomBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
      ),
    );
  }

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedIndex, required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'appTitle'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.forum_outlined),
          selectedIcon: const Icon(Icons.forum),
          label: Text('posts'.tr()),
        ),
        NavigationRailDestination(
          icon: const _ChatTabIcon(),
          selectedIcon: const _ChatTabIcon(selected: true),
          label: Text('chat'.tr()),
        ),
        NavigationRailDestination(
          icon: _AccountAvatarIcon(size: 24),
          selectedIcon: _AccountAvatarIcon(size: 24, selected: true),
          label: Text('account'.tr()),
        ),
      ],
    );
  }
}

class _AccountAvatarIcon extends StatelessWidget {
  final double size;
  final bool selected;

  const _AccountAvatarIcon({required this.size, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final avatarUrl = authService.avatarUrl != null && authService.avatarUrl!.isNotEmpty
        ? authService.avatarUrl!
        : (authService.user?.avatarUrl.isNotEmpty == true
            ? authService.user!.avatarUrl
            : null);
    if (avatarUrl == null) {
      return Icon(
        selected ? Icons.person : Icons.person_outline,
        size: size,
      );
    }
    return Avatar(
      radius: size / 2,
      imageUrl: avatarUrl,
    );
  }
}

/// Chat tab icon with a small red dot / count badge whenever the chat list
/// reports unread messages. Used by both the bottom NavigationBar and the
/// NavigationRail destination.
class _ChatTabIcon extends StatelessWidget {
  final bool selected;
  const _ChatTabIcon({this.selected = false});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<ChatUnreadService, int>((s) => s.totalUnread);
    final icon = Icon(selected ? Icons.chat : Icons.chat_outlined);
    if (unread <= 0) return icon;
    final theme = Theme.of(context);
    final label = unread > 99 ? '99+' : '$unread';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.error,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.surface, width: 1.5),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onError,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selectedIndex, required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.forum_outlined),
          selectedIcon: const Icon(Icons.forum),
          label: 'posts'.tr(),
        ),
        NavigationDestination(
          icon: const _ChatTabIcon(),
          selectedIcon: const _ChatTabIcon(selected: true),
          label: 'chat'.tr(),
        ),
        NavigationDestination(
          icon: const _AccountAvatarIcon(size: 24),
          selectedIcon: const _AccountAvatarIcon(size: 24, selected: true),
          label: 'account'.tr(),
        ),
      ],
    );
  }
}
