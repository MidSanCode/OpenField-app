import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shows a 6-digit payment PIN entry dialog.
///
/// [mode] is `set` when the user must choose a new PIN (entered twice) and
/// `verify` when an existing PIN must be confirmed to authorize a payment.
/// Resolves with the entered PIN when confirmed, or `null` when cancelled.
Future<String?> showPinDialog(
  BuildContext context, {
  required bool isSetting,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PinDialog(isSetting: isSetting),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.isSetting});

  final bool isSetting;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() => _error = 'pinInvalid'.tr());
      return;
    }
    if (widget.isSetting) {
      if (_confirmController.text.trim() != pin) {
        setState(() => _error = 'pinMismatch'.tr());
        return;
      }
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.isSetting ? 'pinSetTitle'.tr() : 'pinVerifyTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isSetting ? 'pinSetHint'.tr() : 'pinVerifyHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            obscureText: _obscure,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'pinLabel'.tr(),
              counterText: '',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.isSetting) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              obscureText: _obscure,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'pinConfirmLabel'.tr(),
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isSetting ? 'pinSave'.tr() : 'confirm'.tr()),
        ),
      ],
    );
  }
}