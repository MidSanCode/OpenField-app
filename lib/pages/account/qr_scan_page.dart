import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/profile_page.dart';

/// QR login, scanning/approving side. Opened from the account settings of an
/// ALREADY signed-in device: it scans the code shown on the requesting
/// device's login screen and approves the handshake. Signed-in devices never
/// display a login QR themselves — the requesting side renders it.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final ApiService _api = ApiService();
  final MobileScannerController _controller = MobileScannerController();
  bool _approving = false;

  @override
  void dispose() {
    // stop() before dispose(): on iOS the AVCaptureSession teardown races
    // an active session and can abort the app when disposing mid-stream.
    _controller.stop().catchError((_) {});
    _controller.dispose();
    super.dispose();
  }

  /// Dispatches a scanned payload: app deep links (profile / group QRs)
  /// navigate in-app, anything else is treated as a login handshake code to
  /// approve for the requesting device.
  Future<void> _handlePayload(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'openfield') {
      final id = int.tryParse(uri.path.replaceFirst('/', ''));
      if (uri.host == 'user' && id != null && id > 0) {
        if (mounted) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ProfilePage(userId: id)),
          );
        }
        return;
      }
      if (uri.host == 'group' && id != null && id > 0) {
        await _joinGroup(id);
        return;
      }
      // Unknown deep link: fall through to the login-handshake path.
    }
    await _approve(raw);
  }

  /// Joins the scanned group after a confirmation. Private groups reject the
  /// join server-side and the error surfaces in a snackbar.
  Future<void> _joinGroup(int conversationId) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || _approving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('groupJoinQrTitle'.tr()),
        content: Text('groupJoinQrBody'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('groupJoin'.tr())),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approving = true);
    try {
      await _api.joinGroup(token, conversationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('groupJoinSuccess'.tr())),
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
      appBar: AppBar(title: Text('qrScanTitle'.tr())),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error, child) {
              // Camera permission denied / camera unavailable: show a
              // readable screen instead of an empty preview.
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'qrLoginCameraUnavailable'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              );
            },
            onDetect: (capture) {
              // Barcode frames keep arriving while the approval request is
              // in flight; the guard also stops double-fires racing the
              // controller stop + page pop (a known crash shape on iOS).
              if (_approving) return;
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code.isNotEmpty) {
                _controller.stop().catchError((_) {});
                _handlePayload(code);
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
                'qrScanHint'.tr(),
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

/// True on platforms that can realistically open the scanner (phone builds);
/// desktop and web do not carry a useful camera setup here.
bool get qrScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
