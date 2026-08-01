import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/router/app_router.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/core/theme/app_theme.dart';

void main() {
  runApp(const OpenFieldApp());
}

class OpenFieldApp extends StatefulWidget {
  const OpenFieldApp({super.key});

  @override
  State<OpenFieldApp> createState() => _OpenFieldAppState();
}

class _OpenFieldAppState extends State<OpenFieldApp> {
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  late final GoRouter _router;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _router = createRouter(_authService);
    _setupDeepLinks();
  }

  Future<void> _setupDeepLinks() async {
    final appLinks = AppLinks();
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      _handleDeepLink(initial);
    }
    _linkSubscription = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (uri.host != 'oauth' && !uri.path.startsWith('/oauth')) return;

    final accessToken = uri.queryParameters['access_token'];
    if (accessToken == null) return;

    _authService.setTokens(accessToken);
    _authService.setUser(
      username: uri.queryParameters['username'],
      email: uri.queryParameters['email'],
      avatarUrl: uri.queryParameters['avatar_url'],
    );
  }
  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authService),
        ChangeNotifierProvider.value(value: _settingsService),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp.router(
            title: 'OpenField',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            locale: settings.locale != null ? Locale(settings.locale!) : null,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            routerDelegate: _router.routerDelegate,
            routeInformationParser: _router.routeInformationParser,
            routeInformationProvider: _router.routeInformationProvider,
          );
        },
      ),
    );
  }
}
