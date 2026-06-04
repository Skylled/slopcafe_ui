# ♊ GEMINI.md — Repository Grounding & Codebase Map

Welcome! This file serves as a grounding and reference document for future AI developer sessions. It outlines the purpose of the Slopcafe Operator App (UI), maps key files and features to their respective implementations, and establishes the "self-healing" documentation protocol.

---

## 📌 Repository Purpose
The **Slopcafe Operator App** is a professional, feature-rich Flutter administrative application designed for operators to manage, search, monitor, and configure the Slopcafe fleet deployment.

It communicates with the Slopcafe Backend API to perform fleet management tasks, agent registrations, document revocation, and metadata indexing.

---

## 🛠️ Technology Stack
- **Framework**: Flutter SDK (>=3.0.0)
- **State Management**: `flutter_riverpod` (Riverpod 2.x)
- **HTTP Client**: `dio` (with custom interceptors for auth and status monitoring)
- **Local Persistence**: 
  - `flutter_secure_storage` (secure storage of base URLs and API operator tokens)
  - Custom SQLite or local file-based database for offline document caching
- **Platform Targets**: macOS, iOS, Android, and Web

---

## 🎨 Design Language — "Craft"
The mobile UI follows the **Craft** design language (a warm café metaphor): a terracotta **clay** +
**honey** OKLCH-derived palette, serif display type, emoji-free tinted cover tiles, press-cards, and a
floating pill tab bar. The information architecture is three tabs — **Library** ("The Café"),
**Search**, and **Operate** ("The Pass") — plus a full-screen document **Reader** and a pushed
**Settings** screen. Copy uses "light café flavor": café-flavored section/screen titles, professional
functional copy. Both **Craft-light** and a derived **Craft-dark** are supported via `ThemeMode.system`.

---

## 📂 Codebase Map & Key Functionalities

Below is the directory mapping of the core functionalities within the `lib/` directory:

### 1. Entry & Bootstrapping
* **[lib/main.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/main.dart)**
  * Initializes the `ProviderScope`, builds the `MaterialApp` (Craft light/dark themes, `ThemeMode.system`), and runs the application.
  * Contains `RootGate`: the first-launch gate that routes to `SettingsScreen` when the deployment is unconfigured (no Base URL/Operator Token in secure storage), otherwise to `AppShell`.
* **[lib/screens/app_shell.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/app_shell.dart)**
  * The three-tab shell: an `IndexedStack` of Library / Search / Operate beneath a floating pill tab bar.
  * Houses the global connection-state listener that intercepts `401 Unauthorized` token rejections and pushes the Settings screen.

### 2. Core Services
* **[lib/core/api_client.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/api_client.dart)**
  * Sets up the global `dioProvider` and defines custom interceptors.
  * Implements `connectionStateProvider` to track whether the app is in `connected`, `disconnected`, or `unauthorized` states.
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
  * Shared display formatters: `fmtBytes`, `fmtDate`, `relTime`, `greeting`.

### 3. Data Models
* **[lib/models/document.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/models/document.dart)**
  * Represents document metadata (slug, title, body content, status, tags, and timestamps).
* **[lib/models/agent.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/models/agent.dart)**
  * Represents fleet agents (IDs, active keys count, total keys minted, and live document counts).

### 4. State Management (Providers)
* **[lib/providers/document_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/document_provider.dart)**
  * Manages state for fetching document listings, including cursor-based infinite pagination.
  * Automatically serializes and caches the document list locally when online, and falls back to loading cached listings when offline.
  * Aggregates document tags for sidebar/filter widgets.
  * Integrates search algorithms (such as full-text BM25 keyword matching) to calculate relevance score indicators.
  * Implements local client-side search fallback over cached listings with highlight formatting when offline.
  * Provides triggers for revoking specific documents and caching them locally.
* **[lib/providers/agent_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/agent_provider.dart)**
  * Manages agent lists, agent creation, key minting/rotation, and key revocation actions.

### 5. UI & Screens (Craft IA)
* **[lib/screens/library_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/library_screen.dart)** — Library ("The Café") tab.
  * Greeting + connection-status pill (taps through to Settings), search affordance, fleet/menu tickers, a "Today's Special" featured document, a tag-based Collections carousel, and a "Recently plated" list. Offline banner + per-doc `OFFLINE READY` badge from cache state.
* **[lib/screens/search_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/search_screen.dart)** — Search tab.
  * Autofocus query field, debounced live results via `documentSearchProvider` (with local cached fallback), relevance bars, matched-field pills, and highlighted snippets. Suggestion chips when idle.
* **[lib/screens/operate_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/operate_screen.dart)** — Operate ("The Pass") tab.
  * Fleet stat grid + R2 storage bar; a "Kitchen" segment (agent rows → an agent bottom-sheet with keys, mint key, OAuth client, kill; plus mint-agent and unbound-OAuth flows) and a "Documents" segment (admin doc list with include-revoked + a per-doc actions sheet: visibility/slug/tags/revoke).
* **[lib/screens/reader_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/reader_screen.dart)** — full-screen document Reader ("the plate"), pushed as a route.
  * Cover + tags + serif title/description + byline + version sheet. View modes Read (WebView) / HTML / Markdown / Report (sanitizer report). Preserves the version-first offline cache strategy (conditional `If-None-Match`/`304`, instant cached render, reload only on version change). Houses copy-link, more-actions sheet, version restore, and the document revocation action. Pops `true` after a mutation so list/search callers can refresh.
* **[lib/screens/settings_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/settings_screen.dart)** — pushed Settings ("Connection") screen.
  * Configure + double-probe test the Base URL and Operator Token (`GET /healthz` then `GET /admin/agents`), save (optional `onSaved` callback, used by the first-launch gate), and clear secure storage. Shows the unauthorized banner.

### 6. Shared Widgets
* **[lib/widgets/](file:///Users/kyle/Repos/slopcafe_ui/lib/widgets/)** — Craft primitives composed by every screen: `pill.dart` (`Pill`/`VisBadge`/`OfflineReadyBadge`), `app_button.dart` (`AppButton`/`AppIconButton`), `press_card.dart` (`PressCard`/`RiseIn`), `stat.dart` (`MiniStat`/`OpStat`), `section_header.dart`, `sheets.dart` (`AppSheet`/`SecretSheet`/`showConfirmSheet`/`CopyField`/`SheetActionRow`), `toast.dart`, `cafe_logo.dart`.

---

## 🔗 External Integration Dependencies

* **Canonical HTTP API Reference**:
  * **Document Slug**: `slopcafe-http-api`
  * **URL**: [https://slopcafe.com/s/slopcafe-http-api](https://slopcafe.com/s/slopcafe-http-api)
  * Always consult this live document when modifying request/response schemas or endpoint paths.

---

## 🔄 Self-Healing Documentation Protocol (CRITICAL)

> [!IMPORTANT]
> **Maintaining Documentation Integrity:**
> Whenever you modify this repository—whether introducing new features, refactoring directory structures, changing providers, or updating API integrations—**you MUST update this `GEMINI.md` file.**
> 
> Keep the codebase map, dependencies list, and design guidelines completely accurate. Ensuring that this file self-heals at the end of each session ensures seamless continuity for all subsequent AI developer agents.
