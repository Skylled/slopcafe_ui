# ♊ GEMINI.md — Repository Grounding & Codebase Map

Welcome! This file serves as a grounding and reference document for future AI developer sessions. It outlines the purpose of the Slopcafe Operator App (UI), maps key files and features to their respective implementations, and establishes the "self-healing" documentation protocol.

---

## 📌 Repository Purpose
The **Slopcafe Operator App** is a professional, feature-rich Flutter administrative application designed for operators to manage, search, monitor, and configure the Slopcafe fleet deployment.

It communicates with the Slopcafe Backend API to perform fleet management tasks, agent registrations, document revocation, and metadata indexing.

---

## 🛠️ Technology Stack
- **Framework**: Flutter SDK (>=3.0.0)
- **State Management**: `flutter_riverpod` (Riverpod 3.x). The mutable stores
  (`connectionStateProvider`, `documentsListProvider`, `agentsListProvider`) use
  the modern `Notifier`/`NotifierProvider` API — each overrides `build()` for its
  initial state and reads `ref` directly (Riverpod 3 dropped the legacy
  `StateNotifier`/`StateNotifierProvider` from the default barrel).
- **HTTP Client**: `dio` (with custom interceptors for auth and status monitoring)
- **Local Persistence**: 
  - `flutter_secure_storage` (v10; secure storage of base URLs and API operator
    tokens). v10 dropped the Jetpack-Security/`EncryptedSharedPreferences` Android
    backend (deprecated by Google) for default custom ciphers; values written by
    earlier builds auto-migrate on first access, so no `AndroidOptions` are set.
  - Custom SQLite or local file-based database for offline document caching
- **Localization**: `flutter_localizations` + `intl` via Flutter's `gen-l10n` ARB
  pipeline. Every user-facing string is centralized in `lib/l10n/app_en.arb`
  (see the **Localization (i18n)** section below).
- **API Models & Error Codes**: **generated** from the backend's canonical
  **OpenAPI 3.1** contract — `freezed` + `json_serializable` data classes plus an
  `ErrorCode` enum — by a bespoke pure-Dart emitter (`tool/generate_api.dart`)
  feeding the existing `build_runner` pipeline. The hand-written `lib/models/`
  classes are gone; see **API layer (generated from the OpenAPI contract)** below.
- **URL Launching**: `url_launcher` for external browser navigation on mobile platforms (Android/iOS).
- **Platform Targets**: macOS, iOS, Android, and Web

---

## 🎨 Design Language — "Craft"
The mobile UI follows the **Craft** design language (a warm café metaphor): a terracotta **clay** +
**honey** OKLCH-derived palette, serif display type, text-forward "plate" cards (no cover art), tinted
tag chips, press-cards, and a floating pill tab bar. The information architecture is three tabs —
**Library** ("The Café"), **Search**, and **Operate** ("The Pass") — plus pushed routes: a full-screen
document **Reader**, a **Collections** tag browser, a generic **document list** (a tag's collection /
"see all"), and **Settings**. Copy uses "light café flavor": café-flavored section/screen titles,
professional functional copy. Both **Craft-light** and a derived **Craft-dark** are supported via
`ThemeMode.system`.

---

## 🌐 Localization (i18n)
The app is wired for multiple languages using Flutter's **idiomatic `gen-l10n` ARB pipeline**, even
though only English (`en`) currently ships. The driving goal is centralization: **all user-facing
copy lives in a single editable file**, `lib/l10n/app_en.arb`, so wording can be tweaked without
hunting through widgets.

* **Single source of copy**: [lib/l10n/app_en.arb](file:///Users/kyle/Repos/slopcafe_ui/lib/l10n/app_en.arb)
  — the template ARB. Edit values here to change any in-app text. Plurals (e.g. `documentCount`,
  `searchResultCount`) use ICU syntax; placeholders (`{count}`, `{error}`, `{version}`) are typed in
  the `@key` metadata. A few notable conventions: `searchSuggestionSeeds` is a comma-separated list
  split at runtime into the Search idle chips; `revokeConfirmWord` is the word an operator must type
  to confirm a document revoke; trailing/leading spaces in `cascadingDestruction`,
  `typeToConfirmPrefix`, and `typeToConfirmSuffix` are intentional (they sit next to styled spans).
* **Config**: [l10n.yaml](file:///Users/kyle/Repos/slopcafe_ui/l10n.yaml) (arb-dir `lib/l10n`,
  output class `AppLocalizations`, `nullable-getter: false`). `pubspec.yaml` sets `generate: true`.
* **Generated code** (committed, **do not hand-edit**): `lib/l10n/app_localizations.dart` +
  `app_localizations_en.dart`. Regenerate after editing any ARB with **`flutter gen-l10n`** (also
  runs on `flutter pub get`).
* **Access pattern**: call sites read copy via the `context.l10n` extension defined in
  [lib/l10n/l10n.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/l10n/l10n.dart) — e.g.
  `context.l10n.searchTitle`, `context.l10n.documentCount(n)`. In `async` methods, capture
  `final l10n = context.l10n;` *before* the first `await` to avoid `use_build_context_synchronously`.
* **Wiring**: `MaterialApp` in `main.dart` registers `AppLocalizations.localizationsDelegates` /
  `supportedLocales` and sets the OS title via `onGenerateTitle`.
* **Context-less layers**: `lib/core/format.dart` helpers `relTime(l10n, date)` and `greeting(l10n)`
  take an `AppLocalizations`; byte/date formatting (`fmtBytes`, `fmtDate`) and separators stay
  locale-neutral. The `api_client` 401 handler intentionally carries **no** copy — the UI layer
  supplies the localized `tokenRejectedDetail`.
* **Adding a language**: copy `app_en.arb` to `app_<locale>.arb` (e.g. `app_es.arb`), translate the
  values, run `flutter gen-l10n`. No Dart changes required.

---

## 📂 Codebase Map & Key Functionalities

Below is the directory mapping of the core functionalities within the `lib/` directory:

### 1. Entry & Bootstrapping
* **[lib/main.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/main.dart)**
  * Initializes the `ProviderScope`, builds the `MaterialApp` (Craft light/dark themes, `ThemeMode.system`), and runs the application.
  * Registers the localization delegates (`AppLocalizations.localizationsDelegates` / `supportedLocales`) and sets the OS task-switcher title via `onGenerateTitle` (localized `appTitle`).
  * Contains `RootGate`: the first-launch gate that routes to `SettingsScreen` when the deployment is unconfigured (no Base URL/Operator Token in secure storage), otherwise to `AppShell`.
* **[lib/screens/app_shell.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/app_shell.dart)**
  * The three-tab shell: an `IndexedStack` of Library / Search / Operate beneath a floating pill tab bar.
  * Houses the global connection-state listener that intercepts `401 Unauthorized` token rejections and pushes the Settings screen.

### 2. Core Services
* **[lib/core/api_client.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/api_client.dart)**
  * Sets up the global `dioProvider` and defines custom interceptors.
  * Implements `connectionStateProvider` to track whether the app is in `connected`, `disconnected`, or `unauthorized` states. On a 401 it flips to `unauthorized` carrying **no app copy** — it parses the typed `ApiError` envelope and forwards the backend's own `ErrorBody.message` (server-supplied detail) into `errorMessage`, leaving it null otherwise; the UI layer renders the localized `tokenRejectedDetail` fallback (this service has no `BuildContext`).
  * Appends authorization headers dynamically to all requests sent to the configured Base URL.
* **[lib/core/secure_storage.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/secure_storage.dart)**
  * Wraps `flutter_secure_storage` to encrypt and store the API Base URL and Operator Token.
* **[lib/core/document_cache.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/document_cache.dart)**
  * Manages the storage and retrieval of offline-cached documents to support running the app in disconnected mode.
  * Encapsulates saving and loading the global documents metadata listing (`documents_list.json`), checking if specific document versions exist in the cache, and scanning the cache directory for version resolution.
* **[lib/core/theme.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/theme.dart)**
  * Assembles the Craft `ThemeData` (light + dark) from the design tokens: maps the palette onto a Material `ColorScheme` AND registers the raw token set as a `ThemeExtension`, plus component themes (cards, inputs, buttons, sheets).
* **[lib/core/design/tokens.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/design/tokens.dart)**
  * `AppColors` (a `ThemeExtension`) — the Craft-light + Craft-dark palettes (OKLCH→sRGB), shadows, tag tints, and decorative accents. Read anywhere via `context.colors`. Also `AppRadii` and `AppSpacing`.
* **[lib/core/design/typography.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/design/typography.dart)**
  * `AppText` — named serif/sans/mono text styles (system-font fallback stacks) + the Material `TextTheme` builder.
* **[lib/core/format.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/format.dart)**
  * Shared display formatters: `fmtBytes`, `fmtDate`, `relTime`, `greeting`, `titleCase` (tag/collection display names). The copy-bearing helpers take an `AppLocalizations`: `relTime(l10n, date)` and `greeting(l10n)`; the rest stay locale-neutral.
* **[lib/l10n/](file:///Users/kyle/Repos/slopcafe_ui/lib/l10n/)** — localization. `app_en.arb` (the single editable copy file), `l10n.dart` (the `context.l10n` extension), and the generated `app_localizations*.dart`. See the **Localization (i18n)** section above.

### 3. Data Models — `lib/api/` (GENERATED — see the API layer section below)
The hand-written `lib/models/document.dart` / `lib/models/agent.dart` have been
**replaced by code generated from the OpenAPI contract**. App code imports the
barrel **[lib/api/api.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/api/api.dart)**.
* **[lib/api/models.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/api/models.dart)** *(generated, do not edit)* — `freezed` + `json_serializable` data classes for every JSON request/response body in the spec: `DocumentListing`, `SearchHit`, `AgentListing`, `AgentKey`, `ListDocumentsResponse`, `SearchDocumentsResponse`, `ListAgentsResponse`, `ListAgentKeysResponse`, `MintAgentKeyResponse`, `CreateOAuthClientResponse`, `CreateUnboundOAuthClientResponse`, `Revoke{,Agent,Key}Response`, `SetDocument{Visibility,Slug,Tags}Response`, `HealthzResponse`, `BackfillResponse` (the per-page `POST /admin/vectors/backfill` result — drives the vector-index backfill; see the **semantic search** note below), etc. Nullable (OpenAPI-3.1 `anyOf`-null) fields generate as nullable Dart; `created_at`/`revoked_at` (plain spec strings) are typed `DateTime`; `visibility`/`matched_field` stay `String` (not enums) to avoid call-site churn (the semantic-search update added `"semantic"` as a fourth `matched_field` value — a vector-only concept hit; because the field is kept as `String`, this was a no-op for the generated layer). `DocumentListing`/`AgentKey` expose an `isRevoked` getter; `SearchHit` is flat with a `.document` view + `SearchHit.fromDocument(...)` (used by the offline local-search fallback). `toJson` emits the same snake_case keys as before, so the offline document cache stays compatible (a stale cache missing a newly-required field just fails the parse and falls back to an online fetch — `getCachedDocumentList` swallows it). As of the authoring update both `DocumentListing` and `SearchHit` also carry a **required** `created_by_kind` (`agent`|`operator`, kept as `String`), distinguishing operator-authored documents. As of contract **0.5.0** the `AgentKey` item also carries **required** `expired` (`bool`, server-computed) and `expires_at` (nullable `DateTime`; **null = never expires** — every operator-minted key and all legacy rows; a non-null value is a short-lived publish credential's TTL). Per the contract a key authenticates **only while `revoked_at` is null AND `expired` is false**, so `AgentKey` exposes `isActive => !isRevoked && !expired` (alongside the existing `isRevoked`) — the Operate key list buckets on `isActive` so a lapsed-but-un-revoked credential isn't shown as live (see Operate below). As of contract **0.10.0** (the lifecycle-status + context-packs update) `DocumentListing`/`SearchHit`/`ReadSourceResponse` carry a **required** `status` (`active`|`deprecated`|`archived`, kept as `String` like `visibility`) and a nullable `superseded_by` (a replacement doc's `public_id`; the contract mandates it is **never auto-followed** — surface it, let the reader decide), and new generated classes exist for the status mutator (`SetDocumentStatusResponse`) and the context-pack envelope (`PackResponse`/`PackInfo`/`PackRoot`/`PackDocument`/`PackOmitted`). The status axis is consumed across the UI (see the **Lifecycle status** notes under the provider, Operate, Reader, Search, and widgets entries); the pack envelope is generated but **no UI consumes packs yet**.
* **[lib/api/error_code.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/api/error_code.dart)** *(generated, do not edit)* — the `ErrorCode` enum: the 30 `error` discriminants of the `ErrorBody` oneOf union (0.10.0 added `bad_status` + `invalid_status`), plus `unknown` (forward-compat). `ErrorCode.fromWire(String?)` maps a wire value to a code.
* **[lib/api/api_error.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/api/api_error.dart)** *(hand-written glue)* — `ApiError`: a typed view over the `ErrorBody` envelope. `ApiError.fromException(e)` parses a `DioException`; `ApiError.describe(e)` returns the backend's `message` (falling back to the raw error) for toasts; discriminant extras are exposed as getters (`clientId`, `hint`, `slug`). The OAuth-exists path keys on `ErrorCode.clientExists`.

### 4. State Management (Providers)
* **[lib/providers/document_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/document_provider.dart)**
  * Manages state for fetching document listings, including cursor-based infinite pagination.
  * Automatically serializes and caches the document list locally when online, and falls back to loading cached listings when offline.
  * Aggregates document tags for sidebar/filter widgets.
  * Integrates search algorithms (such as full-text BM25 keyword matching) to calculate relevance score indicators.
  * Implements local client-side search fallback over cached listings with highlight formatting when offline.
  * `documentSearchProvider` (a `FutureProvider.family` keyed by `SearchQueryParams`) calls `GET /admin/documents/search`. `SearchQueryParams` carries the `SearchMode` enum (`hybrid` (default) · `keyword` · `semantic`) which is sent as the `mode` query param — the backend's hybrid leg fuses BM25 + vector (Vectorize/Workers-AI) search via RRF. The Search tab's segmented selector drives it. The offline cached fallback is keyword-only substring matching regardless of mode (mirroring the backend's own best-effort degrade-to-keyword behaviour when embedding is unavailable).
  * Provides triggers for revoking specific documents and caching them locally.
  * Exposes `updateStatus(publicId, status, {supersededBy})` — the lifecycle-status mutator (`POST /admin/documents/:id/status`, no version bump), the fourth sibling of the `updateVisibility`/`updateSlug`/`updateTags` writes. `'deprecated'` may carry a `supersededBy` replacement public_id; the backend force-clears the pointer on `'active'` and the response is canonical for both fields (the local row + offline cache mirror it).
  * Exposes `authorDocument(...)` — the operator authoring write (`POST /admin/documents`). Builds the inline request body (`content`+`format` required; optional `title`/`description`/`tags`/`slug`/`visibility`), returns the backend's `WriteResponse`, and reloads the canonical first page on success.
  * Exposes `backfillVectors(VectorBackfillMode)` — walks the cursor-paginated `POST /admin/vectors/backfill` to completion (`missing` = embed un-vectored docs · `rebuild` = re-embed the corpus) and returns a summed `BackfillSummary`. Drives the Operate › Documents "Search index" action; touches no document state (vectors are a search-side index).
* **[lib/providers/agent_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/agent_provider.dart)**
  * Manages agent lists, agent creation, key minting/rotation, and key revocation actions.
* **[lib/providers/health_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/health_provider.dart)**
  * `healthProvider` (`Notifier<HealthState>`) — the best-effort `/healthz` snapshot (sanitizer version + R2 storage cap/used) shown on the Operate stat grid + storage bar. Was Operate-local widget state; **lifted into a provider** so the shared pull-to-refresh can reload it from either home tab. `load()` is best-effort (a failure keeps the last snapshot; the opportunistic `storage_used_bytes`/`storage_bytes_used` field isn't in the contract).
* **[lib/providers/refresh.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/refresh.dart)**
  * `refreshFleetData(ref)` — the single pull-to-refresh routine for both home tabs. Concurrently reloads the document list, the agent fleet, and the health snapshot (`clear: true` for the lists) — the same fetches a cold app open kicks off, so a pull behaves "as if the app were opened anew" regardless of which tab started it. Wired into both Library's and Operate's `RefreshIndicator`.

### 5. UI & Screens (Craft IA)
* **[lib/screens/library_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/library_screen.dart)** — Library ("The Café") tab.
  * Greeting + connection-status pill (taps through to Settings), fleet/menu tickers, a text-forward "Today's Special" featured plate (`DocFeedCard`; currently the newest public doc — curated selection deferred to a future backend feature), a tag-based Collections carousel ("All" → `CollectionsScreen`, tiles → `DocumentListScreen`), and a "Recently plated" list ("See all" → `DocumentListScreen`). Offline banner from cache state. No search bar (Search is its own tab) and no per-doc `OFFLINE READY` badge. **Pull-to-refresh** (a `RefreshIndicator` over the `ListView`) runs the shared `refreshFleetData` — a full document + agent + health reload, identical to an Operate pull.
* **[lib/screens/search_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/search_screen.dart)** — Search tab.
  * Autofocus query field, debounced live results via `documentSearchProvider` (with local cached fallback), relevance bars, matched-field pills (deprecated hits also carry the `DEPRECATED` badge), and highlighted snippets. Suggestion chips when idle. A **segmented Hybrid/Keyword/Semantic mode selector** (`_SearchModeSelector`, styled like `PillTone.solid`) appears beneath the field while a query is active and drives `SearchQueryParams.mode`. Semantic-only hits surface as a `SEMANTIC` matched-field pill and an **un-bracketed** snippet (the backend deliberately omits the `[term]` brackets to signal "concept match, not term match"); the snippet parser already renders an un-bracketed string as plain text, and the relevance bar normalizes against the in-set max score (so the per-mode score scales — fused RRF / negated BM25 / cosine — stay comparable within a result set).
* **[lib/screens/operate_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/operate_screen.dart)** — Operate ("The Pass") tab.
  * Fleet stat grid + R2 storage bar; a "Kitchen" segment (agent rows → an agent bottom-sheet with keys, mint key, OAuth client, kill; plus mint-agent and unbound-OAuth flows). The agent sheet's key list buckets on `AgentKey.isActive`: live keys (neither revoked nor expired) get the revoke action and, if they carry a future TTL, an "Expires …" sub-label; everything else falls into a single **INACTIVE** audit section where each `_KeyRow` shows the right tombstone pill — red **REVOKED** or neutral **EXPIRED** (a lapsed-but-un-revoked short-lived publish credential) and a "Documents" segment (an **"Author a document"** CTA that pushes the compose screen, a **"Search index"** entry that opens the vector-backfill sheet (`_BackfillSheet` — index-new vs rebuild, each confirmed), the admin doc list with include-revoked, a three-way **lifecycle filter** (`_StatusFilterSegmented`: All/Active/Deprecated — client-side over the loaded provider pages, like include-revoked) and a `DEPRECATED` badge on deprecated rows, + a per-doc actions sheet: visibility/**status**/slug/tags/revoke — the status row toggles Mark deprecated (via the shared `showDeprecateSheet`, optional `superseded_by` target) / Mark active (plain confirm; the pointer clears server-side)). After authoring it surfaces the outcome (incl. any sanitizer adjustments) via toast. The `/healthz` metrics come from `healthProvider` (no longer Operate-local state). **Pull-to-refresh** (a `RefreshIndicator` over the `ListView`) runs the shared `refreshFleetData` — the same full reload as a Library pull.
* **[lib/screens/compose_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/compose_screen.dart)** — operator authoring / **Markdown composition** screen, pushed from Operate › Documents.
  * A deliberately **forkable starting point**. The plumbing is wired end-to-end against the live contract: the metadata form (title/description/tags/slug/visibility), the `format` (Markdown/HTML) toggle, the write/preview switch, the `POST /admin/documents` call (via `documentsListProvider.authorDocument`), and sanitizer-aware result handling. The actual Markdown/HTML **rendering is intentionally left as an isolated swap seam** — `_PreviewPane`, currently a raw-source passthrough — so renderer packages (flutter_markdown, markdown_widget, gpt_markdown, …) can be A/B'd without touching the rest of the screen. **No rendering dependency was added** (deferred by design). Visibility is tri-state (Default = omit the field → deploy default · Public · Private). Pops the `WriteResponse` on success (the list is already reloaded by the provider). Render/behaviour covered by [test/compose_screen_test.dart](file:///Users/kyle/Repos/slopcafe_ui/test/compose_screen_test.dart).
* **[lib/screens/reader_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/reader_screen.dart)** — full-screen document Reader ("the plate"), pushed as a route.
  * WebView-only reader with deliberately minimal chrome: a compact top bar (back · version chip · more), a single-line truncated serif title, a thin meta row (visibility · author · date), and tappable tag chips (→ `DocumentListScreen`). The WebView lives in an `Expanded` inside a `Column` (not a scroll view), so it scrolls internally and owns the screen edge-to-edge. Preserves the version-first offline cache strategy (conditional `If-None-Match`/`304`, instant cached render, reload only on version change). Operator actions are consolidated in the more-sheet (copy link, make public/private, mark deprecated/active — the lifecycle-status toggle, same `showDeprecateSheet` flow as Operate — edit slug & tags, copy slug URL, open in browser, revoke) plus version restore. A deprecated document shows a `DEPRECATED` badge in the meta row and a honey caution **banner** above the WebView; when `superseded_by` names a replacement, the banner's Open CTA resolves it (by public_id, via the same `_resolveDocumentListing` path link-clicks use) and pushes a new Reader — the contract never auto-follows the pointer, so the tap is the reader's explicit decision. Pops `true` after a revoke so list/search callers can refresh. Intercepts link clicks: matching configured Host URL links navigate the app internally to the document (resolving by public ID or slug), while other external links present an "Open in browser?" warning dialog before launching. (The cover, description, `OFFLINE READY` badge, bottom action bar, and the HTML/Markdown/Report view modes were removed.)
* **[lib/screens/collections_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/collections_screen.dart)** — pushed **Collections** tag browser.
  * Lists every tag (counts computed client-side from loaded docs, matching the Library carousel); each row opens that tag's collection via `DocumentListScreen`.
* **[lib/screens/document_list_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/document_list_screen.dart)** — pushed generic document list.
  * Renders documents as text-forward `DocFeedCard`s. Powers both a single tag's collection (`tag` set) and "Recently plated → See all" (newest-first), reading and filtering the shared `documentsListProvider` client-side. Exposes the static `DocumentListScreen.openForTag(context, tag)` — the shared tag-tap navigation used by cards, Collections, and the Reader.
* **[lib/screens/settings_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/settings_screen.dart)** — pushed Settings ("Connection") screen.
  * Configure + double-probe test the Base URL and Operator Token (`GET /healthz` then `GET /admin/agents`), save (optional `onSaved` callback, used by the first-launch gate), and clear secure storage. Shows the unauthorized banner.

### 6. Shared Widgets
* **[lib/widgets/](file:///Users/kyle/Repos/slopcafe_ui/lib/widgets/)** — Craft primitives composed by every screen: `pill.dart` (`Pill`/`VisBadge`/`DeprecatedBadge` — the honey-toned lifecycle pill, rendered only for `status == 'deprecated'` — /`TagChip` — the tinted, tappable tag chip), `doc_feed_card.dart` (`DocFeedCard` — the text-forward "plate" card shared by Library / Collections / document lists; deprecated docs carry the `DeprecatedBadge` beside the visibility marker), `app_button.dart` (`AppButton`/`AppIconButton`), `press_card.dart` (`PressCard`/`RiseIn`), `stat.dart` (`MiniStat`/`OpStat`), `section_header.dart` (`SectionHeader`/`MetaDot`/`Eyebrow`/`BackHeader` — the pushed-screen back+title header), `sheets.dart` (`AppSheet`/`SecretSheet`/`showConfirmSheet`/`showDeprecateSheet` — the deprecate flow's sheet: explainer + optional `superseded_by` field, returns the trimmed target or null on cancel; the caller owns the POST — /`CopyField`/`SheetActionRow`), `toast.dart`, `cafe_logo.dart`. Status-surfacing render coverage lives in [test/status_lifecycle_test.dart](file:///Users/kyle/Repos/slopcafe_ui/test/status_lifecycle_test.dart).

---

## 🔗 External Integration Dependencies

* **Canonical OpenAPI spec (machine source of truth)**:
  * Served live at **[https://slopcafe.com/openapi.json](https://slopcafe.com/openapi.json)** — OpenAPI **3.1.0**, `info.version` tracked in `tool/CONTRACT_VERSION` (currently **0.10.0**). The app's models + `ErrorCode` are generated from a pinned copy at `tool/openapi.json`. See the **API layer** section below.
* **Canonical HTTP API Reference (human reference)**:
  * **Document Slug**: `slopcafe-http-api`
  * **URL**: [https://slopcafe.com/s/slopcafe-http-api](https://slopcafe.com/s/slopcafe-http-api)
  * Consult this live document for behavioral/narrative contract the spec can't encode.

---

## 🔌 API layer (generated from the OpenAPI contract)

The app's API models and error codes are **generated from the backend's canonical
OpenAPI 3.1 spec** rather than hand-maintained, so they stay in sync with the
backend automatically (this was "Phase 3 — consumer adoption" of the backend's
code-first API-contract effort).

* **Pinned spec**: `tool/openapi.json` — an exact copy of what prod serves at
  `https://slopcafe.com/openapi.json`. Generating from the pin (not the live URL)
  keeps builds reproducible. `tool/CONTRACT_VERSION` records the `info.version`
  generated against. **Re-pin + regenerate whenever the backend surface
  changes** — not only on an `info.version` bump. (The operator authoring
  endpoints + `created_by_kind` landed under an unchanged `info.version` of
  `1.0.0`, so `CONTRACT_VERSION` stayed `1.0.0`; only update it if `info.version`
  actually changes. The semantic-search surface — the `/admin/documents/search`
  `mode` param, the new `POST /admin/vectors/backfill` path + `BackfillResponse`
  schema, and the `"semantic"` `matched_field` value — landed the same way: pin
  re-pulled, `CONTRACT_VERSION` left at `1.0.0`.) The inverse also happens: the
  backend later **renumbered** `info.version` `1.0.0` → **`0.4.0`** with **no
  surface change** — pre-launch they switched off the placeholder `1.0.0` to
  `0.x.y` nomenclature, and going forward any change (breaking or not) bumps the
  minor/tweak digits for consumer visibility; the `1.0.0` bump is reserved for
  actual launch. That re-pin touched only the version numeral (the pinned spec is
  otherwise byte-identical), so the only generated diff was the contract string in
  the `models.dart` / `error_code.dart` headers. The first **real** surface change
  under that scheme then bumped `0.4.0` → **`0.5.0`**: the `AgentKey` item (in
  `ListAgentKeysResponse.keys`) gained two **required** fields — `expires_at`
  (nullable ISO; null = never expires) and `expired` (server-computed bool) — so a
  key is now "active" only when neither revoked nor expired. The generator emits
  these automatically (`expires_at` → nullable `DateTime`; `expired` → `bool`);
  the one hand-edit was the new `isActive` convenience getter on `AgentKey`
  (`tool/generate_api.dart` `_extraMembers`). The companion agent counts
  (`active_keys`/`total_keys` on `AgentListing`) were already in the spec; their
  contract definition now also excludes expired keys (no schema diff). The next
  re-pin jumped **0.5.0 → 0.10.0** in one hop, absorbing four backend bumps:
  the operator console (HTML-only paths, invisible to codegen), the **lifecycle
  status axis** (required `status` + nullable `superseded_by` on
  `DocumentListing`/`SearchHit`/`ReadSourceResponse`; the new
  `POST /admin/documents/{id}/status` mutator; `status` filter param on
  list/search; error codes `bad_status`/`invalid_status`), **context packs**
  (the `Pack*` schemas behind search's `include_bodies` knob — note
  `SearchOrPackResponse` is a pure `anyOf` union with no `properties`, which the
  generator correctly skips: a caller knows which arm it gets from the
  `include_bodies` param it sent; `load_context_pack` is MCP-only, no HTTP
  twin), and 0.10.0's auth widening on the five content-read endpoints (prose
  only, no shape change). Generator config change: `DocumentStatus` joined
  `_stringEnumSchemas` (it's a `$ref`'d string enum — without the entry it
  emits as `dynamic`). The required `status` field also meant updating the one
  hand-built `DocumentListing(...)` placeholder (`reader_screen.dart`) and the
  `tool/smoke_test.dart` fixtures (which had silently drifted — they were
  missing `created_by_kind` since the authoring update and failing 2 checks
  before this re-pin). A stale offline `documents_list.json` missing `status`
  fails the parse and falls back to an online fetch, by design.
  ```sh
  curl -s https://slopcafe.com/openapi.json -o tool/openapi.json
  # update tool/CONTRACT_VERSION if info.version changed
  dart run tool/generate_api.dart        # spec -> lib/api/models.dart + error_code.dart
  dart run build_runner build            # -> models.freezed.dart + models.g.dart
  ```
* **Generator**: [tool/generate_api.dart](file:///Users/kyle/Repos/slopcafe_ui/tool/generate_api.dart)
  — a dev-only, pure-Dart script (no Flutter imports) that walks
  `components.schemas` and emits `lib/api/models.dart` (freezed) + `lib/api/error_code.dart`.
  Its header documents **why a bespoke emitter** rather than an off-the-shelf
  generator: `swagger_dart_code_generator` doesn't support 3.1 and emits
  non-nullable fields for `anyOf`-null (a runtime crash on revoked docs);
  `swagger_parser`/`swagger_to_dart` handle 3.1 nullability but force a Retrofit
  dep, `String` (not `DateTime`) timestamps, an enum (not `String`) `visibility`,
  and **still** require a hand-written 28-code error enum — net *more* churn. The
  bespoke emitter is ~thin: the real serialization/`copyWith`/equality is produced
  by the standard `freezed` + `json_serializable` + `build_runner` pipeline.
  Small app-specific config lives at the top of the script (string-enum schemas
  kept as `String`, `score` typed `double`, `_at` strings typed `DateTime`,
  inline-item name overrides `agents→AgentListing` / `keys→AgentKey`).
* **Generated outputs** (committed, **do not hand-edit**): `lib/api/models.dart`,
  `lib/api/error_code.dart`, and the `build_runner` products `models.freezed.dart`
  / `models.g.dart`. Hand-written glue: `lib/api/api_error.dart`; barrel: `lib/api/api.dart`.
* **Operator authoring (write) routes use hand-built request maps**:
  `POST /admin/documents` (author a new doc as the operator principal) and
  `PUT /admin/documents/{public_id}` (update → new version, optional `If-Match`)
  take request bodies the spec models **inline** (not in `components.schemas`),
  so the generator emits no request class — `DocumentsListNotifier.authorDocument`
  builds the JSON map directly (mirroring the existing `set{Visibility,Slug,Tags}`
  writes). Both return the generated `WriteResponse` (new `public_id`/`url`/
  `version` + the sanitizer report `stripped`/`will_not_render`). The compose UI
  lives in `lib/screens/compose_screen.dart`. (Only `POST` — author-new — is wired
  in the UI so far; `PUT`/edit is a future extension over the same `WriteResponse`.)
* **Non-JSON routes stay hand-rolled** (by spec design): content-negotiated /
  raw-bytes / HTML reads (`/d/{id}`, `/d/{id}/raw`, `/d/{id}/text`, `/s/{slug}`,
  the version `/raw` reads, restore) and `/mcp` are not JSON-modelled — the
  Reader's WebView + ETag conditional-GET cache and the 404/410 status-code
  handling there are intentionally **not** routed through `ErrorCode` (the bodies
  aren't the JSON envelope).
* **Semantic search (`mode` + backfill)**: the backend added a hybrid
  keyword+vector search. `GET /admin/documents/search` gained a `mode` query
  param — `hybrid` (default; BM25 ⊕ Vectorize/Workers-AI fused via Reciprocal
  Rank Fusion) · `keyword` (FTS only) · `semantic` (vector only). It's a query
  param (not a `components.schemas` shape), so the generator emits nothing for
  it — `documentSearchProvider` threads it by hand from the `SearchMode` enum,
  surfaced by the Search tab's segmented selector. `SearchHit.matched_field`
  gained `"semantic"` (un-bracketed snippet ⇒ concept match); kept as `String`,
  so no codegen change. Behavioural notes from the contract: search is **not
  paginated** (50-cap, raise `limit` up to 200 to widen), the query embed is
  **best-effort** (a brief embedding outage degrades `hybrid`/`semantic` to the
  keyword leg rather than erroring; the only hard failure is `422 bad_query`
  when no leg can run), and `score` scale **differs by mode and is only
  comparable within one result set** (already handled — the relevance bar
  normalizes against the in-set max). **Vector backfill:**
  `DocumentsListNotifier.backfillVectors(VectorBackfillMode)` walks
  `POST /admin/vectors/backfill` (operator; `mode=missing|rebuild`, cursor-
  paginated → the generated `BackfillResponse`) to completion, summing pages
  into a `BackfillSummary`. Docs published before semantic search shipped have
  no vectors and stay invisible to the semantic/hybrid legs until embedded.
  Surfaced as the Operate › Documents **"Search index"** entry (`_BackfillSheet`)
  with two clearly-delineated modes — **index-new** (`missing`; cheap,
  incremental) and **rebuild** (re-embed the whole corpus; flagged as the
  costly option) — **each gated by its own confirmation sheet** (rebuild gets
  the danger CTA). `BackfillSummary.suspectPartialFailure` (`vectors ≪ embedded`)
  drives a "some embeds failed, re-run" warning toast.
* **Smoke test**: [tool/smoke_test.dart](file:///Users/kyle/Repos/slopcafe_ui/tool/smoke_test.dart)
  validates the generated layer against the **live** backend (public `/healthz`
  + an unauthenticated 401 → `ErrorCode.unauthorized`) and a revoked-doc fixture
  (the 3.1-nullable risk). Run `dart run tool/smoke_test.dart`; set
  `OPERATOR_TOKEN=…` to also exercise the authenticated list → search flow.

---

## 🔄 Self-Healing Documentation Protocol (CRITICAL)

> [!IMPORTANT]
> **Maintaining Documentation Integrity:**
> Whenever you modify this repository—whether introducing new features, refactoring directory structures, changing providers, or updating API integrations—**you MUST update this `GEMINI.md` file.**
> 
> Keep the codebase map, dependencies list, and design guidelines completely accurate. Ensuring that this file self-heals at the end of each session ensures seamless continuity for all subsequent AI developer agents.
