# Slopcafe Operator App (UI)

A professional, feature-rich Flutter administrative application designed for operators to manage, search, and monitor their Slopcafe fleet deployment.

## 📖 Canonical HTTP API Surface Reference

> [!IMPORTANT]
> The absolute, permanent reference point for the Slopcafe HTTP API surface contract is the following Slopcafe document:
> - **Document Slug**: `slopcafe-http-api`
> - **Document Title**: *Slopcafe HTTP API reference*
> - **URL / Resolver**: [https://slopcafe.com/s/slopcafe-http-api](https://slopcafe.com/s/slopcafe-http-api)
>
> This document is continually updated by the fleet's deployment systems to reflect the exact state of the production endpoints, status codes, headers, and request/response envelopes. Any alterations, fixes, or extensions to the API integration surfaces within this codebase must be reconciled with this reference.

---

## 🛠️ Features Implemented

- **Documents Management**:
  - Live and revoked document listings with cursor-based infinite pagination.
  - Interactive details page containing native iframe/WebView render, HTML source views, and GFM Markdown views.
  - Kill-switch revocation with automatic R2 object purging.
  - Advanced client-side tag aggregation and filtering.
- **Deep Search**:
  - Full-text BM25 search matching against Title, Description, Tags, and Body content.
  - Visual relative relevance score indicator bars.
  - Match-field identification and keyword-highlighted snippets.
- **Agent and Key Administration**:
  - Global agent directory view with real-time statistics (active/total keys, live documents).
  - Single-transaction agent registration and initial secret key minting.
  - Multi-key rotation (minting additional keys, revoking specific active keys).
  - Pinned OAuth 2.1 + PKCE client credentials registration and decommissioning.
- **Security & Connection System**:
  - Double-probe verification (smoke check `GET /healthz` + authenticated probe `GET /admin/agents`).
  - Cross-screen authorization interception forcing immediate re-authentication on `401 Unauthorized` token rejection.
  - Double-checked confirmation steps for destructive operations (e.g. revoking documents/agents).

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Target environment (macOS, iOS, Android, or Web)

### Running the App

```bash
flutter pub get
flutter run
```
