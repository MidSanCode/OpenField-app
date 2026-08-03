import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/log/log_overlay.dart';
import 'package:openfield/core/log/log_recorder.dart';
import 'package:openfield/core/router/app_router.dart';
import 'package:openfield/core/windows/protocol_registration.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    ensureOpenFieldProtocol();
  }
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
  bool _deepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    LogService.instance.setEnabled(_settingsService.developerMode);
    ApiService.setServerHost(_settingsService.serverHost);
    _settingsService.addListener(_syncServerHost);
    _router = createRouter(_authService, appNavigatorKey);
    _setupDeepLinks();
    _authService.addListener(_syncRealtimeConnection);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRealtimeConnection(),
    );
  }

  /// Connects the realtime WebSocket while authenticated, disconnecting it
  /// immediately when the user logs out.
  void _syncRealtimeConnection() {
    final token = _authService.accessToken;
    if (token != null) {
      RealtimeService.instance.connect(token);
    } else {
      RealtimeService.instance.disconnect();
    }
  }

  void _syncServerHost() {
    ApiService.setServerHost(_settingsService.serverHost);
  }

  @override
  void dispose() {
    _settingsService.removeListener(_syncServerHost);
    _authService.removeListener(_syncRealtimeConnection);
    RealtimeService.instance.disconnect();
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setupDeepLinks() async {
    // Windows fallback: when the app is launched from a protocol URL,
    // the URI is passed as a command-line argument because app_links
    // does not reliably deliver the initial link on this platform.
    if (!kIsWeb && Platform.isWindows) {
      for (final arg in Platform.executableArguments) {
        final trimmed = arg.trim();
        if (trimmed.startsWith('openfield://')) {
          _handleDeepLink(Uri.parse(trimmed));
          break;
        }
      }
    }

    final appLinks = AppLinks();
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      _handleDeepLink(initial);
    }
    _linkSubscription = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (uri.host != 'oauth' && !uri.path.startsWith('/oauth')) return;
    if (_deepLinkHandled) return;
    _deepLinkHandled = true;

    final accessToken = uri.queryParameters['access_token'];
    if (accessToken == null) return;

    _authService.setTokens(
      accessToken,
      refreshToken: uri.queryParameters['refresh_token'],
    );
    _authService.setUser(
      username: uri.queryParameters['username'],
      email: uri.queryParameters['email'],
      avatarUrl: uri.queryParameters['avatar_url'],
    );

    // Bind result (no token issued).
    final bindResult = uri.queryParameters['bind'];
    if (bindResult != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    // Login: fetch full profile and navigate to account page.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _authService.fetchCurrentUser();
      if (mounted) {
        setState(() {});
        _router.go('/account');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _settingsService.ready,
      builder: (context, snapshot) {
        final savedLocale = _settingsService.locale;
        return EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('zh')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: savedLocale != null ? Locale(savedLocale) : null,
          child: MultiProvider(
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
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
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
          ),
        );
      },
    );
  }
}
