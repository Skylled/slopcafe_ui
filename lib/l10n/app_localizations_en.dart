// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Slopcafe Operator';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabOperate => 'Operate';

  @override
  String get untitled => '[Untitled]';

  @override
  String get untitledPlain => 'Untitled';

  @override
  String get untagged => 'untagged';

  @override
  String versionLabel(String version) {
    return 'v$version';
  }

  @override
  String get actionAll => 'All';

  @override
  String get actionSeeAll => 'See all';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get saving => 'Saving…';

  @override
  String get working => 'Working…';

  @override
  String get revoke => 'Revoke';

  @override
  String get restore => 'Restore';

  @override
  String get deleteClient => 'Delete client';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String libraryGreeting(String greeting) {
    return '$greeting, Operator';
  }

  @override
  String get theCafe => 'The Café';

  @override
  String get statusLive => 'Live';

  @override
  String get statusTokenRejected => 'Token rejected';

  @override
  String get statusDisconnected => 'Disconnected';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusConnect => 'Connect';

  @override
  String get offlineBanner => 'Offline — showing cached documents.';

  @override
  String get tickerOnMenu => 'on the menu';

  @override
  String get tickerCooks => 'cooks on the line';

  @override
  String get tickerPublicPlates => 'public plates';

  @override
  String get collectionsTitle => 'Collections';

  @override
  String get recentlyPlatedTitle => 'Recently plated';

  @override
  String get mostRecentFirst => 'Most recent first';

  @override
  String get nothingPlatedYet => 'Nothing plated yet.';

  @override
  String get nothingPlatedHere => 'Nothing plated here yet.';

  @override
  String get noCollectionsYet => 'No collections yet.';

  @override
  String get browseByTag => 'Browse by tag';

  @override
  String get collectionEyebrow => 'Collection';

  @override
  String documentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents',
      one: '1 document',
    );
    return '$_temp0';
  }

  @override
  String collectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count collections',
      one: '1 collection',
    );
    return '$_temp0';
  }

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Titles, body, tags, slugs…';

  @override
  String get trySearching => 'TRY SEARCHING';

  @override
  String get searchSuggestionSeeds => 'sanitizer,recipe,oauth,espresso,revoke';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results · ranked by relevance',
      one: '1 result · ranked by relevance',
    );
    return '$_temp0';
  }

  @override
  String searchNoMatch(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get searchNoMatchHint => 'Try a different keyword, tag, or slug.';

  @override
  String get searchError => 'Search hit a snag.';

  @override
  String get searchCeilingHint =>
      'Showing the top 50 plates. Refine your search to find the rest.';

  @override
  String get searchModeHybrid => 'Hybrid';

  @override
  String get searchModeKeyword => 'Keyword';

  @override
  String get searchModeSemantic => 'Semantic';

  @override
  String get searchIndex => 'Search index';

  @override
  String get searchIndexSubtitle => 'Semantic search vectors';

  @override
  String get semanticSearch => 'Semantic search';

  @override
  String get backfillBody =>
      'Semantic search matches documents by concept using vector embeddings. Documents added before search was enabled — or any that slipped through — need embedding before they appear in semantic and hybrid results.';

  @override
  String get indexNewTitle => 'Index new documents';

  @override
  String get indexNewOptionBody =>
      'Embed only documents that don\'t have vectors yet. Fast and inexpensive.';

  @override
  String get indexNewConfirmBody =>
      'Embed every document that\'s missing search vectors. This is incremental and cheap — only un-indexed documents are touched.';

  @override
  String get indexNewCta => 'Index new';

  @override
  String get rebuildIndexTitle => 'Rebuild entire index';

  @override
  String get rebuildIndexOptionBody =>
      'Re-embed every document from scratch. Slower and more costly — use after an embedding-model change or to repair the index.';

  @override
  String get rebuildIndexConfirmBody =>
      'This re-embeds every live document from scratch — significantly more compute and real cost than indexing only new documents. Run it only after a model or chunk-size change, or to repair a stale index.';

  @override
  String get rebuildIndexCta => 'Rebuild index';

  @override
  String get indexingNew => 'Indexing new documents…';

  @override
  String get rebuildingIndex => 'Rebuilding the entire index…';

  @override
  String backfillDone(int embedded, int vectors, int skipped) {
    return 'Search index updated · $embedded embedded, $vectors vectors, $skipped skipped';
  }

  @override
  String get backfillUpToDate =>
      'Search index already up to date — nothing to embed.';

  @override
  String backfillPartial(int embedded, int vectors) {
    return 'Embedded $embedded docs but only $vectors vectors landed — some embeds failed. Try again.';
  }

  @override
  String backfillFailed(String error) {
    return 'Backfill failed: $error';
  }

  @override
  String get backOfHouse => 'Back of house';

  @override
  String get thePass => 'The Pass';

  @override
  String get liveDocuments => 'Live documents';

  @override
  String publicCountSub(int count) {
    return '$count public';
  }

  @override
  String get activeAgents => 'Active agents';

  @override
  String ofCountSub(int count) {
    return 'of $count';
  }

  @override
  String get activeKeys => 'Active keys';

  @override
  String mintedSub(int count) {
    return '$count minted';
  }

  @override
  String get sanitizer => 'Sanitizer';

  @override
  String get allGreen => 'all green';

  @override
  String get unavailable => 'unavailable';

  @override
  String get r2Storage => 'R2 storage';

  @override
  String storageCapLabel(String cap) {
    return 'cap $cap';
  }

  @override
  String get usageUnavailable => 'Usage figure unavailable.';

  @override
  String get segKitchen => 'The Kitchen';

  @override
  String get segDocuments => 'Documents';

  @override
  String agentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count agents',
      one: '1 agent',
    );
    return '$_temp0';
  }

  @override
  String get newAgent => 'New agent';

  @override
  String get unboundOAuthClients => 'Unbound OAuth clients';

  @override
  String get unboundOAuthSubtitle =>
      'Global clients not tied to any agent profile.';

  @override
  String get couldNotLoadFleet => 'Could not load the fleet.';

  @override
  String get noAgentsYet => 'No agents on the line yet. Hire one to begin.';

  @override
  String get allDocuments => 'All documents';

  @override
  String get includeRevoked => 'Include revoked';

  @override
  String get couldNotLoadDocuments => 'Could not load documents.';

  @override
  String get noDocuments => 'No documents to show.';

  @override
  String get revokedLower => 'revoked';

  @override
  String get revokedBadge => 'Revoked';

  @override
  String get revokedUpper => 'REVOKED';

  @override
  String get documentActionsTooltip => 'Document actions';

  @override
  String get agentHiredTitle => 'Agent hired';

  @override
  String get agentIdLabel => 'Agent ID';

  @override
  String get plaintextBearerKeyLabel => 'Plaintext bearer key';

  @override
  String get hireAgentTitle => 'Hire an agent';

  @override
  String get newProfile => 'New profile';

  @override
  String get hireAgentBody =>
      'Creates a logical agent profile and mints its initial bearer key. The key is shown only once.';

  @override
  String get agentNameLabel => 'AGENT NAME';

  @override
  String get agentNameHint => 'e.g. Claude Writer';

  @override
  String get hiring => 'Hiring…';

  @override
  String get hireAgent => 'Hire agent';

  @override
  String get nameRequired => 'Please enter a name.';

  @override
  String get nameTooLong => 'Name must be 200 characters or less.';

  @override
  String failedHireAgent(String error) {
    return 'Failed to hire agent: $error';
  }

  @override
  String get oauthClientCreated => 'OAuth client created';

  @override
  String get clientIdLabel => 'Client ID';

  @override
  String get clientSecretLabel => 'Client secret (one-shot)';

  @override
  String get mcpUrlLabel => 'MCP connection URL';

  @override
  String get globalConnections => 'Global connections';

  @override
  String get unboundClientsBody =>
      'Unbound clients are not tied to any single agent profile. They let operators authenticate valid agent flows dynamically.';

  @override
  String get mintUnboundClient => 'Mint unbound client';

  @override
  String get mintedOnThisDevice => 'MINTED ON THIS DEVICE';

  @override
  String get noUnboundClients => 'No unbound clients recorded on this device.';

  @override
  String failedMintUnbound(String error) {
    return 'Failed to mint unbound client: $error';
  }

  @override
  String get deleteUnboundTitle => 'Delete unbound client';

  @override
  String deleteUnboundBody(String clientId) {
    return 'Delete unbound OAuth client \"$clientId\"? This instantly revokes all live sessions and tokens issued under it.';
  }

  @override
  String get unboundClientDeleted => 'Unbound client deleted.';

  @override
  String failedDeleteClient(String error) {
    return 'Failed to delete client: $error';
  }

  @override
  String get agentProfile => 'Agent profile';

  @override
  String docsCountShort(int count) {
    return '$count docs';
  }

  @override
  String get mintKey => 'Mint key';

  @override
  String get oauthClientButton => 'OAuth client';

  @override
  String get oauthClientRegistered => 'OAuth client registered';

  @override
  String get deleteOAuthClientButton => 'Delete OAuth client';

  @override
  String get apiKeysLabel => 'API KEYS';

  @override
  String get noKeys => 'No keys registered. Mint one to authorize clients.';

  @override
  String inactiveAudit(int count) {
    return 'INACTIVE ($count)';
  }

  @override
  String get expiredUpper => 'EXPIRED';

  @override
  String errorFetchingKeys(String error) {
    return 'Error fetching keys: $error';
  }

  @override
  String get bearerKeyMinted => 'Bearer key minted';

  @override
  String get keyPlaintextLabel => 'Key plaintext';

  @override
  String failedMintKey(String error) {
    return 'Failed to mint key: $error';
  }

  @override
  String get revokeKeyTitle => 'Revoke key';

  @override
  String revokeKeyBody(String keyPrefix) {
    return 'Revoke key \"$keyPrefix\"? This is irreversible — the worker using it is immediately locked out.';
  }

  @override
  String keyRevoked(String keyPrefix) {
    return 'Key $keyPrefix revoked.';
  }

  @override
  String failedRevokeKey(String error) {
    return 'Failed to revoke key: $error';
  }

  @override
  String get oauthAlreadyExists =>
      'OAuth client already exists for this agent.';

  @override
  String failedMintOAuth(String error) {
    return 'Failed to mint OAuth client: $error';
  }

  @override
  String get deleteOAuthTitle => 'Delete OAuth client';

  @override
  String deleteOAuthBody(String clientId) {
    return 'Delete OAuth client \"$clientId\"? This instantly revokes every live access and refresh token issued to Claude or external MCP hosts.';
  }

  @override
  String get oauthClientDeleted => 'OAuth client deleted.';

  @override
  String failedDeleteOAuth(String error) {
    return 'Failed to delete OAuth client: $error';
  }

  @override
  String get killAgentTitle => 'Kill agent profile';

  @override
  String get cascadingDestruction => 'Cascading destruction. ';

  @override
  String get killAgentBody =>
      'This instantly revokes all bearer keys and deletes the agent\'s OAuth client.';

  @override
  String get killProfile => 'Kill profile';

  @override
  String agentKilled(Object keys, Object clients) {
    return 'Agent killed. Revoked $keys key(s), deleted $clients client(s).';
  }

  @override
  String failedKillAgent(String error) {
    return 'Failed to kill agent: $error';
  }

  @override
  String keyRevokedOn(String date) {
    return 'Revoked $date';
  }

  @override
  String keyMintedOn(String date) {
    return 'Minted $date';
  }

  @override
  String keyExpiredOn(String date) {
    return 'Expired $date';
  }

  @override
  String keyExpiresOn(String date) {
    return 'Expires $date';
  }

  @override
  String get makePublic => 'Make public';

  @override
  String get makePrivate => 'Make private';

  @override
  String get makePublicBody =>
      'Anyone with the link will be able to read this document.';

  @override
  String get makePrivateBody =>
      'Only authorized operators will be able to read this document.';

  @override
  String get makePrivateBodyReader =>
      'Only operators will be able to read this document.';

  @override
  String visibilitySet(String visibility) {
    return 'Visibility set to $visibility.';
  }

  @override
  String failedUpdateVisibility(String error) {
    return 'Failed to update visibility: $error';
  }

  @override
  String get noSlugUrl => 'No slug URL available.';

  @override
  String get slugUrlCopied => 'Slug URL copied.';

  @override
  String get editSlugTags => 'Edit slug & tags';

  @override
  String get copySlugUrl => 'Copy slug URL';

  @override
  String get documentActions => 'Document actions';

  @override
  String get documentMetadata => 'Document metadata';

  @override
  String get documentProperties => 'Document properties';

  @override
  String get slugLabel => 'SLUG';

  @override
  String get slugHint => 'e.g. my-cool-document';

  @override
  String get slugRetiredNote =>
      'Slugs are retired permanently when cleared or changed — the old slug then returns 410 Gone. Leave empty to clear.';

  @override
  String get tagsLabel => 'TAGS';

  @override
  String get tagsHint => 'comma, separated, tags';

  @override
  String get tagsHintReader => 'e.g. guide, tutorial, reference';

  @override
  String get separateTagsWithCommas => 'Separate tags with commas.';

  @override
  String get slugTagsUpdated => 'Slug & tags updated.';

  @override
  String get documentPropertiesUpdated => 'Document properties updated';

  @override
  String failedUpdate(String error) {
    return 'Failed to update: $error';
  }

  @override
  String get deprecatedUpper => 'DEPRECATED';

  @override
  String get markDeprecated => 'Mark deprecated';

  @override
  String get markActive => 'Mark active';

  @override
  String get markDeprecatedBody =>
      'The document stays served and searchable, but is marked as no longer current and left out of context packs by default.';

  @override
  String get markActiveBody =>
      'The document will count as current again. Any superseded-by pointer is cleared.';

  @override
  String get supersededByLabel => 'SUPERSEDED BY (OPTIONAL)';

  @override
  String get supersededByHint => 'Replacement document\'s public ID';

  @override
  String get supersededByNote =>
      'Readers are pointed at the replacement but never auto-redirected. Leave empty if there is no successor.';

  @override
  String statusSet(String status) {
    return 'Status set to $status.';
  }

  @override
  String failedUpdateStatus(String error) {
    return 'Failed to update status: $error';
  }

  @override
  String get deprecatedBanner =>
      'This document is deprecated — treat it as no longer current.';

  @override
  String get deprecatedBannerSuperseded =>
      'Deprecated — a newer document supersedes this one.';

  @override
  String get openReplacement => 'Open';

  @override
  String get statusFilterAll => 'All';

  @override
  String get statusFilterActive => 'Active';

  @override
  String get statusFilterDeprecated => 'Deprecated';

  @override
  String get authorDocument => 'Author a document';

  @override
  String get composeTitle => 'Compose';

  @override
  String get composeEyebrow => 'New document';

  @override
  String get composeModeWrite => 'Write';

  @override
  String get composeModePreview => 'Preview';

  @override
  String get composeFormatMarkdown => 'Markdown';

  @override
  String get composeFormatHtml => 'HTML';

  @override
  String get composeBodyHint => 'Write your document here…';

  @override
  String get composePreviewRaw => 'Preview · raw source';

  @override
  String get composePreviewEmpty => 'Nothing to preview yet.';

  @override
  String get composeDetails => 'Details';

  @override
  String get composeTitleLabel => 'TITLE';

  @override
  String get composeTitleHint =>
      'Optional — derived from the first heading if left blank';

  @override
  String get composeDescriptionLabel => 'DESCRIPTION';

  @override
  String get composeDescriptionHint => 'Optional short summary';

  @override
  String get composeSlugNote =>
      'Optional — a unique URL slug. Leave blank to auto-assign.';

  @override
  String get composeVisibilityLabel => 'VISIBILITY';

  @override
  String get composeVisibilityDefault => 'Default';

  @override
  String get composeVisibilityPublic => 'Public';

  @override
  String get composeVisibilityPrivate => 'Private';

  @override
  String get composeVisibilityNote =>
      '“Default” births the document at the deployment\'s configured visibility.';

  @override
  String get composePublish => 'Publish';

  @override
  String get composePublishing => 'Publishing…';

  @override
  String get composeContentRequired => 'Write some content before publishing.';

  @override
  String documentPublished(int version) {
    return 'Published as v$version.';
  }

  @override
  String documentPublishedSanitized(int version, int count) {
    return 'Published v$version — the sanitizer adjusted $count item(s).';
  }

  @override
  String failedPublish(String error) {
    return 'Failed to publish: $error';
  }

  @override
  String get revokeDocumentTitle => 'Revoke document';

  @override
  String get revokePermanently => 'Revoke permanently';

  @override
  String get revokeConfirmWord => 'REVOKE';

  @override
  String get revokeDocumentBodyShort =>
      'This is permanent and irreversible. Document files are purged from R2 storage and the slug is released for reuse.';

  @override
  String get revokePermanentWarning =>
      'This action is permanent and irreversible.';

  @override
  String get revokeDocumentBodyLong =>
      'Document files will be immediately purged from R2 storage. Live slugs will be cleared for reuse.';

  @override
  String documentRevokedPurged(Object count) {
    return 'Document revoked. $count R2 object(s) purged.';
  }

  @override
  String documentRevokedToast(String title, Object count) {
    return 'Revoked \"$title\" · $count R2 object(s) purged';
  }

  @override
  String revocationFailed(String error) {
    return 'Revocation failed: $error';
  }

  @override
  String get operatorActions => 'Operator actions';

  @override
  String get refresh => 'Refresh';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get openingInBrowser => 'Opening in browser…';

  @override
  String get urlCopiedPaste => 'URL copied — paste it in your browser';

  @override
  String get couldNotLaunchBrowser =>
      'Could not launch browser — URL copied instead';

  @override
  String get openInBrowserDialogTitle => 'Open in browser?';

  @override
  String openInBrowserDialogBody(String url) {
    return 'Navigating to: $url';
  }

  @override
  String get proceed => 'Proceed';

  @override
  String get noBaseUrlConfigured =>
      'No base URL configured. Open Settings to connect.';

  @override
  String get deletedAgent => 'Deleted agent';

  @override
  String get unknownAgent => 'Unknown agent';

  @override
  String get cafeBack => 'Café';

  @override
  String get versionHistory => 'Version history';

  @override
  String get onTheMenu => 'On the menu';

  @override
  String get versionHistoryLoadFailed => 'Couldn\'t load version history';

  @override
  String get versionBadgeLive => 'LIVE';

  @override
  String get versionBadgeCurrent => 'CURRENT';

  @override
  String get versionNoSource => 'No source retained';

  @override
  String get versionNoSourceHint =>
      'This version predates source retention and can\'t be restored.';

  @override
  String versionAuthorBy(String name) {
    return 'by $name';
  }

  @override
  String get versionNotFoundToast => 'That version no longer exists';

  @override
  String liveVersionLabel(String version) {
    return 'Live v$version';
  }

  @override
  String get notLiveBadge => 'NOT LIVE';

  @override
  String unpublishedWorkNote(int current, int published) {
    return 'v$current isn\'t live yet — readers see v$published.';
  }

  @override
  String get nothingPublishedYet => 'Nothing published yet';

  @override
  String get publishAction => 'Publish';

  @override
  String publishVersionTitle(int version) {
    return 'Publish v$version?';
  }

  @override
  String publishVersionBody(int version) {
    return 'Everyone who reads this document — including the anonymous internet — will see v$version.';
  }

  @override
  String publishedToast(int version) {
    return 'v$version is now live';
  }

  @override
  String get publishFailedToast => 'Couldn\'t publish that version';

  @override
  String get readerServedBannerTitle => 'You\'re reading the live version';

  @override
  String readerServedBannerBody(int current) {
    return 'v$current is newer and hasn\'t been published.';
  }

  @override
  String readerViewNewestAction(int version) {
    return 'View v$version';
  }

  @override
  String viewingHistoricalShort(int version) {
    return 'Viewing historical v$version — not the live version.';
  }

  @override
  String viewingHistoricalLong(int version) {
    return 'Viewing historical version v$version. This is not the live version.';
  }

  @override
  String restoreVersionTitle(int version) {
    return 'Restore v$version';
  }

  @override
  String restoreVersionBody(int version) {
    return 'This creates a new version of the document with the exact contents of v$version.';
  }

  @override
  String restoredVersion(int version, int newVer) {
    return 'Restored v$version as v$newVer';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String nowVisibility(String visibility) {
    return 'Now $visibility';
  }

  @override
  String get documentRevokedTitle => 'Document revoked';

  @override
  String get documentNotFound => 'Document not found';

  @override
  String get documentRevokedHtmlBody =>
      'This document has been permanently revoked.';

  @override
  String get documentNotFoundHtmlBody =>
      'This document could not be found on the server.';

  @override
  String get offlineConnectionError => 'Offline / connection error';

  @override
  String get couldNotRetrieve =>
      'Could not retrieve the document. Please check your internet connection.';

  @override
  String get errorTitle => 'Error';

  @override
  String documentRevokedOn(String date) {
    return 'This document was permanently revoked on $date.';
  }

  @override
  String get unknownDate => 'an unknown date';

  @override
  String get revokedStateDetail =>
      'All R2 file bytes have been purged and slugs released. The public and debug views now return 404.';

  @override
  String get visibilityPublic => 'PUBLIC';

  @override
  String get visibilityPrivate => 'PRIVATE';

  @override
  String get shownOnce => 'Shown once · never retrievable';

  @override
  String get secretWarning =>
      'This is the only time this secret is shown. Store it now — it is not kept in plaintext.';

  @override
  String get secretStoredAck =>
      'I\'ve securely stored this secret. I understand it can\'t be shown again.';

  @override
  String get dismissPurgeSecret => 'Dismiss & purge secret';

  @override
  String get confirmAction => 'Confirm action';

  @override
  String get typeToConfirmPrefix => 'Type ';

  @override
  String get typeToConfirmSuffix => ' to confirm:';

  @override
  String get connectionTitle => 'Connection';

  @override
  String get credentialsSection => 'Credentials';

  @override
  String get openTheLine => 'Open the line';

  @override
  String get connectionIntroBody =>
      'Point the operator app at your Slopcafe deployment and provide an admin token. Credentials are stored only on this device in secure storage.';

  @override
  String get baseUrlLabel => 'Base URL';

  @override
  String get baseUrlHint => 'https://slopcafe.com';

  @override
  String get baseUrlRequired => 'Please enter a Base URL';

  @override
  String get baseUrlInvalidScheme => 'Must start with http:// or https://';

  @override
  String get operatorTokenLabel => 'Operator Token';

  @override
  String get operatorTokenHint => 'Operator-level admin token';

  @override
  String get operatorTokenRequired => 'Please enter the Operator token';

  @override
  String get showToken => 'Show token';

  @override
  String get hideToken => 'Hide token';

  @override
  String get testingConnection => 'Testing…';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get saveAndContinue => 'Save & Continue';

  @override
  String connectionSuccessResult(String sanitizer, String cap) {
    return 'Connection successful!\nSanitizer version: $sanitizer\nStorage cap: $cap bytes';
  }

  @override
  String get connectionProbeFailed =>
      'Connection probe failed with unexpected codes.';

  @override
  String connectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get connectionSaved => 'Connection saved';

  @override
  String get secureStorageCleared => 'Secure storage cleared';

  @override
  String get probeFailed => 'Probe failed';

  @override
  String get probeResult => 'Probe result';

  @override
  String get tokenRejectedHeading => 'Token rejected';

  @override
  String get tokenRejectedDetail =>
      'Operator token rejected. Please verify your credentials.';

  @override
  String get clearSecureStorageTitle => 'Clear secure storage';

  @override
  String get clearSecureStorageBody =>
      'Removes the saved Base URL and Operator Token from this device and resets the connection state.';

  @override
  String get clearSecureStorageButton => 'Clear Secure Storage';

  @override
  String get relativeToday => 'today';

  @override
  String get relativeYesterday => 'yesterday';

  @override
  String relativeDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String relativeMonthsAgo(int months) {
    return '${months}mo ago';
  }

  @override
  String relativeYearsAgo(int years) {
    return '${years}y ago';
  }
}
