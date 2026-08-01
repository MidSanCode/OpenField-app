import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/account/attachments_page.dart';
import 'package:openfield/pages/account/my_posts_page.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/pages/register/register_page.dart';
import 'package:openfield/pages/settings/settings_page.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';

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
  bool _isBindingOAuth = false;

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

    // OAuth account-binding callback (no access_token is issued).
    final bindResult = uri.queryParameters['bind'];
    if (bindResult != null) {
      final l10n = AppLocalizations.of(context)!;
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.fetchCurrentUser();
      if (mounted) {
        final success = bindResult == 'success';
        final name = uri.queryParameters['name'];
        final msg = success
            ? (name != null && name.isNotEmpty
                ? '${l10n.oauthBindSuccess} ($name)'
                : l10n.oauthBindSuccess)
            : l10n.oauthBindFailed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        setState(() {});
      }
      return;
    }

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

  Future<void> _bindOAuth() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;

    setState(() => _isBindingOAuth = true);
    try {
      final authUrl = await _apiService.getOIDCBindUrl(token);
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isBindingOAuth = false);
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
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final username = _loginUsernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _isLoggingIn = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(username, password);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.clearTokens();
    if (mounted) setState(() {});
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
    final displayName = user?.displayName ?? authService.username ?? l10n.username;

    final hasOAuth = user?.hasOAuthBinding ?? false;
    final oauthName = hasOAuth && user != null
        ? (user.oauth2Username.isNotEmpty ? user.oauth2Username : 'OIDC')
        : '';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ---- Banner with centered avatar + nickname ----
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: bannerUrl != null
                  ? Image.network(bannerUrl, fit: BoxFit.cover)
                  : Container(
                      color: theme.colorScheme.primaryContainer,
                      child: Center(
                        child: Icon(
                          Icons.photo_outlined,
                          size: 48,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -52,
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      final currentUser = authService.user;
                      if (currentUser != null) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ProfilePage(userId: currentUser.id)),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: theme.colorScheme.surface,
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null ? const Icon(Icons.person, size: 44) : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  VerifiedName(
                    name: displayName,
                    verified: user?.isVerified ?? false,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (authService.email != null && authService.email!.isNotEmpty)
                    Text(
                      authService.email!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (user?.role == 'admin') ...[
                    const SizedBox(height: 6),
                    Chip(
                      avatar: const Icon(Icons.admin_panel_settings, size: 16),
                      label: Text(l10n.admin),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (user != null && user.storageQuota > 0) ...[
                    const SizedBox(height: 8),
                    _StorageChip(used: user.storageUsed, quota: user.storageQuota),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 62),

        // ---- Bio ----
        if (user != null && user.bio.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: MarkdownContent(data: user.bio),
          ),
        ],

        // ---- Sections ----
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsSection(
              title: l10n.oauthBinding,
              children: [
                ListTile(
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.link),
                  title: Text(l10n.oauthBinding),
                  subtitle: Text(
                    hasOAuth ? oauthName : l10n.oauthNotBound,
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
                  trailing: hasOAuth
                      ? Text(l10n.oauthBound,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ))
                      : TextButton(
                          onPressed: _isBindingOAuth ? null : _bindOAuth,
                          child: Text(l10n.bindOAuth),
                        ),
                ),
                if (!hasOAuth) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Text(
                      l10n.oauthUnbindAdminOnly,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            _SettingsSection(
              title: l10n.accountSettings,
              children: [
                ListTile(
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.article_outlined),
                  title: Text(l10n.myPosts),
                  subtitle: Text(
                    l10n.myPostsHint,
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MyPostsPage(userId: user!.id),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.attach_file),
                  title: Text(l10n.myAttachments),
                  subtitle: Text(
                    l10n.manageAttachmentsHint,
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AttachmentsPage()),
                    );
                  },
                ),
              ],
            ),

            _SettingsSection(
              title: l10n.settings,
              children: [
                ListTile(
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l10n.settings),
                  subtitle: Text(
                    l10n.accountSettings,
                    style: const TextStyle(fontSize: 12),
                  ),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),

            _SettingsSection(
              title: l10n.accountSettings,
              children: [
                ListTile(
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(l10n.editProfile),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
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
                  minLeadingWidth: 48,
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.logout),
                  contentPadding: const EdgeInsets.only(left: 24, right: 17),
                  onTap: _logout,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
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

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24, thickness: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
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
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.user;
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isSaving = true);
    try {
      await _apiService.updateProfile(
        auth.accessToken!,
        nickname: _nicknameController.text.trim(),
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim(),
      );
      await auth.fetchCurrentUser();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
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
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: l10n.username,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nicknameController,
              decoration: InputDecoration(
                labelText: l10n.nickname,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bioController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.bio,
                hintText: l10n.bioHint,
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
