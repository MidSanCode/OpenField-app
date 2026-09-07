# OpenField App (Flutter)

The OpenField client is a Flutter application for the OpenField platform. It
talks only to the gateway (`http://localhost:8080/api/v1`), never to the
internal services directly.

## Stack

- Flutter (Material 3) with `easy_localization` for Chinese / English UI text.
- `provider` for state management; REST via `http` (see `ApiService`).
- Local persistence with `shared_preferences` (session/tokens), SQLite-backed
  caches for chat history and encrypted conversations (`chat_local_db.dart`,
  `encrypted_chat_db.dart`), and a chat cache store.
- Realtime chat over a WebSocket (`RealtimeService` against `GET /api/v1/ws`).

## Running

```bash
flutter pub get
flutter run
```

The app uses whatever base URL you configure in the settings screen; the
default points at `http://127.0.0.1:8080`. The server must be running with the
gateway on port 8080 (see the server repo).

### Analyze / format

```bash
flutter analyze --no-pub
dart format lib test
```

`flutter analyze` alone can hang on dependency resolution behind the CN
mirror; `--no-pub` is the reliable invocation.

## Project layout

```
lib/
  main.dart                 App entry, providers, localization setup
  core/
    theme/app_theme.dart    Light/dark ThemeData (seed color + card style)
    widgets/                Shared dialogs and helpers (pin, error, markdown)
    services/               Settings, log, capability discovery
  data/
    models/                 User, Post, PostReply, Conversation, ChatMember,
                            ChatMessage, Membership, Wallet, Attachment, ...
    services/               ApiService (all HTTP), AuthService (tokens/session),
                            RealtimeService (WebSocket), chat caches
  pages/
    account/                Profile, account hub, wallet, membership, name
                            style, favorites, my posts, follow lists, exp
    auth/                   Login / registration
    chat/                   Conversation list, chat room, groups, consent
    posts/                  Feed, post detail, create/edit
  widgets/                  PostCard, ReplyTile, VerifiedName, attachment &
                            markdown renderers, reaction bar
```

## Auth & session

- Tokens (access + rotating refresh) come from OIDC or password login.
- `AuthService` owns the session: it persists tokens, auto-refreshes before
  expiry, and holds the cached `User`.
- `ApiService` throws `ApiException(statusCode, message)`; UI surfaces it via
  `showApiErrorDialog`.
- Login may arrive through a custom URI scheme (`openfield://oauth/callback`),
  handled by the OS URI handler.

## Feature overview

- **Posts**: feed with public/friends-only visibility, rich text/markdown,
  attachments, reactions, favorites, replies (nested), and author navigation.
  Authors can pin their own posts (pin/unpin in the context menu); pinned
  posts carry a badge and float to the top of the profile. Posts can be
  published into 贴吧-style **camps** (see below).
- **Camps**: a camp directory (search, mine/all toggle) reachable from the
  feed app bar. Camps support visibility (hidden camps are member-only) and a
  direct-join switch; camp posts live outside the global feed and the composer
  scopes new posts to the camp. Creation is quota-limited (100 per user,
  boosted by membership).
- **Chat**: consent-based private chats and groups, E2E-encrypted
  conversations, @mentions, quote replies, message forwarding, read receipts,
  typing indicators and offline message caches. Groups gain **announcements**
  (manager-published), a shared **to-do checklist**, and a **group files**
  view over the attachments shared in the conversation.
- **Group quotas**: creating groups is limited to 1000 owned groups (joined
  groups don't count) with a +25%-per-membership-level bonus.
- **Images**: uploads produce a 512px thumbnail and a 1440px preview; lists
  and the viewer load the preview first and fetch the original only through
  the viewer's "load original" toggle.
- **QR login & share codes**: the signing-in device shows a 5-minute QR on
  its login screen; already-signed-in devices scan and approve. Personal and
  group QR codes (`openfield://user/<id>`, `openfield://group/<id>`) open
  profiles or offer to join a group when scanned.
- **App announcements**: the latest server notice shows in a startup dialog
  with a per-notice "don't show again" and a history page; permission holders
  can publish/retire notices from the app.
- **Wallet**: balance in cents, transaction history, transfers with a payment
  PIN dialog.
- **Membership**: tier catalog and purchase (paid with wallet coins + PIN),
  exp-multiplier display, storage-bonus and name-perk chips.
- **Name styling**: custom display-name color reserved to members (Lv.1 preset
  palette, Lv.2+ any hex, Lv.3 gradients, Lv.4 animated gradient) edited in
  `NameStylePage`; rendered everywhere via `VerifiedName`, which also shows the
  membership tier badge and the verification badge.
- **Experience**: level derived from total exp (geometric growth, max level
  200), daily sign-in calendar with make-up days, one-time tasks and an exp
  history timeline.
- **Profile**: verification badge/note, follow/friends, banner and avatar
  uploads, storage usage.

## Localization

Strings are in `assets/translations/{zh,en}.json`. Keys are kept sorted
alphabetically in both files. Membership tier names (薄雾/篝火/明月/孤星) and
level-tier names are defined alongside their UI (see `user.dart` and
`membership.dart`) and rendered untranslated by design.

## Server compatibility

The client adapts to server capability flags (`GET /api/v1/capabilities`) and
tolerates missing/string-typed JSON fields (`_asInt` / `_asDate` helpers) so a
schema change never crashes the app. See the server repo's `docs/features.md`
for the backend feature guide.