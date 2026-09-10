import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';

/// Usernames are lowercase letters, digits and underscores (3-32 chars);
/// the same rule the server enforces at registration.
final RegExp _usernameRule = RegExp(r'^[a-z0-9_]{3,32}$');

/// Final step of first-time sign-up: collects username, nickname and optional
/// bio to complete an account created through the OAuth flow, then pops the
/// page on success. A taken username shows a localized error snackbar.
/// Usernames cannot be changed later (only admins rename), so the field
/// carries an explicit rule hint.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final bio = _bioController.text.trim();
    if (username.isEmpty || nickname.isEmpty) return;
    if (!_usernameRule.hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('usernameInvalid'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.register(username, nickname, bio: bio);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        final localized = message.contains('taken')
            ? 'usernameTaken'.tr()
            : (message.contains('lowercase') || message.contains('3-32'))
                ? 'usernameInvalid'.tr()
                : 'registrationFailed'.tr();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localized)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('completeRegistration'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text('registerHint'.tr(), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                LengthLimitingTextInputFormatter(32),
              ],
              decoration: InputDecoration(
                labelText: 'username'.tr(),
                helperText: 'usernameRule'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
             const SizedBox(height: 16),
             TextField(
               controller: _nicknameController,
               decoration: InputDecoration(
                 labelText: 'nickname'.tr(),
                 border: const OutlineInputBorder(),
               ),
             ),
             const SizedBox(height: 16),
             TextField(
               controller: _bioController,
               decoration: InputDecoration(
                 labelText: 'bio'.tr(),
                 hintText: 'bioHint'.tr(),
                 border: const OutlineInputBorder(),
               ),
               maxLines: 3,
             ),
             const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text('register'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
