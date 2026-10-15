# Usage Rings

Keep the providers, read-only CLI, and WidgetKit extension independent of cc:.
Human setup and privacy information belong in [README.md](README.md). Keep repository
instructions in these two documents; retain `LICENSE`, `THIRD_PARTY_NOTICES.md`, and
functional `Skills/*/SKILL.md` files.

## Implementation boundaries

- `Sources/UsageRings`: app, views, stores, provider clients, and window support.
- `Sources/UsageCore`: models, parsers, sanitized persistence, ring views, and SVG resources.
- `Sources/UsageRingsWidget`: sandboxed widget, timeline, and local snapshot reader.
- `Sources/UsageRingsCLI`: the `usage-rings` executable; `Skills/usage-rings-budget`: bundled skill.
- Preserve explicit monitoring consent, selected-provider polling, and per-provider
  display preferences. The CLI reads the bridge; it must not launch/enable the app,
  refresh providers, read credentials, or change settings.
- Keep credentials and private keys out of source, logs, widget data, and release
  assets. Provider CLIs own their sign-in; do not add shell execution, login flows,
  or credential-reader fallbacks. Retain the README security FAQ anchor used by the app.
- Unknown, failed, expired, or over-20-minute-old usage is unavailable, not full.
  Keep real observation times; never infer that a reset restored quota.

## Validate and install locally

Run `make check`, then `make build` for tests and embedded bundle/signature checks.
`make run` opens the built app. `make install` rebuilds, stages/verifies, replaces
`~/Applications/Usage Rings.app`, restarts only its widget, connects the Claude
helper without replacing custom status lines, and opens the app.

Before updates or distribution, choose `APP_VERSION` (`x.y.z`) and an `APP_BUILD`
higher than the installed/published build (1–9999). Unspecified local defaults are
0.1.0/build 1; do not use them to downgrade an existing installation.
`SOURCE_REVISION` must be the full current HEAD; dirty builds are marked as such.

`swift run WidgetPreview dist/widget-preview.png` renders synthetic small/medium,
light/dark fixtures without accounts or installed-widget changes. A second image
argument creates a comparison. This does not verify desktop compositing or WidgetKit scheduling.

## Package and publish

Local packaging is allowed. Keep initial GitHub releases as drafts. Uploading or
publicly publishing release assets requires explicit user approval; a successful
build/package or draft is not proof of public availability.

From a clean committed checkout, set `release_version` and `release_build` to the
chosen values, then run:

```sh
APP_VERSION="$release_version" APP_BUILD="$release_build" make build
make package-unnotarized
```

The normal distribution is **ad-hoc signed, unnotarized, macOS 26+, arm64**.
Host, widget, status-line helper, and CLI are signed; preserve Sparkle's official
nested signatures for ad-hoc builds. Packaging checks CPU/signature/entitlement
and metadata consistency, required CLI/skill resources, ZIP extraction, and a
read-only DMG mount followed by detach. It does not install or launch the app.

The versioned `dist/packages/` folder contains five stable asset names:
`usage-rings-macos.dmg`, `usage-rings-macos.zip`, `appcast.xml`,
`usage-rings-macos.json`, and `usage-rings-macos.sha256`. Publish the matching five
files together, verify their checksums and public responses, and keep the appcast
ZIP URL immutable at `releases/download/v<version>/usage-rings-macos.zip`.
Keep bundle identifiers unchanged and increase the build number for each update.
Update README's source-only feature notice when the matching release is public.

Sparkle config is in `script/sparkle-config.json`; the feed is GitHub's
`releases/latest/download/appcast.xml`. Packaging signs the final ZIP through
`generate_appcast` using the existing dedicated Keychain account
`work.hayashigoto.UsageRings` and verifies with the app's public key. Do not export
or log the private key. Creating/replacing the key requires release-operator approval;
only its public key belongs in config. Key loss can prevent installed clients updating.

`make package-draft` creates a review ZIP. Optional `make package` requires matching
Developer ID teams, hardened runtime, secure timestamps, an accepted notarization
ticket stapled with `xcrun stapler staple 'dist/Usage Rings.app'`, and Gatekeeper
assessment. `CODE_SIGN_IDENTITY` must be an installed Developer ID Application SHA-1
hash; the default `-` selects ad-hoc signing. Never remove quarantine, disable
Gatekeeper, or silently fall back from notarized to unnotarized distribution.

Without a configured Sparkle public key, `CONFIGURATION=debug make build` permits
local development with updates disabled; release builds require the public key.
Use `-SUEnableAutomaticChecks NO` when launching a configured build for testing
without changing its saved update preference.
