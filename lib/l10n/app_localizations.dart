import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OpenField'**
  String get appTitle;

  /// No description provided for @posts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @loginWithOIDC.
  ///
  /// In en, this message translates to:
  /// **'Login with OIDC'**
  String get loginWithOIDC;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @createPost.
  ///
  /// In en, this message translates to:
  /// **'Create Post'**
  String get createPost;

  /// No description provided for @postContent.
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get postContent;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noPosts.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get noPosts;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get loadFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deletePostConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this post?'**
  String get deletePostConfirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @systemMode.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get systemMode;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @openSource.
  ///
  /// In en, this message translates to:
  /// **'Open Source'**
  String get openSource;

  /// No description provided for @loginWithPassword.
  ///
  /// In en, this message translates to:
  /// **'Login with Password'**
  String get loginWithPassword;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @completeRegistration.
  ///
  /// In en, this message translates to:
  /// **'Complete Registration'**
  String get completeRegistration;

  /// No description provided for @registerHint.
  ///
  /// In en, this message translates to:
  /// **'Please set your username and nickname to continue'**
  String get registerHint;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @setNickname.
  ///
  /// In en, this message translates to:
  /// **'Set Nickname'**
  String get setNickname;

  /// No description provided for @setAvatar.
  ///
  /// In en, this message translates to:
  /// **'Set Avatar'**
  String get setAvatar;

  /// No description provided for @setBanner.
  ///
  /// In en, this message translates to:
  /// **'Set Banner'**
  String get setBanner;

  /// No description provided for @banner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get banner;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @normalUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get normalUser;

  /// No description provided for @addImages.
  ///
  /// In en, this message translates to:
  /// **'Add Images'**
  String get addImages;

  /// No description provided for @post.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get post;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploading;

  /// No description provided for @usernameTaken.
  ///
  /// In en, this message translates to:
  /// **'Username already taken'**
  String get usernameTaken;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @registrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get registrationFailed;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @localAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Admin-created accounts sign in here. Self-registration is not available.'**
  String get localAccountHint;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSaved;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @discardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get discardDraft;

  /// No description provided for @loadDraft.
  ///
  /// In en, this message translates to:
  /// **'Continue editing draft'**
  String get loadDraft;

  /// No description provided for @noDraft.
  ///
  /// In en, this message translates to:
  /// **'No draft'**
  String get noDraft;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editPost.
  ///
  /// In en, this message translates to:
  /// **'Edit Post'**
  String get editPost;

  /// No description provided for @myAttachments.
  ///
  /// In en, this message translates to:
  /// **'My Attachments'**
  String get myAttachments;

  /// No description provided for @manageAttachmentsHint.
  ///
  /// In en, this message translates to:
  /// **'Manage your uploaded files'**
  String get manageAttachmentsHint;

  /// No description provided for @deleteAttachmentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this attachment?'**
  String get deleteAttachmentConfirm;

  /// No description provided for @noAttachments.
  ///
  /// In en, this message translates to:
  /// **'No attachments yet'**
  String get noAttachments;

  /// No description provided for @appSettings.
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettings;

  /// No description provided for @accountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get accountSettings;

  /// No description provided for @chatRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get chatRequests;

  /// No description provided for @chatRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get chatRequestsEmpty;

  /// No description provided for @chatStartPrivate.
  ///
  /// In en, this message translates to:
  /// **'Start Private Chat'**
  String get chatStartPrivate;

  /// No description provided for @chatNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get chatNewGroup;

  /// No description provided for @chatGroupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get chatGroupCreate;

  /// No description provided for @chatEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get chatEmpty;

  /// No description provided for @chatRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Chat request sent'**
  String get chatRequestSent;

  /// No description provided for @chatInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent'**
  String get chatInviteSent;

  /// No description provided for @chatRequestAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get chatRequestAccept;

  /// No description provided for @chatRequestDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get chatRequestDecline;

  /// No description provided for @chatRequestTypePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private chat request'**
  String get chatRequestTypePrivate;

  /// No description provided for @chatRequestTypeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group invite'**
  String get chatRequestTypeGroup;

  /// No description provided for @chatQuoteReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get chatQuoteReply;

  /// No description provided for @chatGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get chatGroupMembers;

  /// No description provided for @chatGroupInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get chatGroupInvite;

  /// No description provided for @chatGroupNickname.
  ///
  /// In en, this message translates to:
  /// **'Group Nickname'**
  String get chatGroupNickname;

  /// No description provided for @chatGroupLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave Group'**
  String get chatGroupLeave;

  /// No description provided for @chatGroupLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave this group?'**
  String get chatGroupLeaveConfirm;

  /// No description provided for @chatNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get chatNote;

  /// No description provided for @chatEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get chatEdited;

  /// No description provided for @chatLoadEarlier.
  ///
  /// In en, this message translates to:
  /// **'Load earlier'**
  String get chatLoadEarlier;

  /// No description provided for @chatReplying.
  ///
  /// In en, this message translates to:
  /// **'Replying...'**
  String get chatReplying;

  /// No description provided for @chatOwnerRole.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get chatOwnerRole;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @groupTitle.
  ///
  /// In en, this message translates to:
  /// **'Group title'**
  String get groupTitle;

  /// No description provided for @groupTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a group title'**
  String get groupTitleHint;

  /// No description provided for @chatSearchUsers.
  ///
  /// In en, this message translates to:
  /// **'Search Users'**
  String get chatSearchUsers;

  /// No description provided for @chatSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by username or nickname'**
  String get chatSearchHint;

  /// No description provided for @chatNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get chatNoUsers;

  /// No description provided for @myPermissions.
  ///
  /// In en, this message translates to:
  /// **'My Permissions'**
  String get myPermissions;

  /// No description provided for @myPermissionsHint.
  ///
  /// In en, this message translates to:
  /// **'View your groups and permissions'**
  String get myPermissionsHint;

  /// No description provided for @myGroups.
  ///
  /// In en, this message translates to:
  /// **'My Groups'**
  String get myGroups;

  /// No description provided for @noGroups.
  ///
  /// In en, this message translates to:
  /// **'You are not in any group'**
  String get noGroups;

  /// No description provided for @noPermissions.
  ///
  /// In en, this message translates to:
  /// **'No permissions granted'**
  String get noPermissions;

  /// No description provided for @developerMode.
  ///
  /// In en, this message translates to:
  /// **'Developer Mode'**
  String get developerMode;

  /// No description provided for @developerModeHint.
  ///
  /// In en, this message translates to:
  /// **'Record logs for debugging'**
  String get developerModeHint;

  /// No description provided for @logViewer.
  ///
  /// In en, this message translates to:
  /// **'Log Viewer'**
  String get logViewer;

  /// No description provided for @logViewerHint.
  ///
  /// In en, this message translates to:
  /// **'Open the floating log viewer'**
  String get logViewerHint;

  /// No description provided for @replies.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get replies;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyContent.
  ///
  /// In en, this message translates to:
  /// **'Write a reply...'**
  String get replyContent;

  /// No description provided for @replyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No replies yet'**
  String get replyEmpty;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @oauthBinding.
  ///
  /// In en, this message translates to:
  /// **'OAuth Account'**
  String get oauthBinding;

  /// No description provided for @oauthNotBound.
  ///
  /// In en, this message translates to:
  /// **'Not bound'**
  String get oauthNotBound;

  /// No description provided for @oauthBound.
  ///
  /// In en, this message translates to:
  /// **'Bound'**
  String get oauthBound;

  /// No description provided for @bindOAuth.
  ///
  /// In en, this message translates to:
  /// **'Bind'**
  String get bindOAuth;

  /// No description provided for @oauthUnbindAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'OAuth accounts can only be unbound in the admin panel.'**
  String get oauthUnbindAdminOnly;

  /// No description provided for @oauthBindSuccess.
  ///
  /// In en, this message translates to:
  /// **'OAuth account bound successfully'**
  String get oauthBindSuccess;

  /// No description provided for @oauthBindFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to bind OAuth account'**
  String get oauthBindFailed;

  /// No description provided for @myPosts.
  ///
  /// In en, this message translates to:
  /// **'My Posts'**
  String get myPosts;

  /// No description provided for @myPostsHint.
  ///
  /// In en, this message translates to:
  /// **'View and manage your posts'**
  String get myPostsHint;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @bioHint.
  ///
  /// In en, this message translates to:
  /// **'Tell others about yourself'**
  String get bioHint;

  /// No description provided for @serverHost.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverHost;

  /// No description provided for @serverHostHint.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverHostHint;

  /// No description provided for @backgroundImage.
  ///
  /// In en, this message translates to:
  /// **'Background Image'**
  String get backgroundImage;

  /// No description provided for @backgroundImageHint.
  ///
  /// In en, this message translates to:
  /// **'Set a background image for this device'**
  String get backgroundImageHint;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @verifiedAccount.
  ///
  /// In en, this message translates to:
  /// **'Verified account'**
  String get verifiedAccount;

  /// No description provided for @advancedLogin.
  ///
  /// In en, this message translates to:
  /// **'Advanced Login'**
  String get advancedLogin;

  /// No description provided for @advancedLoginHint.
  ///
  /// In en, this message translates to:
  /// **'For special cases'**
  String get advancedLoginHint;

  /// No description provided for @tokenLogin.
  ///
  /// In en, this message translates to:
  /// **'Token Login'**
  String get tokenLogin;

  /// No description provided for @tokenLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the token copied from the browser login page'**
  String get tokenLoginHint;

  /// No description provided for @tokenPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste access token'**
  String get tokenPlaceholder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
