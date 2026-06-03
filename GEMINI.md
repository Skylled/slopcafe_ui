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

## 📂 Codebase Map & Key Functionalities

Below is the directory mapping of the core functionalities within the `lib/` directory:

### 1. Entry & Bootstrapping
* **[lib/main.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/main.dart)**
  * Initializes the `ProviderScope` and runs the application.
  * Contains the `MainNavigationShell` widget, which manages the application's top-level navigation layout (supporting sidebar NavigationRail on desktop/tablets and BottomNavigationBar on mobile).
  * Implements `SettingsScreen` which allows operators to configure and test the Base URL and Operator Token via a double-probe check (checking `GET /healthz` and then `GET /admin/agents`).
  * Houses connection state listeners that automatically intercept `401 Unauthorized` token rejections and redirect users to the Settings Screen.

### 2. Core Services
* **[lib/core/api_client.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/api_client.dart)**
  * Sets up the global `dioProvider` and defines custom interceptors.
  * Implements `connectionStateProvider` to track whether the app is in `connected`, `disconnected`, or `unauthorized` states.
  * Appends authorization headers dynamically to all requests sent to the configured Base URL.
* **[lib/core/secure_storage.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/secure_storage.dart)**
  * Wraps `flutter_secure_storage` to encrypt and store the API Base URL and Operator Token.
* **[lib/core/document_cache.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/document_cache.dart)**
  * Manages the storage and retrieval of offline-cached documents to support running the app in disconnected mode.
* **[lib/core/theme.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/core/theme.dart)**
  * Defines the color schemes and typographic parameters for the light and dark visual themes.

### 3. Data Models
* **[lib/models/document.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/models/document.dart)**
  * Represents document metadata (slug, title, body content, status, tags, and timestamps).
* **[lib/models/agent.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/models/agent.dart)**
  * Represents fleet agents (IDs, active keys count, total keys minted, and live document counts).

### 4. State Management (Providers)
* **[lib/providers/document_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/document_provider.dart)**
  * Manages state for fetching document listings, including cursor-based infinite pagination.
  * Aggregates document tags for sidebar/filter widgets.
  * Integrates search algorithms (such as full-text BM25 keyword matching) to calculate relevance score indicators.
  * Provides triggers for revoking specific documents and caching them locally.
* **[lib/providers/agent_provider.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/providers/agent_provider.dart)**
  * Manages agent lists, agent creation, key minting/rotation, and key revocation actions.

### 5. UI & Screens
* **[lib/screens/documents_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/documents_screen.dart)**
  * Renders the documents index, including search bars, tag selectors, and infinite scrolling feeds.
* **[lib/screens/document_detail_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/document_detail_screen.dart)**
  * Displays the content of individual documents across three formats: a native WebView/iframe renderer, raw HTML source, and parsed GitHub-Flavored Markdown (GFM).
  * Houses the document revocation action.
* **[lib/screens/agents_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/agents_screen.dart)**
  * Displays a global directory of all active fleet agents with real-time status counters.
  * Provides actions for new agent registration.
* **[lib/screens/agent_detail_screen.dart](file:///Users/kyle/Repos/slopcafe_ui/lib/screens/agent_detail_screen.dart)**
  * Detail view for individual agents, allowing administrators to rotate access keys, view active API secrets, and decommission the agent.

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
