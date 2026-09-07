import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// QR login, requesting side. Shown on the LOGIN screen of the device that
/// wants to sign in: it creates a handshake code (no session needed), renders
/// it as a QR and polls until an already-authenticated device scans and
/// approves it. Codes expire after five minutes; the screen offers a refresh
/// action once that happens.
///
/// The scanning/approving side lives in QrScanPage (opened from the
/// authenticated settings screen) — a signed-in device never shows a login QR
/// itself.
class QrLoginPage extends StatefulWidget {
  const QrLoginPage({super.key});

  @override
  State<QrLoginPage> createState() => _QrLoginPageState();
}

/// State for [QrLoginPage]: creates the handshake code, polls every two
/// seconds for approval and stores the tokens once confirmed.
class _QrLoginPageState extends State<QrLoginPage> {
  final ApiService _api = ApiService();
  String? _code;
  bool _loading = true;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  String? _error;
  DateTime? _expiresAt;

  bool get _expired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _code = null;
      });
    }
    try {
      final code = await _api.createQrLogin();
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
        // Server-side TTL is five minutes; track a local deadline for the
        // countdown and stop polling once it lapses.
        _expiresAt = DateTime.now().add(const Duration(minutes: 5));
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {}); // tick the countdown text
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _poll() async {
    if (_code == null || !mounted || _expired) return;
    try {
      final result = await _api.pollQrLogin(_code!);
      if (!mounted) return;
      if (result.isConfirmed) {
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        final auth = Provider.of<AuthService>(context, listen: false);
        await auth.setTokens(
          result.accessToken!,
          refreshToken: result.refreshToken,
          expiresIn: result.expiresIn,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      // Transient poll failures are ignored; the next tick retries.
    }
  }

  String get _countdownText {
    final expires = _expiresAt;
    if (expires == null) return '';
    final left = expires.difference(DateTime.now());
    if (left.isNegative) return '';
    final m = left.inMinutes;
    final s = left.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('qrLoginTitle'.tr())),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.refresh),
                          label: Text('retry'.tr()),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('qrLoginHint'.tr(),
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _expired
                              ? SizedBox(
                                  width: 220,
                                  height: 220,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.timer_off_outlined,
                                            size: 40),
                                        const SizedBox(height: 12),
                                        Text('qrLoginExpired'.tr(),
                                            textAlign: TextAlign.center),
                                      ],
                                    ),
                                  ),
                                )
                              : QrImageView(
                                  data: _code!,
                                  version: QrVersions.auto,
                                  size: 220,
                                ),
                        ),
                        const SizedBox(height: 16),
                        if (_expired)
                          FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.refresh),
                            label: Text('qrLoginExpired'.tr()),
                          )
                        else ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(strokeWidth: 2),
                              const SizedBox(width: 12),
                              Text('qrLoginWaiting'.tr()),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_countdownText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [],
                              )),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
