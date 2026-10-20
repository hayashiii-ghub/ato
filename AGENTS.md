# ato?

Keep user setup/privacy in [README.md](README.md) and repository instructions here.
Retain `LICENSE`, `THIRD_PARTY_NOTICES.md`, and functional `Skills/*/SKILL.md`;
ask before adding other documentation. Keep the app independent of cc:.

## Boundaries

- `Sources/UsageRings`: host, providers, views, stores. `UsageCore`: shared models,
  parsing, sanitized persistence, rings/resources. `UsageRingsWidget`: sandboxed
  widget. `UsageRingsCLI` and `Skills/usage-rings-budget`: read-only agent interface.
- Preserve explicit consent, selected-provider polling, and display preferences.
  The CLI must not launch/enable the app, refresh providers, read credentials, or change settings.
- Provider CLIs own sign-in. Do not add shell execution, login flows, or credential
  fallbacks. Never expose credentials/private keys in logs, caches, or assets.
- Claude/Gemini use passive status line caches. Never launch Antigravity to poll usage.
  Preserve custom status lines and unrelated settings during helper setup.
- Unknown, failed, expired, or 20-minute-old usage is unavailable. Preserve actual
  observation times, including unchanged Gemini quota data; never infer a restored
  allowance. Keep README's security FAQ anchor.
- `site/` owns the website's Bun/TypeScript source and static assets. Edit `src/`
  and `public/`, not generated `dist/`. Vercel builds `site/` and publishes `dist/`
  at `https://ato.shigoto.dev` from `main`; pull requests get previews. Retain the
  former Sites identity for old-URL redirects. Keep feature claims aligned with
  the published app release.
- The visible brand is `ato?`. Keep the `Usage Rings.app` path, bundle IDs,
  widget kind, CLI name, cache paths, and update URLs compatible with existing installs.
- Keep the old `usage-rings` repository name unused; installed update URLs rely on its GitHub redirect.

## Validate

Run `make check`, then `APP_VERSION="$app_version" APP_BUILD="$app_build" make build`.
Use `x.y.z` and build 1–9999; increase the installed/published build and never lower
its version. Unspecified development defaults are 0.1.0/build 1. `SOURCE_REVISION`
must match full HEAD; dirty builds are marked. `make run` builds/opens;
`make install` follows [README](README.md#build-from-source).

For website changes, install with `cd site && bun install --frozen-lockfile`, then
run `make site-check` and `make site-build` from the repository root, then
`cd site && bun run test`. Verify the language switch, demo controls, and
desktop/mobile layout when changing the browser code.

`swift run WidgetPreview dist/widget-preview.png` renders synthetic small/medium,
light/dark fixtures; a second image argument adds comparison. It does not verify
WidgetKit scheduling or desktop compositing. Test configured app launches with
`-SUEnableAutomaticChecks NO`, without changing the saved update preference.

## Release

- Package from a clean committed checkout after choosing version/build and running
  the checks/build above. Default: **ad-hoc signed, unnotarized, macOS 26+, arm64**.
  Use `make package-unnotarized`; `make package-draft` creates a review ZIP.
- Keep bundle IDs fixed. Sign host/widget/helpers; preserve Sparkle's official
  nested signatures for ad-hoc builds. Packaging verifies bundles and archives;
  it does not install or launch the app.
- Local packaging is allowed. Initial GitHub releases stay drafts; uploading or
  publishing assets requires explicit approval. Publish the matching five files:
  `usage-rings-macos.dmg`, `usage-rings-macos.zip`, `appcast.xml`,
  `usage-rings-macos.json`, `usage-rings-macos.sha256`. Verify checksums/public responses;
  keep ZIP URLs immutable at `releases/download/v<version>/usage-rings-macos.zip`.
  Update README's source-only notice only after public availability is verified.
- Sparkle uses `script/sparkle-config.json`, GitHub's latest-release appcast, and
  Keychain account `work.hayashigoto.UsageRings`. Packaging signs the final ZIP and
  checks its public key. Never export/log the private key; key replacement requires
  release-operator approval. Missing public key permits debug builds only.
- Optional `make package` requires matching Developer ID teams, hardened runtime,
  secure timestamps, accepted notarization with a stapled ticket, and Gatekeeper
  assessment. `CODE_SIGN_IDENTITY` is an installed Developer ID Application SHA-1
  hash (`-` means ad-hoc). Never remove quarantine, disable Gatekeeper, or silently
  fall back from notarized to unnotarized distribution.
