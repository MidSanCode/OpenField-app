/// The features this client build actually implements, keyed identically to the
/// server's capability list so the settings page can diff the two and report
/// how many features each side supports.
class ClientCapabilities {
  const ClientCapabilities._();

  /// Feature keys this client supports. Kept in sync with the server's
  /// `ServerCapabilities` map; anything here must have real client code behind
  /// it, not merely a server endpoint.
  static const Set<String> supported = {
    'auth.password_login',
    'auth.oidc_login',
    'user.password_register',
    'user.e2ee_key',
    'user.exp_levels',
    'user.daily_bonus',
    'user.adjust_exp',
    'chat.private_chat',
    'chat.group_chat',
    'chat.public_groups',
    'chat.e2ee',
    'chat.encrypted_private',
    'chat.mentions',
    'chat.notify_level',
    'chat.member_titles',
    'posts.create',
    'posts.replies',
    'posts.reactions',
    'storage.uploads',
    'storage.chunked_uploads',
    'realtime.websocket',
  };
}