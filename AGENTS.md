# ato?

Keep user guidance in `README.md` and repository procedures here. Retain required licenses and functional `Skills/*/SKILL.md`; ask before adding other documentation. Keep ato? independent of cc:.

## Boundaries

- `Sources/UsageRings`: host app; `UsageCore`: models/providers/cache; `UsageRingsWidget`: sandboxed widget; `UsageRingsCLI` and `Skills/usage-rings-budget`: read-only agent interface.
- Preserve consent, selected-provider polling, display settings, and original observation times. Unknown, failed, expired, or 20-minute-old readings are unavailable; resets do not imply restored allowance.
- Antigravity provides no observation timestamp/sequence. Filter the current value and latest 256 fingerprints without stopping new input at capacity; evicted replays may appear new.
- Provider CLIs own sign-in. Never add shell/login/credential fallbacks, expose secrets, or launch Antigravity to poll. Claude/Gemini read passive status-line caches. Preserve custom status lines.
- AI Tools setup belongs to the host. Bundle/sign `UsageRingsBudgetHook`; merge only owned hooks and preserve edited skills, unrelated settings, status lines, and client trust. Setup must not enable monitoring. The CLI must not launch the app, refresh providers, read credentials, or change settings.
- Visible brand: `ato?`. Preserve `Usage Rings.app`, bundle IDs, widget kind, CLI/cache paths, and update URLs. Leave the old `usage-rings` repository name unused so installed GitHub redirects work.
- `site/src/` and `site/public/` are website sources; do not edit generated `dist/`. Vercel publishes `site/dist/` at `https://ato.shigoto.dev` from `main`; PRs get previews. Preserve former Sites redirect identity and README anchors linked from the app/site. Claims must match the published release.

## Development

Requires Xcode. Set `app_version=x.y.z` and `app_build=1–9999`, keeping the version at least as high as installed/published and increasing its build number:

```sh
make check
APP_VERSION="$app_version" APP_BUILD="$app_build" make build
```

`make run` builds/opens; `APP_VERSION="$app_version" APP_BUILD="$app_build" make install` replaces `~/Applications/Usage Rings.app`, restarts its widget, and opens it. Source installation preserves custom Claude/Antigravity status lines. `SOURCE_REVISION` must match full HEAD; dirty builds are marked.

Website: use Bun 1.4.2; run `cd site && bun install --frozen-lockfile`, then root `make site-check` and `make site-build`, then `cd site && bun run test`. `bun run dev` previews the site. Browser changes require desktop/mobile, language-switch, and demo-control checks.

`swift run WidgetPreview dist/widget-preview.png` renders synthetic fixtures, not WidgetKit scheduling/compositing. Launch configured test apps with `-SUEnableAutomaticChecks NO` without changing saved preferences. After editing `Assets/AppIcon.svg`, run `swift run IconAssets` to regenerate native/web icons.

## Release

- Use a clean committed checkout and validated version/build. `make package-unnotarized` packages ad-hoc signed, unnotarized, macOS 26+/arm64 builds; `make package-draft` creates a review ZIP. Packaging does not install/launch.
- Preserve bundle IDs and Sparkle's nested signatures. Sign host, widget, and helpers. Local packaging is allowed; initial GitHub releases stay drafts, and upload/publication requires explicit approval.
- Publish matching `usage-rings-macos.{dmg,zip,json,sha256}` and `appcast.xml`; verify checksums/public responses. Keep versioned ZIP URLs immutable. Packaging signs the final ZIP using `script/sparkle-config.json` and Keychain account `work.hayashigoto.UsageRings`; never export/log the private key. Key replacement requires operator approval; a missing public key permits debug builds only.
- `make package` additionally requires matching Developer ID teams, hardened runtime, secure timestamps, accepted/stapled notarization, and Gatekeeper assessment. `CODE_SIGN_IDENTITY` is the installed Developer ID SHA-1 (`-` means ad-hoc). Never remove quarantine, disable Gatekeeper, or silently downgrade notarized distribution.
