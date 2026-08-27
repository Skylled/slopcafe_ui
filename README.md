# Slopcafe Operator App (UI)

A professional, feature-rich Flutter administrative application designed for operators to manage, search, and monitor their Slopcafe fleet deployment.

## 🎨 Mobile experience — "Cortado"

The app uses the **Cortado** design language: a warm café-themed visual system (terracotta **clay** +
**honey** palette, serif display type, press-cards, a floating pill tab bar) with light + dark support.
The mobile information architecture is three tabs — **Library** ("The Café"), **Search**, and
**Operate** ("The Pass") — plus a full-screen document **Reader** and a **Connection** (Settings)
screen, which doubles as the manager for every saved deployment. See [GEMINI.md](GEMINI.md) for the full codebase map.

> Cortado's visual language is inspired by the [Craft](https://www.craft.do/) app, whose
> warm, document-forward aesthetic guided the original Claude Design overhaul.

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
- **Inbound web links (Android)**:
  - Tapping a `https://slopcafe.com/d/<id>` or `/s/<slug>` link anywhere on the device opens it in the app's Reader instead of a browser — including **private** documents, which resolve through the operator's own token.
  - Deliberately mobile-only; on macOS a web link belongs in the browser.
  - Requires an `assetlinks.json` on the web host to skip the browser. Setup and domain configuration: [docs/deep-links.md](docs/deep-links.md).
- **Multiple instances**:
  - Save several Slopcafe deployments (production, a fork, a local dev backend) and switch between them without signing out and back in.
  - One-tap quick switcher from the shell — the side rail's logo on desktop, a chip beside the Operate title on phones — with full add/edit/remove management on the Connection screen.
  - Each instance is isolated: its own operator token, its own OAuth client registrations, and its own offline document cache (a `public_id` means different things on different deployments, so the caches are namespaced rather than shared).
  - Test a new deployment's credentials before committing them, while another instance is still the active one.
  - An inbound web link is routed to the saved instance that actually serves that host, whichever one you left active.
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
