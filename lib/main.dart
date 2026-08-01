import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/log/log_overlay.dart';
import 'package:openfield/core/log/log_recorder.dart';
import 'package:openfield/core/router/app_router.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _initConsoleLogging();
  runApp(const OpenFieldApp());
}

void _initConsoleLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      final stack = record.error != null ? ' error=${record.error}' : '';
      debugPrint('[${record.level.name}] ${record.message}$stack');
    }
  });
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
    LogService.instance.setEnabled(_settingsService.developerMode);
    ApiService.setServerHost(_settingsService.serverHost);
    _settingsService.addListener(_syncServerHost);
    _router = createRouter(_authService, appNavigatorKey);
    _setupDeepLinks();
  }

  void _syncServerHost() {
    ApiService.setServerHost(_settingsService.serverHost);
  }

  @override
  void dispose() {
    _settingsService.removeListener(_syncServerHost);
    _linkSubscription?.cancel();
    super.dispose();
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
            builder: (context, child) {
              final bgPath = settings.backgroundImagePath;
              if (bgPath == null) return child!;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(
                      File(bgPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  child!,
                ],
              );
            },
          );
        },
      ),
    );
  }
}
