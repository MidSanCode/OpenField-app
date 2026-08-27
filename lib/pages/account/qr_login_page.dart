import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// QR login handshake. On desktop (non-mobile) it creates a QR code and polls
/// for approval; on a phone it acts as the approver: scan the code shown on the
/// other device and approve the pending login.
class QrLoginPage extends StatelessWidget {
  const QrLoginPage({super.key});

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    return _isMobile ? const _QrApproverView() : const _QrRequesterView();
  }
}

/// Desktop side: create a code, show it as a QR, poll until the phone approves.
class _QrRequesterView extends StatefulWidget {
  const _QrRequesterView();

  @override
  State<_QrRequesterView> createState() => _QrRequesterViewState();
}

class _QrRequesterViewState extends State<_QrRequesterView> {
  final ApiService _api = ApiService();
  String? _code;
  bool _loading = true;
  Timer? _pollTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final code = await _api.createQrLogin(token);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _poll() async {
    if (_code == null || !mounted) return;
    try {
      final result = await _api.pollQrLogin(_code!);
      if (!mounted) return;
      if (result.isConfirmed) {
        _pollTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('qrLoginTitle'.tr())),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
                ? Text(_error!)
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
                          child: QrImageView(
                            data: _code!,
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 2),
                            const SizedBox(width: 12),
                            Text('qrLoginWaiting'.tr()),
                          ],
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Mobile side: scan the code shown on the other device and approve it.
class _QrApproverView extends StatefulWidget {
  const _QrApproverView();

  @override
  State<_QrApproverView> createState() => _QrApproverViewState();
}

class _QrApproverViewState extends State<_QrApproverView> {
  final ApiService _api = ApiService();
  final MobileScannerController _controller = MobileScannerController();
  bool _approving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _approve(String code) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || _approving) return;
    setState(() => _approving = true);
    try {
      await _api.approveQrLogin(token, code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('qrLoginApproved'.tr())),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _approving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('qrLoginTitle'.tr())),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code.isNotEmpty) {
                _controller.stop();
                _approve(code);
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'qrLoginScanHint'.tr(),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
