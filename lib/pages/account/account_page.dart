import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/attachments_page.dart';
import 'package:openfield/pages/account/favorites_page.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/pages/account/tasks_page.dart';
import 'package:openfield/pages/account/wallet_page.dart';
import 'package:openfield/pages/register/register_page.dart';
import 'package:openfield/pages/settings/settings_page.dart';
import 'package:openfield/widgets/experience_bar.dart';
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
  final TextEditingController _tokenController = TextEditingController();
  StreamSubscription<Uri>? _linkSubscription;
  bool _isLoggingIn = false;
  bool _claimingDailyBonus = false;

  Future<void> _claimDailyBonus(AuthService authService) async {
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _claimingDailyBonus = true);
    try {
      final data = await _apiService.claimDailyBonus(token);
      await authService.fetchCurrentUser();
      if (!mounted) return;
      final granted = data['granted'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'dailyBonusClaimed'.tr(namedArgs: {'exp': '${data['amount'] ?? ''}'})
                : 'dailyBonusAlready'.tr(),
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _claimingDailyBonus = false);
    }
  }

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
    _tokenController.dispose();
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
    final isOAuthUri = uri.host == 'oauth' || uri.path.startsWith('/oauth');
    final hasOAuthParams = uri.queryParameters.containsKey('access_token') ||
        uri.queryParameters.containsKey('bind');
    if (!isOAuthUri && !hasOAuthParams) return;

    // Skip if main.dart already processed this deep link (e.g., Windows argv).
    final incomingToken = uri.queryParameters['access_token'];
    final authService = Provider.of<AuthService>(context, listen: false);
    if (incomingToken != null && authService.accessToken == incomingToken) {
      return;
    }

    // OAuth account-binding callback (no access_token is issued).
    final bindResult = uri.queryParameters['bind'];
    if (bindResult != null) {
      await authService.fetchCurrentUser();
      if (mounted) {
        final success = bindResult == 'success';
        final name = uri.queryParameters['name'];
        final msg = success
            ? (name != null && name.isNotEmpty
                ? '${'oauthBindSuccess'.tr()}} ($name)'
                : 'oauthBindSuccess'.tr())
            : 'oauthBindFailed'.tr();
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

    await authService.setTokens(
      accessToken,
      refreshToken: uri.queryParameters['refresh_token'],
      expiresIn: int.tryParse(uri.queryParameters['expires_in'] ?? ''),
    );
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

  Future<void> _loginWithToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;

    setState(() => _isLoggingIn = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.loginWithToken(token);
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
    final isAuthenticated = authService.isAuthenticated;

    return Scaffold(
      appBar: AppBar(title: Text('account'.tr())),
      body: isAuthenticated
          ? _buildProfile(context, authService)
          : _buildLogin(context, authService),
    );
  }

  Widget _buildLogin(BuildContext context, AuthService authService) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isLoggingIn ? null : _loginWithOIDC,
                icon: const Icon(Icons.login),
                label: Text('loginWithOIDC'.tr()),
              ),
              const SizedBox(height: 12),
              _buildAdvancedLogin(context),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
                icon: const Icon(Icons.settings_outlined),
                label: Text('settings'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedLogin(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.keyboard_arrow_down),
        title: Text('advancedLogin'.tr()),
        subtitle: Text('advancedLoginHint'.tr(), style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _loginUsernameController,
            decoration: InputDecoration(
              labelText: 'username'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'password'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('localAccountHint'.tr(), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isLoggingIn ? null : _loginWithPassword,
            icon: const Icon(Icons.login),
            label: Text('loginWithPassword'.tr()),
          ),
          const Divider(height: 32),
          TextField(
            controller: _tokenController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'tokenLogin'.tr(),
              hintText: 'tokenPlaceholder'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('tokenLoginHint'.tr(), style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isLoggingIn ? null : _loginWithToken,
            icon: const Icon(Icons.vpn_key),
            label: Text('tokenLogin'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(BuildContext context, AuthService authService) {
    final theme = Theme.of(context);
    final user = authService.user;
    final bannerUrl = user?.bannerUrl.isNotEmpty == true ? user!.bannerUrl : null;
    final avatarUrl = authService.avatarUrl != null && authService.avatarUrl!.isNotEmpty
        ? authService.avatarUrl!
        : (user?.avatarUrl.isNotEmpty == true ? user!.avatarUrl : null);
    final displayName = user?.displayName ?? authService.username ?? 'username'.tr();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ---- Banner with overlapping avatar ----
        _buildProfileHeader(
          context,
          theme,
          authService,
          user,
          bannerUrl: bannerUrl,
          avatarUrl: avatarUrl,
          displayName: displayName,
        ),
        // ---- Level & daily bonus ----
        if (user != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildLevelCard(context, theme, authService, user),
          ),
        // ---- Bio ----
        if (user != null && user.bio.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: MarkdownContent(data: user.bio),
          ),
        ],

        // ---- Sections grouped by related functionality ----
        _SettingsSection(
          title: 'account'.tr(),
          children: [
            if (user != null)
              _NavTile(
                icon: Icons.badge_outlined,
                title: 'accountSettings'.tr(),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
                  );
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        _SettingsSection(
          title: 'walletAndRewards'.tr(),
          children: [
            _NavTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'wallet'.tr(),
              subtitle: 'walletHint'.tr(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletPage()),
                );
              },
            ),
            const Divider(height: 1),
            _NavTile(
              icon: Icons.emoji_events_outlined,
              title: 'tasks'.tr(),
              subtitle: 'taskMilestones'.tr(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TasksPage()),
                );
              },
            ),
          ],
        ),
        _SettingsSection(
          title: 'myContent'.tr(),
          children: [
            if (user != null)
              _NavTile(
                icon: Icons.attach_file,
                title: 'myAttachments'.tr(),
                subtitle: 'manageAttachmentsHint'.tr(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AttachmentsPage()),
                  );
                },
              ),
            if (user != null) const Divider(height: 1),
            _NavTile(
              icon: Icons.bookmarks_outlined,
              title: 'favorites'.tr(),
              subtitle: 'favoritesPosts'.tr(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoritesPage()),
                );
              },
            ),
          ],
        ),
        _SettingsSection(
          title: 'appSettings'.tr(),
          children: [
            _NavTile(
              icon: Icons.settings_outlined,
              title: 'settings'.tr(),
              subtitle: 'appSettings'.tr(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            const Divider(height: 1),
            _NavTile(
              icon: Icons.logout,
              title: 'logout'.tr(),
              showChevron: false,
              onTap: _logout,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLevelCard(
    BuildContext context,
    ThemeData theme,
    AuthService authService,
    User user,
  ) {
    final canClaim = user.canClaimDailyBonus;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExperienceBar(user: user),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.card_giftcard_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canClaim ? 'dailyBonusHint'.tr() : 'dailyBonusDone'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed:
                      canClaim && !_claimingDailyBonus ? () => _claimDailyBonus(authService) : null,
                  icon: _claimingDailyBonus
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 18),
                  label: Text('claimDailyBonus'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Banner with the avatar straddling its bottom edge and the identity block
  /// pulled up tight against it.
  Widget _buildProfileHeader(
    BuildContext context,
    ThemeData theme,
    AuthService authService,
    User? user, {
    required String? bannerUrl,
    required String? avatarUrl,
    required String displayName,
  }) {
    const avatarRadius = 44.0;
    const bannerHeight = 160.0;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: bannerHeight,
              child: bannerUrl != null
                  ? MediaImage(url: bannerUrl, fit: BoxFit.cover)
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
            // Space for the lower half of the overlapping avatar.
            const SizedBox(height: avatarRadius),
            Center(
              child: VerifiedName(
                name: displayName,
                verified: user?.isVerified ?? false,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (authService.email != null && authService.email!.isNotEmpty)
              Center(
                child: Text(
                  authService.email!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (user?.role == 'admin') ...[
              const SizedBox(height: 6),
              Center(
                child: Chip(
                  avatar: const Icon(Icons.admin_panel_settings, size: 16),
                  label: Text('admin'.tr()),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
        Positioned(
          // Top edge of the avatar sits on the banner's bottom edge so it
          // overlaps the boundary, with the lower half spilling below.
          top: bannerHeight - avatarRadius,
          left: 0,
          right: 0,
          child: Center(
            child: InkWell(
              onTap: () {
                final currentUser = authService.user;
                if (currentUser != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProfilePage(userId: currentUser.id)),
                  );
                }
              },
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: theme.colorScheme.surface,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null ? const Icon(Icons.person, size: 44) : null,
              ),
            ),
          ),
        ),
      ],
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;

  const _NavTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 48,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(fontSize: 12),
            )
          : null,
      contentPadding: const EdgeInsets.only(left: 24, right: 17),
      trailing: showChevron ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final ApiService _apiService = ApiService();
  late final TextEditingController _nicknameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool _isSaving = false;
  bool _isBindingOAuth = false;

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
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('saved'.tr())),
        );
      }
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  Future<void> _pickAvatar() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;
    try {
      await _apiService.uploadAvatar(result.path, auth.accessToken!);
      await auth.fetchCurrentUser();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('saved'.tr())),
        );
      }
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    }
  }

  Future<void> _pickBanner() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;
    try {
      await _apiService.uploadBanner(result.path, auth.accessToken!);
      await auth.fetchCurrentUser();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('saved'.tr())),
        );
      }
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context);
    final user = authService.user;
    final hasOAuth = user?.hasOAuthBinding ?? false;
    final oauthName = hasOAuth && user != null
        ? (user.oauth2Username.isNotEmpty ? user.oauth2Username : 'OIDC')
        : '';

    return Scaffold(
      appBar: AppBar(title: Text('accountSettings'.tr())),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ---- Edit profile fields ----
          _SectionHeader(title: 'nickname'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'username'.tr(),
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
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'bio'.tr(),
                      hintText: 'bioHint'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.save),
                    label: Text('save'.tr()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- Avatar & banner ----
          _SectionHeader(title: 'setAvatar'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('setAvatar'.tr()),
                  subtitle: Text(
                    authService.avatarUrl?.isNotEmpty == true ? 'saved'.tr() : '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickAvatar,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: Text('setBanner'.tr()),
                  subtitle: Text(
                    user?.bannerUrl.isNotEmpty == true ? 'saved'.tr() : '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickBanner,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- OAuth binding ----
          _SectionHeader(title: 'oauthBinding'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text('oauthBinding'.tr()),
                  subtitle: Text(
                    hasOAuth ? oauthName : 'oauthNotBound'.tr(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: hasOAuth
                      ? Text(
                          'oauthBound'.tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : TextButton(
                          onPressed: _isBindingOAuth ? null : _bindOAuth,
                          child: Text('bindOAuth'.tr()),
                        ),
                ),
                if (!hasOAuth) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      'oauthUnbindAdminOnly'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Settings ----
          // Removed: app settings now live on the account page itself so they
          // are reachable without logging in.
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
