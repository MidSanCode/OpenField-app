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
import 'package:openfield/core/web/history_stub.dart'
    if (dart.library.html) 'package:openfield/core/web/history_web.dart';
import 'package:openfield/core/windows/protocol_registration.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/permission_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    ensureOpenFieldProtocol();
  }
  _initConsoleLogging();
  runApp(const OpenFieldApp());
}

void _initConsoleLogging() {
  Logger.root.level = Level.ALL;
  // Keep the original function: the bridged debugPrint below feeds every
  // message back into Logger, so the console listener must print directly
  // to avoid an infinite loop.
  final originalDebugPrint = debugPrint;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      final stack = record.error != null ? ' error=${record.error}' : '';
      originalDebugPrint('[${record.level.name}] ${record.message}$stack');
    }
  });
  // Bridge Flutter's print()/debugPrint() output and uncaught framework
  // errors into the package:logging stream so the log viewer captures them.
  debugPrint = (String? message, {int? wrapWidth}) {
    Logger.root.info(message ?? '');
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    Logger.root.severe(
      'Flutter error: ${details.exception}',
      details.exception,
      details.stack,
    );
    originalOnError?.call(details);
  };
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
  String? _lastSyncedHost;

  @override
  void initState() {
    super.initState();
    // Logging follows developer mode, which is read from prefs asynchronously.
    _settingsService.ready.then((_) {
      LogService.instance.setEnabled(_settingsService.developerMode);
    });
    _lastSyncedHost = _settingsService.serverHost;
    ApiService.setServerHost(_settingsService.serverHost);
    _settingsService.addListener(_syncServerHost);
    _router = createRouter(_authService, appNavigatorKey);
    _setupDeepLinks();
    _authService.addListener(_syncRealtimeConnection);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRealtimeConnection(),
    );
    // Ask for the runtime permissions the app relies on (notifications, photo
    // library). Requests are fire-and-forget and never block startup.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PermissionService.requestOnLaunch(),
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
    final host = _settingsService.serverHost;
    if (host == _lastSyncedHost) return;
    _lastSyncedHost = host;
    ApiService.setServerHost(host);
    // Account sessions are bound to the server that issued them: when the host
    // changes, switch to the account saved for the new server (or log out).
    _authService.switchServer(host);
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

    // Web fallback: an OIDC redirect to the app's own URL may carry the
    // tokens in the query string. app_links does not always deliver the
    // initial link on web, so inspect Uri.base directly and then strip the
    // credentials from the browser URL.
    if (kIsWeb) {
      final base = Uri.base;
      if (base.queryParameters.containsKey('access_token') ||
          base.queryParameters.containsKey('bind')) {
        _handleDeepLink(base);
        clearUrlQueryParams();
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
    // Accept the OAuth scheme (openfield://oauth/...), an explicit /oauth path
    // (app hosted under a /oauth path), or any URL carrying the access_token /
    // bind query params (browser OIDC redirect back to the app).
    final isOAuthUri = uri.host == 'oauth' || uri.path.startsWith('/oauth');
    final hasOAuthParams = uri.queryParameters.containsKey('access_token') ||
        uri.queryParameters.containsKey('bind');
    if (!isOAuthUri && !hasOAuthParams) return;
    if (_deepLinkHandled) return;
    _deepLinkHandled = true;

    final accessToken = uri.queryParameters['access_token'];
    if (accessToken == null) return;

    _authService.setTokens(
      accessToken,
      refreshToken: uri.queryParameters['refresh_token'],
      expiresIn: int.tryParse(uri.queryParameters['expires_in'] ?? ''),
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
                  theme: AppTheme.light(settings.accentColor),
                  darkTheme: AppTheme.dark(settings.accentColor),
                  themeMode: settings.themeMode,
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  routerDelegate: _router.routerDelegate,
                  routeInformationParser: _router.routeInformationParser,
                  routeInformationProvider: _router.routeInformationProvider,
                  builder: (context, child) {
                    final bgPath =
                        settings.backgroundVisible ? settings.backgroundImagePath : null;
                    var themed = child!;
                    if (bgPath != null) {
                      // Opaque scaffold surfaces would otherwise cover the
                      // background image entirely, so make page backgrounds
                      // transparent while the image is active. Cards, app bars
                      // and other explicit surfaces keep their own colors.
                      themed = Theme(
                        data: Theme.of(context).copyWith(
                          scaffoldBackgroundColor: Colors.transparent,
                        ),
                        child: themed,
                      );
                      return Stack(
                        children: [
                          Positioned.fill(
                            // ValueKey forces Flutter to rebuild the underlying
                            // image element when the path changes; without it the
                            // cached decoded image is reused and the new
                            // background never appears until a restart.
                            child: Image.file(
                              File(bgPath),
                              key: ValueKey('bg:$bgPath'),
                              fit: BoxFit.cover,
                              gaplessPlayback: false,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                          themed,
                        ],
                      );
                    }
                    return themed;
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
