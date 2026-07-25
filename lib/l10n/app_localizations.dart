import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title shown in the OS task switcher / window title.
  ///
  /// In en, this message translates to:
  /// **'Slopcafe Operator'**
  String get appTitle;

  /// Bottom tab bar label for the Library ("The Cafe") tab.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// Bottom tab bar label for the Search tab.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// Bottom tab bar label for the Operate ("The Pass") tab.
  ///
  /// In en, this message translates to:
  /// **'Operate'**
  String get tabOperate;

  /// Placeholder shown in lists/cards when a document has no title.
  ///
  /// In en, this message translates to:
  /// **'[Untitled]'**
  String get untitled;

  /// Plain (no brackets) untitled fallback used inside toasts and sheet titles.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitledPlain;

  /// Shown in a document row when the document carries no tags.
  ///
  /// In en, this message translates to:
  /// **'untagged'**
  String get untagged;

  /// Compact version marker, e.g. v3. The {version} value may be a number or an em dash when unknown.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String versionLabel(String version);

  /// Section-header trailing action that opens the full Collections list.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get actionAll;

  /// Section-header trailing action that opens the full document list.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get actionSeeAll;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get working;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @deleteClient.
  ///
  /// In en, this message translates to:
  /// **'Delete client'**
  String get deleteClient;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// Library header greeting, e.g. "Good morning, Operator".
  ///
  /// In en, this message translates to:
  /// **'{greeting}, Operator'**
  String libraryGreeting(String greeting);

  /// Library tab display title (the home screen / "The Café").
  ///
  /// In en, this message translates to:
  /// **'The Café'**
  String get theCafe;

  /// No description provided for @statusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get statusLive;

  /// No description provided for @statusTokenRejected.
  ///
  /// In en, this message translates to:
  /// **'Token rejected'**
  String get statusTokenRejected;

  /// No description provided for @statusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get statusDisconnected;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get statusConnecting;

  /// Connection-status pill label when no connection has been attempted yet.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get statusConnect;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached documents.'**
  String get offlineBanner;

  /// Caption under the live-document count ticker on the Library screen.
  ///
  /// In en, this message translates to:
  /// **'on the menu'**
  String get tickerOnMenu;

  /// Caption under the agent-count ticker (café metaphor for active agents).
  ///
  /// In en, this message translates to:
  /// **'cooks on the line'**
  String get tickerCooks;

  /// Caption under the public-document count ticker.
  ///
  /// In en, this message translates to:
  /// **'public plates'**
  String get tickerPublicPlates;

  /// No description provided for @collectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get collectionsTitle;

  /// Section/screen title for the newest documents (café metaphor for "recently published").
  ///
  /// In en, this message translates to:
  /// **'Recently plated'**
  String get recentlyPlatedTitle;

  /// No description provided for @mostRecentFirst.
  ///
  /// In en, this message translates to:
  /// **'Most recent first'**
  String get mostRecentFirst;

  /// Empty state on the Library when no documents exist.
  ///
  /// In en, this message translates to:
  /// **'Nothing plated yet.'**
  String get nothingPlatedYet;

  /// Empty state on a tag collection / document list.
  ///
  /// In en, this message translates to:
  /// **'Nothing plated here yet.'**
  String get nothingPlatedHere;

  /// No description provided for @noCollectionsYet.
  ///
  /// In en, this message translates to:
  /// **'No collections yet.'**
  String get noCollectionsYet;

  /// Eyebrow above the Collections screen title.
  ///
  /// In en, this message translates to:
  /// **'Browse by tag'**
  String get browseByTag;

  /// Eyebrow shown above a single tag's document-list screen.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get collectionEyebrow;

  /// Count of documents, e.g. "3 documents".
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document} other{{count} documents}}'**
  String documentCount(int count);

  /// Count of tag collections, e.g. "5 collections".
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 collection} other{{count} collections}}'**
  String collectionCount(int count);

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// Placeholder text inside the search input field.
  ///
  /// In en, this message translates to:
  /// **'Titles, body, tags, slugs…'**
  String get searchHint;

  /// Uppercase label above the search suggestion chips.
  ///
  /// In en, this message translates to:
  /// **'TRY SEARCHING'**
  String get trySearching;

  /// Comma-separated seed search suggestions shown as chips when the field is empty. Edit/reorder freely; whitespace around commas is trimmed.
  ///
  /// In en, this message translates to:
  /// **'sanitizer,recipe,oauth,espresso,revoke'**
  String get searchSuggestionSeeds;

  /// Header above search results, e.g. "12 results · ranked by relevance".
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result · ranked by relevance} other{{count} results · ranked by relevance}}'**
  String searchResultCount(int count);

  /// Empty-results headline when a search yields nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String searchNoMatch(String query);

  /// No description provided for @searchNoMatchHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different keyword, tag, or slug.'**
  String get searchNoMatchHint;

  /// No description provided for @searchError.
  ///
  /// In en, this message translates to:
  /// **'Search hit a snag.'**
  String get searchError;

  /// Shown when search results hit the backend's 50-result ceiling.
  ///
  /// In en, this message translates to:
  /// **'Showing the top 50 plates. Refine your search to find the rest.'**
  String get searchCeilingHint;

  /// Search-mode selector segment: combined keyword + semantic (concept) ranking. The default.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get searchModeHybrid;

  /// Search-mode selector segment: exact keyword (full-text) matching only.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get searchModeKeyword;

  /// Search-mode selector segment: concept (vector) matching only.
  ///
  /// In en, this message translates to:
  /// **'Semantic'**
  String get searchModeSemantic;

  /// Title of the semantic-search vector-index management entry and sheet.
  ///
  /// In en, this message translates to:
  /// **'Search index'**
  String get searchIndex;

  /// Subtitle on the Operate > Documents 'Search index' entry row.
  ///
  /// In en, this message translates to:
  /// **'Semantic search vectors'**
  String get searchIndexSubtitle;

  /// Eyebrow above the search-index (vector backfill) sheet title.
  ///
  /// In en, this message translates to:
  /// **'Semantic search'**
  String get semanticSearch;

  /// Intro paragraph in the search-index sheet explaining why vectors are backfilled.
  ///
  /// In en, this message translates to:
  /// **'Semantic search matches documents by concept using vector embeddings. Documents added before search was enabled — or any that slipped through — need embedding before they appear in semantic and hybrid results.'**
  String get backfillBody;

  /// Title for the cheap, incremental backfill option (embeds only un-vectored docs).
  ///
  /// In en, this message translates to:
  /// **'Index new documents'**
  String get indexNewTitle;

  /// Body for the 'Index new documents' backfill option card.
  ///
  /// In en, this message translates to:
  /// **'Embed only documents that don\'t have vectors yet. Fast and inexpensive.'**
  String get indexNewOptionBody;

  /// Confirmation body for the index-new (missing) backfill mode.
  ///
  /// In en, this message translates to:
  /// **'Embed every document that\'s missing search vectors. This is incremental and cheap — only un-indexed documents are touched.'**
  String get indexNewConfirmBody;

  /// Confirm button for the index-new backfill mode.
  ///
  /// In en, this message translates to:
  /// **'Index new'**
  String get indexNewCta;

  /// Title for the expensive backfill option (re-embeds the whole corpus).
  ///
  /// In en, this message translates to:
  /// **'Rebuild entire index'**
  String get rebuildIndexTitle;

  /// Body for the 'Rebuild entire index' backfill option card.
  ///
  /// In en, this message translates to:
  /// **'Re-embed every document from scratch. Slower and more costly — use after an embedding-model change or to repair the index.'**
  String get rebuildIndexOptionBody;

  /// Confirmation body for the rebuild backfill mode; stresses the cost.
  ///
  /// In en, this message translates to:
  /// **'This re-embeds every live document from scratch — significantly more compute and real cost than indexing only new documents. Run it only after a model or chunk-size change, or to repair a stale index.'**
  String get rebuildIndexConfirmBody;

  /// Confirm button for the rebuild backfill mode.
  ///
  /// In en, this message translates to:
  /// **'Rebuild index'**
  String get rebuildIndexCta;

  /// Progress label shown while the index-new backfill runs.
  ///
  /// In en, this message translates to:
  /// **'Indexing new documents…'**
  String get indexingNew;

  /// Progress label shown while the rebuild backfill runs.
  ///
  /// In en, this message translates to:
  /// **'Rebuilding the entire index…'**
  String get rebuildingIndex;

  /// Success toast after a backfill run that embedded at least one document.
  ///
  /// In en, this message translates to:
  /// **'Search index updated · {embedded} embedded, {vectors} vectors, {skipped} skipped'**
  String backfillDone(int embedded, int vectors, int skipped);

  /// Toast when a backfill run found no documents needing embedding.
  ///
  /// In en, this message translates to:
  /// **'Search index already up to date — nothing to embed.'**
  String get backfillUpToDate;

  /// Warning toast when chunk vectors are far fewer than docs embedded (transient failure).
  ///
  /// In en, this message translates to:
  /// **'Embedded {embedded} docs but only {vectors} vectors landed — some embeds failed. Try again.'**
  String backfillPartial(int embedded, int vectors);

  /// Error toast when a backfill run throws.
  ///
  /// In en, this message translates to:
  /// **'Backfill failed: {error}'**
  String backfillFailed(String error);

  /// Eyebrow above the Operate screen title (café metaphor).
  ///
  /// In en, this message translates to:
  /// **'Back of house'**
  String get backOfHouse;

  /// Operate screen / Settings intro title (café metaphor for the operator back office).
  ///
  /// In en, this message translates to:
  /// **'The Pass'**
  String get thePass;

  /// No description provided for @liveDocuments.
  ///
  /// In en, this message translates to:
  /// **'Live documents'**
  String get liveDocuments;

  /// Sub-label under the live-documents stat, e.g. "4 public".
  ///
  /// In en, this message translates to:
  /// **'{count} public'**
  String publicCountSub(int count);

  /// No description provided for @activeAgents.
  ///
  /// In en, this message translates to:
  /// **'Active agents'**
  String get activeAgents;

  /// Sub-label under the active-agents stat, e.g. "of 12".
  ///
  /// In en, this message translates to:
  /// **'of {count}'**
  String ofCountSub(int count);

  /// No description provided for @activeKeys.
  ///
  /// In en, this message translates to:
  /// **'Active keys'**
  String get activeKeys;

  /// Sub-label under the active-keys stat, e.g. "30 minted".
  ///
  /// In en, this message translates to:
  /// **'{count} minted'**
  String mintedSub(int count);

  /// No description provided for @sanitizer.
  ///
  /// In en, this message translates to:
  /// **'Sanitizer'**
  String get sanitizer;

  /// Sub-label under the Sanitizer stat when the backend health probe succeeds.
  ///
  /// In en, this message translates to:
  /// **'all green'**
  String get allGreen;

  /// Sub-label under the Sanitizer stat when its version is unknown.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get unavailable;

  /// No description provided for @r2Storage.
  ///
  /// In en, this message translates to:
  /// **'R2 storage'**
  String get r2Storage;

  /// Storage bar trailing label when only the cap is known, e.g. "cap 5.00 MB".
  ///
  /// In en, this message translates to:
  /// **'cap {cap}'**
  String storageCapLabel(String cap);

  /// No description provided for @usageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Usage figure unavailable.'**
  String get usageUnavailable;

  /// Operate segmented-control option for the agent/kitchen section.
  ///
  /// In en, this message translates to:
  /// **'The Kitchen'**
  String get segKitchen;

  /// Operate segmented-control option for the admin document list.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get segDocuments;

  /// Count of agents shown above the Kitchen list.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 agent} other{{count} agents}}'**
  String agentCount(int count);

  /// No description provided for @newAgent.
  ///
  /// In en, this message translates to:
  /// **'New agent'**
  String get newAgent;

  /// No description provided for @unboundOAuthClients.
  ///
  /// In en, this message translates to:
  /// **'Unbound OAuth clients'**
  String get unboundOAuthClients;

  /// No description provided for @unboundOAuthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Global clients not tied to any agent profile.'**
  String get unboundOAuthSubtitle;

  /// No description provided for @couldNotLoadFleet.
  ///
  /// In en, this message translates to:
  /// **'Could not load the fleet.'**
  String get couldNotLoadFleet;

  /// No description provided for @noAgentsYet.
  ///
  /// In en, this message translates to:
  /// **'No agents on the line yet. Hire one to begin.'**
  String get noAgentsYet;

  /// No description provided for @allDocuments.
  ///
  /// In en, this message translates to:
  /// **'All documents'**
  String get allDocuments;

  /// No description provided for @includeRevoked.
  ///
  /// In en, this message translates to:
  /// **'Include revoked'**
  String get includeRevoked;

  /// No description provided for @couldNotLoadDocuments.
  ///
  /// In en, this message translates to:
  /// **'Could not load documents.'**
  String get couldNotLoadDocuments;

  /// No description provided for @noDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents to show.'**
  String get noDocuments;

  /// Lowercase "revoked" status shown under a document title in admin rows.
  ///
  /// In en, this message translates to:
  /// **'revoked'**
  String get revokedLower;

  /// Title-case Revoked badge on admin document rows.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get revokedBadge;

  /// Uppercase REVOKED pill on cards and the reader.
  ///
  /// In en, this message translates to:
  /// **'REVOKED'**
  String get revokedUpper;

  /// No description provided for @documentActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Document actions'**
  String get documentActionsTooltip;

  /// No description provided for @agentHiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent hired'**
  String get agentHiredTitle;

  /// No description provided for @agentIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent ID'**
  String get agentIdLabel;

  /// No description provided for @plaintextBearerKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Plaintext bearer key'**
  String get plaintextBearerKeyLabel;

  /// No description provided for @hireAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Hire an agent'**
  String get hireAgentTitle;

  /// No description provided for @newProfile.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get newProfile;

  /// No description provided for @hireAgentBody.
  ///
  /// In en, this message translates to:
  /// **'Creates a logical agent profile and mints its initial bearer key. The key is shown only once.'**
  String get hireAgentBody;

  /// No description provided for @agentNameLabel.
  ///
  /// In en, this message translates to:
  /// **'AGENT NAME'**
  String get agentNameLabel;

  /// No description provided for @agentNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Claude Writer'**
  String get agentNameHint;

  /// No description provided for @hiring.
  ///
  /// In en, this message translates to:
  /// **'Hiring…'**
  String get hiring;

  /// No description provided for @hireAgent.
  ///
  /// In en, this message translates to:
  /// **'Hire agent'**
  String get hireAgent;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name.'**
  String get nameRequired;

  /// No description provided for @nameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Name must be 200 characters or less.'**
  String get nameTooLong;

  /// No description provided for @failedHireAgent.
  ///
  /// In en, this message translates to:
  /// **'Failed to hire agent: {error}'**
  String failedHireAgent(String error);

  /// No description provided for @oauthClientCreated.
  ///
  /// In en, this message translates to:
  /// **'OAuth client created'**
  String get oauthClientCreated;

  /// No description provided for @clientIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get clientIdLabel;

  /// No description provided for @clientSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Client secret (one-shot)'**
  String get clientSecretLabel;

  /// No description provided for @mcpUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'MCP connection URL'**
  String get mcpUrlLabel;

  /// No description provided for @globalConnections.
  ///
  /// In en, this message translates to:
  /// **'Global connections'**
  String get globalConnections;

  /// No description provided for @unboundClientsBody.
  ///
  /// In en, this message translates to:
  /// **'Unbound clients are not tied to any single agent profile. They let operators authenticate valid agent flows dynamically.'**
  String get unboundClientsBody;

  /// No description provided for @mintUnboundClient.
  ///
  /// In en, this message translates to:
  /// **'Mint unbound client'**
  String get mintUnboundClient;

  /// No description provided for @mintedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'MINTED ON THIS DEVICE'**
  String get mintedOnThisDevice;

  /// No description provided for @noUnboundClients.
  ///
  /// In en, this message translates to:
  /// **'No unbound clients recorded on this device.'**
  String get noUnboundClients;

  /// No description provided for @failedMintUnbound.
  ///
  /// In en, this message translates to:
  /// **'Failed to mint unbound client: {error}'**
  String failedMintUnbound(String error);

  /// No description provided for @deleteUnboundTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete unbound client'**
  String get deleteUnboundTitle;

  /// No description provided for @deleteUnboundBody.
  ///
  /// In en, this message translates to:
  /// **'Delete unbound OAuth client \"{clientId}\"? This instantly revokes all live sessions and tokens issued under it.'**
  String deleteUnboundBody(String clientId);

  /// No description provided for @unboundClientDeleted.
  ///
  /// In en, this message translates to:
  /// **'Unbound client deleted.'**
  String get unboundClientDeleted;

  /// No description provided for @failedDeleteClient.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete client: {error}'**
  String failedDeleteClient(String error);

  /// No description provided for @agentProfile.
  ///
  /// In en, this message translates to:
  /// **'Agent profile'**
  String get agentProfile;

  /// Compact "N docs" pill on the agent sheet.
  ///
  /// In en, this message translates to:
  /// **'{count} docs'**
  String docsCountShort(int count);

  /// No description provided for @mintKey.
  ///
  /// In en, this message translates to:
  /// **'Mint key'**
  String get mintKey;

  /// No description provided for @oauthClientButton.
  ///
  /// In en, this message translates to:
  /// **'OAuth client'**
  String get oauthClientButton;

  /// No description provided for @oauthClientRegistered.
  ///
  /// In en, this message translates to:
  /// **'OAuth client registered'**
  String get oauthClientRegistered;

  /// No description provided for @deleteOAuthClientButton.
  ///
  /// In en, this message translates to:
  /// **'Delete OAuth client'**
  String get deleteOAuthClientButton;

  /// No description provided for @apiKeysLabel.
  ///
  /// In en, this message translates to:
  /// **'API KEYS'**
  String get apiKeysLabel;

  /// No description provided for @noKeys.
  ///
  /// In en, this message translates to:
  /// **'No keys registered. Mint one to authorize clients.'**
  String get noKeys;

  /// Header above the inert-keys audit list (keys that no longer authenticate — revoked or expired).
  ///
  /// In en, this message translates to:
  /// **'INACTIVE ({count})'**
  String inactiveAudit(int count);

  /// Uppercase EXPIRED pill on a lapsed (but un-revoked) agent key row.
  ///
  /// In en, this message translates to:
  /// **'EXPIRED'**
  String get expiredUpper;

  /// No description provided for @errorFetchingKeys.
  ///
  /// In en, this message translates to:
  /// **'Error fetching keys: {error}'**
  String errorFetchingKeys(String error);

  /// No description provided for @bearerKeyMinted.
  ///
  /// In en, this message translates to:
  /// **'Bearer key minted'**
  String get bearerKeyMinted;

  /// No description provided for @keyPlaintextLabel.
  ///
  /// In en, this message translates to:
  /// **'Key plaintext'**
  String get keyPlaintextLabel;

  /// No description provided for @failedMintKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to mint key: {error}'**
  String failedMintKey(String error);

  /// No description provided for @revokeKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke key'**
  String get revokeKeyTitle;

  /// No description provided for @revokeKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Revoke key \"{keyPrefix}\"? This is irreversible — the worker using it is immediately locked out.'**
  String revokeKeyBody(String keyPrefix);

  /// No description provided for @keyRevoked.
  ///
  /// In en, this message translates to:
  /// **'Key {keyPrefix} revoked.'**
  String keyRevoked(String keyPrefix);

  /// No description provided for @failedRevokeKey.
  ///
  /// In en, this message translates to:
  /// **'Failed to revoke key: {error}'**
  String failedRevokeKey(String error);

  /// No description provided for @oauthAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'OAuth client already exists for this agent.'**
  String get oauthAlreadyExists;

  /// No description provided for @failedMintOAuth.
  ///
  /// In en, this message translates to:
  /// **'Failed to mint OAuth client: {error}'**
  String failedMintOAuth(String error);

  /// No description provided for @deleteOAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete OAuth client'**
  String get deleteOAuthTitle;

  /// No description provided for @deleteOAuthBody.
  ///
  /// In en, this message translates to:
  /// **'Delete OAuth client \"{clientId}\"? This instantly revokes every live access and refresh token issued to Claude or external MCP hosts.'**
  String deleteOAuthBody(String clientId);

  /// No description provided for @oauthClientDeleted.
  ///
  /// In en, this message translates to:
  /// **'OAuth client deleted.'**
  String get oauthClientDeleted;

  /// No description provided for @failedDeleteOAuth.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete OAuth client: {error}'**
  String failedDeleteOAuth(String error);

  /// No description provided for @killAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Kill agent profile'**
  String get killAgentTitle;

  /// Bold lead-in of the kill-agent confirmation (trailing space is intentional).
  ///
  /// In en, this message translates to:
  /// **'Cascading destruction. '**
  String get cascadingDestruction;

  /// No description provided for @killAgentBody.
  ///
  /// In en, this message translates to:
  /// **'This instantly revokes all bearer keys and deletes the agent\'s OAuth client.'**
  String get killAgentBody;

  /// No description provided for @killProfile.
  ///
  /// In en, this message translates to:
  /// **'Kill profile'**
  String get killProfile;

  /// No description provided for @agentKilled.
  ///
  /// In en, this message translates to:
  /// **'Agent killed. Revoked {keys} key(s), deleted {clients} client(s).'**
  String agentKilled(Object keys, Object clients);

  /// No description provided for @failedKillAgent.
  ///
  /// In en, this message translates to:
  /// **'Failed to kill agent: {error}'**
  String failedKillAgent(String error);

  /// Sub-label on a revoked key row, e.g. "Revoked Jan 4, 2026".
  ///
  /// In en, this message translates to:
  /// **'Revoked {date}'**
  String keyRevokedOn(String date);

  /// Sub-label on an active key row, e.g. "Minted Jan 4, 2026".
  ///
  /// In en, this message translates to:
  /// **'Minted {date}'**
  String keyMintedOn(String date);

  /// Sub-label on a lapsed (un-revoked) key row, e.g. "Expired Jan 4, 2026".
  ///
  /// In en, this message translates to:
  /// **'Expired {date}'**
  String keyExpiredOn(String date);

  /// Sub-label on an active short-lived key that has a future expiry, e.g. "Expires Jan 4, 2026".
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String keyExpiresOn(String date);

  /// No description provided for @makePublic.
  ///
  /// In en, this message translates to:
  /// **'Make public'**
  String get makePublic;

  /// No description provided for @makePrivate.
  ///
  /// In en, this message translates to:
  /// **'Make private'**
  String get makePrivate;

  /// No description provided for @makePublicBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone with the link will be able to read this document.'**
  String get makePublicBody;

  /// Make-private confirmation body in the Operate document-actions sheet.
  ///
  /// In en, this message translates to:
  /// **'Only authorized operators will be able to read this document.'**
  String get makePrivateBody;

  /// Make-private confirmation body in the Reader.
  ///
  /// In en, this message translates to:
  /// **'Only operators will be able to read this document.'**
  String get makePrivateBodyReader;

  /// Toast after toggling visibility, e.g. "Visibility set to PUBLIC."
  ///
  /// In en, this message translates to:
  /// **'Visibility set to {visibility}.'**
  String visibilitySet(String visibility);

  /// No description provided for @failedUpdateVisibility.
  ///
  /// In en, this message translates to:
  /// **'Failed to update visibility: {error}'**
  String failedUpdateVisibility(String error);

  /// No description provided for @noSlugUrl.
  ///
  /// In en, this message translates to:
  /// **'No slug URL available.'**
  String get noSlugUrl;

  /// No description provided for @slugUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'Slug URL copied.'**
  String get slugUrlCopied;

  /// No description provided for @editSlugTags.
  ///
  /// In en, this message translates to:
  /// **'Edit slug & tags'**
  String get editSlugTags;

  /// No description provided for @copySlugUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy slug URL'**
  String get copySlugUrl;

  /// No description provided for @documentActions.
  ///
  /// In en, this message translates to:
  /// **'Document actions'**
  String get documentActions;

  /// No description provided for @documentMetadata.
  ///
  /// In en, this message translates to:
  /// **'Document metadata'**
  String get documentMetadata;

  /// No description provided for @documentProperties.
  ///
  /// In en, this message translates to:
  /// **'Document properties'**
  String get documentProperties;

  /// No description provided for @slugLabel.
  ///
  /// In en, this message translates to:
  /// **'SLUG'**
  String get slugLabel;

  /// No description provided for @slugHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my-cool-document'**
  String get slugHint;

  /// No description provided for @slugRetiredNote.
  ///
  /// In en, this message translates to:
  /// **'Slugs are retired permanently when cleared or changed — the old slug then returns 410 Gone. Leave empty to clear.'**
  String get slugRetiredNote;

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'TAGS'**
  String get tagsLabel;

  /// No description provided for @tagsHint.
  ///
  /// In en, this message translates to:
  /// **'comma, separated, tags'**
  String get tagsHint;

  /// No description provided for @tagsHintReader.
  ///
  /// In en, this message translates to:
  /// **'e.g. guide, tutorial, reference'**
  String get tagsHintReader;

  /// No description provided for @separateTagsWithCommas.
  ///
  /// In en, this message translates to:
  /// **'Separate tags with commas.'**
  String get separateTagsWithCommas;

  /// No description provided for @slugTagsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Slug & tags updated.'**
  String get slugTagsUpdated;

  /// No description provided for @documentPropertiesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Document properties updated'**
  String get documentPropertiesUpdated;

  /// No description provided for @failedUpdate.
  ///
  /// In en, this message translates to:
  /// **'Failed to update: {error}'**
  String failedUpdate(String error);

  /// Uppercase DEPRECATED lifecycle pill on cards, hits, rows, and the reader.
  ///
  /// In en, this message translates to:
  /// **'DEPRECATED'**
  String get deprecatedUpper;

  /// No description provided for @markDeprecated.
  ///
  /// In en, this message translates to:
  /// **'Mark deprecated'**
  String get markDeprecated;

  /// No description provided for @markActive.
  ///
  /// In en, this message translates to:
  /// **'Mark active'**
  String get markActive;

  /// Explainer at the top of the deprecate sheet.
  ///
  /// In en, this message translates to:
  /// **'The document stays served and searchable, but is marked as no longer current and left out of context packs by default.'**
  String get markDeprecatedBody;

  /// Mark-active confirmation body.
  ///
  /// In en, this message translates to:
  /// **'The document will count as current again. Any superseded-by pointer is cleared.'**
  String get markActiveBody;

  /// No description provided for @supersededByLabel.
  ///
  /// In en, this message translates to:
  /// **'SUPERSEDED BY (OPTIONAL)'**
  String get supersededByLabel;

  /// No description provided for @supersededByHint.
  ///
  /// In en, this message translates to:
  /// **'Replacement document\'s public ID'**
  String get supersededByHint;

  /// No description provided for @supersededByNote.
  ///
  /// In en, this message translates to:
  /// **'Readers are pointed at the replacement but never auto-redirected. Leave empty if there is no successor.'**
  String get supersededByNote;

  /// Toast after changing lifecycle status, e.g. "Status set to DEPRECATED."
  ///
  /// In en, this message translates to:
  /// **'Status set to {status}.'**
  String statusSet(String status);

  /// No description provided for @failedUpdateStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed to update status: {error}'**
  String failedUpdateStatus(String error);

  /// Reader banner on a deprecated document with no superseded_by pointer.
  ///
  /// In en, this message translates to:
  /// **'This document is deprecated — treat it as no longer current.'**
  String get deprecatedBanner;

  /// Reader banner on a deprecated document that names a replacement.
  ///
  /// In en, this message translates to:
  /// **'Deprecated — a newer document supersedes this one.'**
  String get deprecatedBannerSuperseded;

  /// CTA on the reader deprecation banner that opens the superseded_by replacement.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openReplacement;

  /// Operate › Documents lifecycle filter segments (All / Active / Deprecated).
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statusFilterAll;

  /// No description provided for @statusFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusFilterActive;

  /// No description provided for @statusFilterDeprecated.
  ///
  /// In en, this message translates to:
  /// **'Deprecated'**
  String get statusFilterDeprecated;

  /// Operate › Documents CTA that opens the compose screen (POST /admin/documents).
  ///
  /// In en, this message translates to:
  /// **'Author a document'**
  String get authorDocument;

  /// Title of the operator authoring / Markdown composition screen.
  ///
  /// In en, this message translates to:
  /// **'Compose'**
  String get composeTitle;

  /// No description provided for @composeEyebrow.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get composeEyebrow;

  /// No description provided for @composeModeWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get composeModeWrite;

  /// No description provided for @composeModePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get composeModePreview;

  /// No description provided for @composeFormatMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get composeFormatMarkdown;

  /// No description provided for @composeFormatHtml.
  ///
  /// In en, this message translates to:
  /// **'HTML'**
  String get composeFormatHtml;

  /// No description provided for @composeBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Write your document here…'**
  String get composeBodyHint;

  /// Eyebrow over the placeholder compose preview pane (the swap-in seam for a Markdown renderer).
  ///
  /// In en, this message translates to:
  /// **'Preview · raw source'**
  String get composePreviewRaw;

  /// No description provided for @composePreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview yet.'**
  String get composePreviewEmpty;

  /// No description provided for @composeDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get composeDetails;

  /// No description provided for @composeTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'TITLE'**
  String get composeTitleLabel;

  /// No description provided for @composeTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — derived from the first heading if left blank'**
  String get composeTitleHint;

  /// No description provided for @composeDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION'**
  String get composeDescriptionLabel;

  /// No description provided for @composeDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional short summary'**
  String get composeDescriptionHint;

  /// No description provided for @composeSlugNote.
  ///
  /// In en, this message translates to:
  /// **'Optional — a unique URL slug. Leave blank to auto-assign.'**
  String get composeSlugNote;

  /// No description provided for @composeVisibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'VISIBILITY'**
  String get composeVisibilityLabel;

  /// No description provided for @composeVisibilityDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get composeVisibilityDefault;

  /// No description provided for @composeVisibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get composeVisibilityPublic;

  /// No description provided for @composeVisibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get composeVisibilityPrivate;

  /// No description provided for @composeVisibilityNote.
  ///
  /// In en, this message translates to:
  /// **'“Default” births the document at the deployment\'s configured visibility.'**
  String get composeVisibilityNote;

  /// No description provided for @composePublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get composePublish;

  /// No description provided for @composePublishing.
  ///
  /// In en, this message translates to:
  /// **'Publishing…'**
  String get composePublishing;

  /// No description provided for @composeContentRequired.
  ///
  /// In en, this message translates to:
  /// **'Write some content before publishing.'**
  String get composeContentRequired;

  /// Toast after authoring a new document.
  ///
  /// In en, this message translates to:
  /// **'Published as v{version}.'**
  String documentPublished(int version);

  /// Toast after authoring when the sanitizer stripped or flagged content.
  ///
  /// In en, this message translates to:
  /// **'Published v{version} — the sanitizer adjusted {count} item(s).'**
  String documentPublishedSanitized(int version, int count);

  /// No description provided for @failedPublish.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish: {error}'**
  String failedPublish(String error);

  /// No description provided for @revokeDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke document'**
  String get revokeDocumentTitle;

  /// No description provided for @revokePermanently.
  ///
  /// In en, this message translates to:
  /// **'Revoke permanently'**
  String get revokePermanently;

  /// The exact word the operator must type to confirm a document revoke.
  ///
  /// In en, this message translates to:
  /// **'REVOKE'**
  String get revokeConfirmWord;

  /// Revoke confirmation body in the Operate document-actions sheet.
  ///
  /// In en, this message translates to:
  /// **'This is permanent and irreversible. Document files are purged from R2 storage and the slug is released for reuse.'**
  String get revokeDocumentBodyShort;

  /// No description provided for @revokePermanentWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and irreversible.'**
  String get revokePermanentWarning;

  /// Revoke confirmation detail in the Reader.
  ///
  /// In en, this message translates to:
  /// **'Document files will be immediately purged from R2 storage. Live slugs will be cleared for reuse.'**
  String get revokeDocumentBodyLong;

  /// Toast after revoking from the Operate sheet.
  ///
  /// In en, this message translates to:
  /// **'Document revoked. {count} R2 object(s) purged.'**
  String documentRevokedPurged(Object count);

  /// Toast after revoking from the Reader.
  ///
  /// In en, this message translates to:
  /// **'Revoked \"{title}\" · {count} R2 object(s) purged'**
  String documentRevokedToast(String title, Object count);

  /// No description provided for @revocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Revocation failed: {error}'**
  String revocationFailed(String error);

  /// No description provided for @operatorActions.
  ///
  /// In en, this message translates to:
  /// **'Operator actions'**
  String get operatorActions;

  /// More-sheet action that re-fetches the document from the server (complements pull-to-refresh on the reader).
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @openingInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Opening in browser…'**
  String get openingInBrowser;

  /// No description provided for @urlCopiedPaste.
  ///
  /// In en, this message translates to:
  /// **'URL copied — paste it in your browser'**
  String get urlCopiedPaste;

  /// No description provided for @couldNotLaunchBrowser.
  ///
  /// In en, this message translates to:
  /// **'Could not launch browser — URL copied instead'**
  String get couldNotLaunchBrowser;

  /// Title of the confirmation modal when tapping an external link in the WebView reader.
  ///
  /// In en, this message translates to:
  /// **'Open in browser?'**
  String get openInBrowserDialogTitle;

  /// Body warning for external link navigation.
  ///
  /// In en, this message translates to:
  /// **'Navigating to: {url}'**
  String openInBrowserDialogBody(String url);

  /// Proceed button label on the open-in-browser warning.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get proceed;

  /// No description provided for @noBaseUrlConfigured.
  ///
  /// In en, this message translates to:
  /// **'No base URL configured. Open Settings to connect.'**
  String get noBaseUrlConfigured;

  /// Author fallback in the Reader meta row when the creating agent no longer exists.
  ///
  /// In en, this message translates to:
  /// **'Deleted agent'**
  String get deletedAgent;

  /// Author fallback on document cards when no author name is known.
  ///
  /// In en, this message translates to:
  /// **'Unknown agent'**
  String get unknownAgent;

  /// Label on the Reader's back pill (returns to the Café).
  ///
  /// In en, this message translates to:
  /// **'Café'**
  String get cafeBack;

  /// No description provided for @versionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get versionHistory;

  /// Subtitle of the version-history sheet (café metaphor).
  ///
  /// In en, this message translates to:
  /// **'On the menu'**
  String get onTheMenu;

  /// Error line shown in place of the list when the version-history request fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load version history'**
  String get versionHistoryLoadFailed;

  /// Badge on the row in the version list that readers are actually served. "Live" means the published version — the bytes anyone visiting the document's public URL receives — which is not necessarily the newest version. Uppercase to match the other badges.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get versionBadgeLive;

  /// Badge on the newest version in the version list. The current version is what the operator and every credentialed view read; on a public document whose older version is still published, CURRENT and LIVE sit on two different rows. Uppercase to match the other badges.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get versionBadgeCurrent;

  /// Sub-label on a version row whose original source bytes were never kept by the server.
  ///
  /// In en, this message translates to:
  /// **'No source retained'**
  String get versionNoSource;

  /// Explanation shown when the operator selects a version with no retained source: restoring copies the stored source into a new version, so a version without one cannot be restored.
  ///
  /// In en, this message translates to:
  /// **'This version predates source retention and can\'t be restored.'**
  String get versionNoSourceHint;

  /// Attribution fragment in a version row's meta line, e.g. "by Kitchen Bot" — the agent or operator that wrote that version.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String versionAuthorBy(String name);

  /// Toast when an action targets a version the server no longer has (the version_not_found error), usually because the history changed after this list was loaded.
  ///
  /// In en, this message translates to:
  /// **'That version no longer exists'**
  String get versionNotFoundToast;

  /// Label naming the version readers are actually served, e.g. "Live v3". "Live" means published — the version anyone opening the document's public URL receives — as opposed to the newest version, which may still be unpublished. The value may be a number or an em dash when unknown.
  ///
  /// In en, this message translates to:
  /// **'Live v{version}'**
  String liveVersionLabel(String version);

  /// Badge marking a document whose newest version has not been published, so readers are still being served an older version. Uppercase to match the other badges.
  ///
  /// In en, this message translates to:
  /// **'NOT LIVE'**
  String get notLiveBadge;

  /// Note under a document with unpublished work: {current} is the newest version, which only the operator sees, and {published} is the older version still being served to everyone else.
  ///
  /// In en, this message translates to:
  /// **'v{current} isn\'t live yet — readers see v{published}.'**
  String unpublishedWorkNote(int current, int published);

  /// Shown where a live version would be named, for a public document on which no version has ever been published.
  ///
  /// In en, this message translates to:
  /// **'Nothing published yet'**
  String get nothingPublishedYet;

  /// Action that makes the selected version the live one — the version every reader is served from then on.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishAction;

  /// Title of the confirmation sheet before making a version live, e.g. "Publish v4?".
  ///
  /// In en, this message translates to:
  /// **'Publish v{version}?'**
  String publishVersionTitle(int version);

  /// Body of the publish confirmation sheet. States the consequence plainly: publishing is a public act with no audience restriction, so keep this wording unambiguous.
  ///
  /// In en, this message translates to:
  /// **'Everyone who reads this document — including the anonymous internet — will see v{version}.'**
  String publishVersionBody(int version);

  /// Toast after publishing succeeds: that version is now the one readers are served.
  ///
  /// In en, this message translates to:
  /// **'v{version} is now live'**
  String publishedToast(int version);

  /// Toast when publishing fails; the live version is unchanged.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t publish that version'**
  String get publishFailedToast;

  /// Banner heading in the Reader when the document's newest version has not been published, so the operator is looking at the same older version readers get.
  ///
  /// In en, this message translates to:
  /// **'You\'re reading the live version'**
  String get readerServedBannerTitle;

  /// Body of that Reader banner, naming the newest version that exists but is not yet served to readers.
  ///
  /// In en, this message translates to:
  /// **'v{current} is newer and hasn\'t been published.'**
  String readerServedBannerBody(int current);

  /// Action on that Reader banner that switches the view to the newest, not-yet-published version, e.g. "View v5".
  ///
  /// In en, this message translates to:
  /// **'View v{version}'**
  String readerViewNewestAction(int version);

  /// Banner inside the version-history sheet when a historical version is selected.
  ///
  /// In en, this message translates to:
  /// **'Viewing historical v{version} — not the live version.'**
  String viewingHistoricalShort(int version);

  /// Banner above the reader body when viewing a historical version.
  ///
  /// In en, this message translates to:
  /// **'Viewing historical version v{version}. This is not the live version.'**
  String viewingHistoricalLong(int version);

  /// Title/CTA/button for restoring a historical version, e.g. "Restore v2".
  ///
  /// In en, this message translates to:
  /// **'Restore v{version}'**
  String restoreVersionTitle(int version);

  /// Body of the restore confirmation sheet. Says "a new version", not "a new live version": restore moves current_ver and leaves published_ver alone, so on a gated public document the restored head is not what readers are served until it is published.
  ///
  /// In en, this message translates to:
  /// **'This creates a new version of the document with the exact contents of v{version}.'**
  String restoreVersionBody(int version);

  /// Toast after restoring a version. Deliberately does NOT say the new version is live: restore is restore-as-new, so it moves current_ver and leaves published_ver exactly where it was — on a gated public document readers keep getting the older published version, and the served-version banner is what explains that.
  ///
  /// In en, this message translates to:
  /// **'Restored v{version} as v{newVer}'**
  String restoredVersion(int version, int newVer);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// Toast after toggling visibility from the Reader, e.g. "Now PUBLIC".
  ///
  /// In en, this message translates to:
  /// **'Now {visibility}'**
  String nowVisibility(String visibility);

  /// No description provided for @documentRevokedTitle.
  ///
  /// In en, this message translates to:
  /// **'Document revoked'**
  String get documentRevokedTitle;

  /// No description provided for @documentNotFound.
  ///
  /// In en, this message translates to:
  /// **'Document not found'**
  String get documentNotFound;

  /// No description provided for @documentRevokedHtmlBody.
  ///
  /// In en, this message translates to:
  /// **'This document has been permanently revoked.'**
  String get documentRevokedHtmlBody;

  /// No description provided for @documentNotFoundHtmlBody.
  ///
  /// In en, this message translates to:
  /// **'This document could not be found on the server.'**
  String get documentNotFoundHtmlBody;

  /// No description provided for @offlineConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Offline / connection error'**
  String get offlineConnectionError;

  /// No description provided for @couldNotRetrieve.
  ///
  /// In en, this message translates to:
  /// **'Could not retrieve the document. Please check your internet connection.'**
  String get couldNotRetrieve;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorTitle;

  /// Reader revoked-state body, e.g. "…revoked on Jan 4, 2026."
  ///
  /// In en, this message translates to:
  /// **'This document was permanently revoked on {date}.'**
  String documentRevokedOn(String date);

  /// Used in place of a date when a document's revoke timestamp is missing.
  ///
  /// In en, this message translates to:
  /// **'an unknown date'**
  String get unknownDate;

  /// No description provided for @revokedStateDetail.
  ///
  /// In en, this message translates to:
  /// **'All R2 file bytes have been purged and slugs released. The public and debug views now return 404.'**
  String get revokedStateDetail;

  /// No description provided for @visibilityPublic.
  ///
  /// In en, this message translates to:
  /// **'PUBLIC'**
  String get visibilityPublic;

  /// No description provided for @visibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'PRIVATE'**
  String get visibilityPrivate;

  /// Subtitle of the one-shot secret reveal sheet.
  ///
  /// In en, this message translates to:
  /// **'Shown once · never retrievable'**
  String get shownOnce;

  /// No description provided for @secretWarning.
  ///
  /// In en, this message translates to:
  /// **'This is the only time this secret is shown. Store it now — it is not kept in plaintext.'**
  String get secretWarning;

  /// No description provided for @secretStoredAck.
  ///
  /// In en, this message translates to:
  /// **'I\'ve securely stored this secret. I understand it can\'t be shown again.'**
  String get secretStoredAck;

  /// No description provided for @dismissPurgeSecret.
  ///
  /// In en, this message translates to:
  /// **'Dismiss & purge secret'**
  String get dismissPurgeSecret;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm action'**
  String get confirmAction;

  /// Lead-in before the highlighted confirmation word in a destructive confirm sheet (trailing space intentional).
  ///
  /// In en, this message translates to:
  /// **'Type '**
  String get typeToConfirmPrefix;

  /// Trailing text after the highlighted confirmation word (leading space intentional).
  ///
  /// In en, this message translates to:
  /// **' to confirm:'**
  String get typeToConfirmSuffix;

  /// Settings screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionTitle;

  /// No description provided for @credentialsSection.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get credentialsSection;

  /// Settings intro card heading (café metaphor for connecting).
  ///
  /// In en, this message translates to:
  /// **'Open the line'**
  String get openTheLine;

  /// No description provided for @connectionIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Point the operator app at your Slopcafe deployment and provide an admin token. Credentials are stored only on this device in secure storage.'**
  String get connectionIntroBody;

  /// No description provided for @baseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrlLabel;

  /// Example placeholder shown in the Base URL field.
  ///
  /// In en, this message translates to:
  /// **'https://slopcafe.com'**
  String get baseUrlHint;

  /// No description provided for @baseUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a Base URL'**
  String get baseUrlRequired;

  /// No description provided for @baseUrlInvalidScheme.
  ///
  /// In en, this message translates to:
  /// **'Must start with http:// or https://'**
  String get baseUrlInvalidScheme;

  /// No description provided for @operatorTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Operator Token'**
  String get operatorTokenLabel;

  /// No description provided for @operatorTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Operator-level admin token'**
  String get operatorTokenHint;

  /// No description provided for @operatorTokenRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the Operator token'**
  String get operatorTokenRequired;

  /// No description provided for @showToken.
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get showToken;

  /// No description provided for @hideToken.
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get hideToken;

  /// No description provided for @testingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get testingConnection;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @saveAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save & Continue'**
  String get saveAndContinue;

  /// Result panel text after a successful connection probe.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!\nSanitizer version: {sanitizer}\nStorage cap: {cap} bytes'**
  String connectionSuccessResult(String sanitizer, String cap);

  /// No description provided for @connectionProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection probe failed with unexpected codes.'**
  String get connectionProbeFailed;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailed(String error);

  /// No description provided for @connectionSaved.
  ///
  /// In en, this message translates to:
  /// **'Connection saved'**
  String get connectionSaved;

  /// No description provided for @secureStorageCleared.
  ///
  /// In en, this message translates to:
  /// **'Secure storage cleared'**
  String get secureStorageCleared;

  /// No description provided for @probeFailed.
  ///
  /// In en, this message translates to:
  /// **'Probe failed'**
  String get probeFailed;

  /// No description provided for @probeResult.
  ///
  /// In en, this message translates to:
  /// **'Probe result'**
  String get probeResult;

  /// Heading of the unauthorized banner on the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Token rejected'**
  String get tokenRejectedHeading;

  /// Unauthorized (401) message shown in the app-wide toast and the Settings banner body. Used as the fallback when the API layer carries no server-supplied detail.
  ///
  /// In en, this message translates to:
  /// **'Operator token rejected. Please verify your credentials.'**
  String get tokenRejectedDetail;

  /// No description provided for @clearSecureStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear secure storage'**
  String get clearSecureStorageTitle;

  /// No description provided for @clearSecureStorageBody.
  ///
  /// In en, this message translates to:
  /// **'Removes the saved Base URL and Operator Token from this device and resets the connection state.'**
  String get clearSecureStorageBody;

  /// No description provided for @clearSecureStorageButton.
  ///
  /// In en, this message translates to:
  /// **'Clear Secure Storage'**
  String get clearSecureStorageButton;

  /// No description provided for @relativeToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get relativeToday;

  /// No description provided for @relativeYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get relativeYesterday;

  /// Relative time within the last month, e.g. "5d ago".
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String relativeDaysAgo(int days);

  /// Relative time within the last year, e.g. "3mo ago".
  ///
  /// In en, this message translates to:
  /// **'{months}mo ago'**
  String relativeMonthsAgo(int months);

  /// Relative time over a year, e.g. "2y ago".
  ///
  /// In en, this message translates to:
  /// **'{years}y ago'**
  String relativeYearsAgo(int years);
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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
