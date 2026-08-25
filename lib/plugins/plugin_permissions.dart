/// Client-side plugin permission catalog with security levels.
///
/// Every privileged API a plugin may call maps to one permission key; the key
/// carries a [PermissionLevel] that drives both the UI (badge colors,
/// grouping in the consent dialog) and the default-deny posture of the
/// runtime gateway.
library;

/// How sensitive a permission is. Higher levels demand clearer user consent
/// and render in warmer colors.
enum PermissionLevel {
  /// Read-only / purely local effects (e.g. namespaced storage, logging).
  safe,

  /// Ordinary capabilities with bounded blast radius (network fetch to
  /// allow-listed hosts, reading public content).
  normal,

  /// Touches personal data or device UX (profile info, notifications).
  sensitive,

  /// Can act on behalf of the user or expose private conversations.
  critical,
}

/// One grantable permission in the plugin system.
class PluginPermissionDef {
  final String id;

  /// Localization key for the display name.
  final String labelKey;

  /// Localization key for the one-line explanation.
  final String hintKey;

  final PermissionLevel level;

  const PluginPermissionDef({
    required this.id,
    required this.labelKey,
    required this.hintKey,
    required this.level,
  });
}

const pluginPermissionCatalog = <String, PluginPermissionDef>{
  // ---- Level 0: safe ----
  'storage': PluginPermissionDef(
    id: 'storage',
    labelKey: 'permStorage',
    hintKey: 'permStorageHint',
    level: PermissionLevel.safe,
  ),
  'log': PluginPermissionDef(
    id: 'log',
    labelKey: 'permLog',
    hintKey: 'permLogHint',
    level: PermissionLevel.safe,
  ),
  'ui.toast': PluginPermissionDef(
    id: 'ui.toast',
    labelKey: 'permToast',
    hintKey: 'permToastHint',
    level: PermissionLevel.safe,
  ),

  // ---- Level 1: normal ----
  'http.fetch': PluginPermissionDef(
    id: 'http.fetch',
    labelKey: 'permHttp',
    hintKey: 'permHttpHint',
    level: PermissionLevel.normal,
  ),
  'posts.read': PluginPermissionDef(
    id: 'posts.read',
    labelKey: 'permPostsRead',
    hintKey: 'permPostsReadHint',
    level: PermissionLevel.normal,
  ),
  'clipboard.write': PluginPermissionDef(
    id: 'clipboard.write',
    labelKey: 'permClipboard',
    hintKey: 'permClipboardHint',
    level: PermissionLevel.normal,
  ),

  // ---- Level 2: sensitive ----
  'notifications': PluginPermissionDef(
    id: 'notifications',
    labelKey: 'permNotifications',
    hintKey: 'permNotificationsHint',
    level: PermissionLevel.sensitive,
  ),
  'account.profile': PluginPermissionDef(
    id: 'account.profile',
    labelKey: 'permAccountProfile',
    hintKey: 'permAccountProfileHint',
    level: PermissionLevel.sensitive,
  ),

  // ---- Level 3: critical ----
  'chat.read': PluginPermissionDef(
    id: 'chat.read',
    labelKey: 'permChatRead',
    hintKey: 'permChatReadHint',
    level: PermissionLevel.critical,
  ),
  'chat.send': PluginPermissionDef(
    id: 'chat.send',
    labelKey: 'permChatSend',
    hintKey: 'permChatSendHint',
    level: PermissionLevel.critical,
  ),
};

/// Looks up a permission definition; unknown ids fall back to the most
/// restrictive presentation so an unrecognized request never looks harmless.
PluginPermissionDef? permissionDefOf(String id) => pluginPermissionCatalog[id];

/// Resolves the effective level of a permission id (unknown → critical).
PermissionLevel levelOf(String id) =>
    pluginPermissionCatalog[id]?.level ?? PermissionLevel.critical;
