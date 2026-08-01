import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          l10n.appTitle,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: Text(l10n.posts),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.chat_outlined),
          selectedIcon: const Icon(Icons.chat),
          label: Text(l10n.chat),
        ),
        NavigationRailDestination(
          icon: _AccountAvatarIcon(size: 24),
          selectedIcon: _AccountAvatarIcon(size: 24, selected: true),
          label: Text(l10n.account),
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
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: NetworkImage(avatarUrl),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selectedIndex, required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: l10n.posts,
        ),
        NavigationDestination(
          icon: const Icon(Icons.chat_outlined),
          selectedIcon: const Icon(Icons.chat),
          label: l10n.chat,
        ),
        NavigationDestination(
          icon: const _AccountAvatarIcon(size: 24),
          selectedIcon: const _AccountAvatarIcon(size: 24, selected: true),
          label: l10n.account,
        ),
      ],
    );
  }
}
