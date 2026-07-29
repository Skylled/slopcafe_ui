# Inbound web links (Android App Links)

Tapping a `https://slopcafe.com/d/<public_id>` or `https://slopcafe.com/s/<slug>`
link anywhere on an Android device opens that document in the operator app's
Reader instead of a browser.

The app half of this is done and tested. The **other half lives on the web
server** and cannot be done from this repository — see
[Step 1](#step-1--publish-assetlinksjson-required) below. Until that file is
published, the links still work; they just open in a browser as they always did.

---

## What the app claims

| | |
|---|---|
| Hosts | `slopcafe.com` only — not `www.`, not subdomains |
| Paths | `/d/…` and `/s/…` only |
| Schemes | `https` and `http` |
| Platforms | Android (and iOS, if a target is ever added). **Not macOS.** |

Everything else on the origin — the rendered site, `/openapi.json`, the root —
is deliberately left with the browser. Claiming the whole host would swallow
pages an operator console has nothing to show for.

Trailing byte-path segments are tolerated, so a copied `/d/<id>/raw` or
`/d/<id>/v/3/raw` URL still opens the document. Note the one under-delivery: a
version-pinned link opens the **latest** view, because the Reader owns version
selection in its own state rather than in its constructor.

A `/d/` link opens even when the document is **private** — the app resolves it
through the admin API with the operator's own token, which is the one thing a
browser could never have done with that URL.

### Why not macOS

macOS is excluded on purpose, and it is also excluded by circumstance. A
`https://` link only reaches a Mac app through Universal Links, which requires an
`Associated Domains` entitlement, which requires a Developer Program team — and
this app is ad-hoc signed with no team. Registering a custom URL scheme instead
would hijack the operator's browser links system-wide, which is the opposite of
what a desktop operator wants: on a Mac, a `slopcafe.com` link belongs in the
browser.

The rule is stated in one place, `deepLinksSupported` in
[`lib/providers/deep_link_provider.dart`](../lib/providers/deep_link_provider.dart),
rather than being left incidental.

---

## Step 1 — publish `assetlinks.json` (required)

Android verifies an App Link claim at install time by fetching

```
https://slopcafe.com/.well-known/assetlinks.json
```

over HTTPS (no redirects, `Content-Type: application/json`, HTTP 200). The
`android:autoVerify="true"` filter in the manifest is honoured **only** if that
file names this package and this build's signing certificate. Without it,
Android silently falls back to handing the link to a browser.

Publish exactly this, for the current (debug-signed) builds:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.slopcafe.slopcafe_ui",
      "sha256_cert_fingerprints": [
        "38:26:EA:37:9E:1E:00:9E:C9:82:58:BD:4F:2B:51:56:E2:59:F3:B4:B3:62:EE:D6:9B:79:9B:9F:CC:B2:FC:77"
      ]
    }
  }
]
```

> [!WARNING]
> That fingerprint is **this machine's Android debug keystore**
> (`~/.android/debug.keystore`), because `android/app/build.gradle.kts` still
> signs release builds with the debug config — there is a standing `TODO` there
> to fix that. Two consequences:
>
> - A build made on any other machine has a different debug fingerprint and will
>   not verify against this file.
> - The debug keystore's password is the well-known `android`. Listing its
>   fingerprint publicly means anyone holding that specific key file could ship
>   an app claiming these links. It is fine for getting this working; it is not
>   what should be live once there is a real release keystore.
>
> When a release keystore exists, add its fingerprint to the same array (the
> field is a list precisely so a build can be re-signed without breaking links)
> and drop the debug one.

Read a release keystore's fingerprint with:

```sh
keytool -list -v -keystore <path/to/release.jks> -alias <alias> \
  | grep 'SHA256:'
```

Google's generator and validator: <https://developers.google.com/digital-asset-links/tools/generator>

---

## Step 2 — verify on a device

```sh
# Install, then check what Android decided about the claim.
adb shell pm get-app-links com.slopcafe.slopcafe_ui
#   slopcafe.com: verified          <- assetlinks.json was found and matched
#   slopcafe.com: 1024              <- not verified (file missing/mismatched)

# Force a re-verification without reinstalling.
adb shell pm verify-app-links --re-verify com.slopcafe.slopcafe_ui

# Fire a link at the device directly. This bypasses verification, so it proves
# the app's own parsing and navigation independently of Step 1.
adb shell am start -a android.intent.action.VIEW \
  -d "https://slopcafe.com/s/slopcafe-http-api"
```

Worth testing all three entry states, since they take different paths through
the plugin:

1. **Cold** — app not running. The launch intent is held by the platform side
   and flushed to the first Dart subscriber, so this works even when the app
   opens onto Settings because the deployment is not configured yet: the link
   is delivered once setup completes.
2. **Warm** — app in the background. Arrives via `onNewIntent`
   (`android:launchMode="singleTop"` is already set).
3. **Unconfigured** — no Base URL / Operator Token yet. See (1).

---

## Changing the domain (adopters)

The host is written in two places, because Android decides whether the app is
*offered* a tap long before any Dart runs, and Dart decides whether to *accept*
it:

1. `manifestPlaceholders["deepLinkHost"]` in
   [`android/app/build.gradle.kts`](../android/app/build.gradle.kts)
2. `kDeepLinkHost` in [`lib/core/deep_link.dart`](../lib/core/deep_link.dart)

They must match. `test/deep_link_test.dart` reads the Gradle literal back and
fails if they drift, so this is a one-edit change in practice — change either
one and the test names the other.

Then publish `assetlinks.json` under the new host (Step 1); verification is
per-host, so a second host such as `www.` needs its own file **and** its own
`<data>` tuples in the manifest.

The runtime **Base URL** in Settings is a separate, independent knob: it is what
the app talks to, and it can point at a staging deployment while the build
claims the production domain.

---

## Where the code lives

| File | Role |
|---|---|
| [`lib/core/deep_link.dart`](../lib/core/deep_link.dart) | `kDeepLinkHost`, `DeepLinkTarget`, `parseDeepLink` — hermetic, no Flutter imports |
| [`lib/providers/deep_link_provider.dart`](../lib/providers/deep_link_provider.dart) | `app_links` subscription + the mobile-only rule |
| [`lib/screens/app_shell.dart`](../lib/screens/app_shell.dart) | `_openDeepLink` — resolve, then push the Reader |
| [`lib/providers/document_provider.dart`](../lib/providers/document_provider.dart) | `resolveListing` — the shared name→listing resolver |
| [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) | the `autoVerify` VIEW intent-filter |
| [`test/deep_link_test.dart`](../test/deep_link_test.dart) | parse matrix + the Gradle/Dart host invariant |
