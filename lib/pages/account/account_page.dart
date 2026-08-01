import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/account/attachments_page.dart';
import 'package:openfield/pages/register/register_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  StreamSubscription<Uri>? _linkSubscription;
  bool _isLoggingIn = false;
  bool _isPasswordLogin = false;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _listenForOAuthCallback();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.fetchCurrentUser();
      if (mounted && user != null && user.needsRegistration) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RegisterPage()),
        );
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _loginUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _listenForOAuthCallback() {
    final appLinks = AppLinks();
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (e) {
      // handle error
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.host != 'oauth' && !uri.path.startsWith('/oauth')) return;

    final accessToken = uri.queryParameters['access_token'];
    final username = uri.queryParameters['username'];
    final email = uri.queryParameters['email'];
    final needsRegistration = uri.queryParameters['needs_registration'] == 'true';
    if (accessToken == null) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.setTokens(accessToken);
    if (username != null) authService.setUsername(username);
    if (email != null) authService.setEmail(email);
    if (mounted) setState(() {});

    if (needsRegistration && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterPage()),
      );
    }
  }

  Future<void> _loginWithOIDC() async {
    setState(() => _isLoggingIn = true);
    try {
      final authUrl = await _apiService.getOIDCLoginUrl();
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.loadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final username = _loginUsernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _isLoggingIn = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(username, password);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loginFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.clearTokens();
    if (mounted) setState(() {});
  }

  Future<void> _pickImage(Future<void> Function(String path) onPicked) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _isUploadingImage = true);
    try {
      await onPicked(file.path);
      await authService.fetchCurrentUser();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final l10n = AppLocalizations.of(context)!;
    final isAuthenticated = authService.isAuthenticated;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.account)),
      body: isAuthenticated
          ? _buildProfile(context, authService, l10n)
          : _buildLogin(context, authService, l10n),
    );
  }

  Widget _buildLogin(BuildContext context, AuthService authService, AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoggingIn ? null : _loginWithOIDC,
              icon: const Icon(Icons.login),
              label: Text(l10n.loginWithOIDC),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isPasswordLogin = !_isPasswordLogin),
              child: Text(l10n.loginWithPassword),
            ),
            if (_isPasswordLogin) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _loginUsernameController,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.localAccountHint, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoggingIn ? null : _loginWithPassword,
                icon: const Icon(Icons.login),
                label: Text(l10n.loginWithPassword),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(BuildContext context, AuthService authService, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final user = authService.user;
    final bannerUrl = user?.bannerUrl.isNotEmpty == true ? user!.bannerUrl : null;
    final avatarUrl = authService.avatarUrl != null && authService.avatarUrl!.isNotEmpty
        ? authService.avatarUrl!
        : (user?.avatarUrl.isNotEmpty == true ? user!.avatarUrl : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: 160,
                width: double.infinity,
                child: bannerUrl != null
                    ? Image.network(bannerUrl, fit: BoxFit.cover)
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.image_outlined, size: 48)),
                      ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage((path) => _apiService.uploadBanner(path, authService.accessToken!)),
                  icon: const Icon(Icons.edit),
                  tooltip: l10n.setBanner,
                ),
              ),
              Positioned(
                left: 16,
                bottom: -40,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: theme.colorScheme.surface,
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null
                          ? const Icon(Icons.person, size: 40)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filledTonal(
                        onPressed: _isUploadingImage
                            ? null
                            : () => _pickImage((path) => _apiService.uploadAvatar(path, authService.accessToken!)),
                        icon: const Icon(Icons.edit, size: 16),
                        tooltip: l10n.setAvatar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.displayName ?? authService.username ?? l10n.username,
                        style: theme.textTheme.headlineSmall),
                    if (authService.email != null && authService.email!.isNotEmpty)
                      Text(authService.email!, style: theme.textTheme.bodyMedium),
                    if (user?.role == 'admin') ...[
                      const SizedBox(height: 4),
                      Chip(
                        avatar: const Icon(Icons.admin_panel_settings, size: 16),
                        label: Text(l10n.admin),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),
              if (user != null && user.storageQuota > 0)
                _StorageChip(used: user.storageUsed, quota: user.storageQuota),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Attachment management ----
        _SectionCard(
          title: l10n.myAttachments,
          icon: Icons.folder_outlined,
          child: ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l10n.myAttachments),
            subtitle: Text(l10n.manageAttachmentsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AttachmentsPage()),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // ---- App settings ----
        _SectionCard(
          title: l10n.appSettings,
          icon: Icons.tune,
          child: _buildAppSettings(context, l10n),
        ),
        const SizedBox(height: 16),

        // ---- Account settings ----
        _SectionCard(
          title: l10n.accountSettings,
          icon: Icons.person_outline,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.editProfile),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                  if (mounted) setState(() {});
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.logout),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppSettings(BuildContext context, AppLocalizations l10n) {
    final settings = Provider.of<SettingsService>(context);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.language),
          subtitle: Text(settings.locale == 'zh' ? '中文' : 'English'),
          trailing: DropdownButton<String>(
            value: settings.locale,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: null, child: Text('Auto')),
              DropdownMenuItem(value: 'zh', child: Text('中文')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (value) => settings.setLocale(value),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: Text(l10n.theme),
          trailing: DropdownButton<ThemeMode>(
            value: settings.themeMode,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.systemMode)),
              DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.lightMode)),
              DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.darkMode)),
            ],
            onChanged: (mode) {
              if (mode != null) settings.setThemeMode(mode);
            },
          ),
        ),
      ],
    );
  }
}

class _StorageChip extends StatelessWidget {
  final int used;
  final int quota;

  const _StorageChip({required this.used, required this.quota});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedMb = used / (1024 * 1024);
    final quotaMb = quota / (1024 * 1024);
    final ratio = quota > 0 ? used / quota : 0.0;

    return Tooltip(
      message: '${usedMb.toStringAsFixed(1)} MB / ${quotaMb.toStringAsFixed(1)} MB',
      child: Column(
        children: [
          Text('${usedMb.toStringAsFixed(1)} MB', style: theme.textTheme.bodySmall),
          SizedBox(
            width: 80,
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: ratio > 0.9 ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final ApiService _apiService = ApiService();
  late final TextEditingController _nicknameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthService>(context, listen: false);
    _nicknameController = TextEditingController(text: auth.username ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSaving = true);
    try {
      await _apiService.updateProfile(auth.accessToken!, nickname: _nicknameController.text.trim());
      await auth.fetchCurrentUser();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saved)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editProfile)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nicknameController,
              decoration: InputDecoration(
                labelText: l10n.nickname,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
