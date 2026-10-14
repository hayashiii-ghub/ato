# Usage Rings

Personal macOS widget for remaining Codex, Claude, Cursor, and Grok Bot usage.
Requires macOS 26+; Xcode is only needed to build from source. This is independent of cc:.

## Install or update

Download the latest [DMG](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
or browse [GitHub Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
Requires **macOS 26+ and Apple silicon**; Xcode is not needed to use the download.

Open the DMG, quit any running Usage Rings, and drag the app to Applications.
When updating, replace the existing copy in its current location instead of
installing a second copy. Open the installed app, then right-click the desktop,
choose **Edit Widgets**, and add **Usage Rings → AI Usage**. Read the connection
explanation and choose **Enable AI usage** when you want to connect. First launch
does not read account credentials, start Codex, or contact usage providers.
Upgrading from an earlier version also requires this explicit enable action;
the old on/off preference alone does not authorize the new connection method.
Keep the app running;
it refreshes every five minutes and after waking from sleep. Choose
**Check for Updates…** in the app to use the standard Sparkle
update window. It can download a signed update and relaunch the app to install
it. Sparkle asks whether to check for updates automatically; enabling usage
monitoring does not enable that preference. Add the app to Login Items if desired.

Usage Rings runs without a menu-bar icon. Closing its window keeps usage updates
running. Reopen the installed app or click its widget to view details. Choose
**Quit Usage Rings** in the app window, or press Command-Q while it is active,
to stop the app.

Previously published versions do not contain this updater. Install the first
release that includes it manually once, then use in-app updates for later
releases. The updater requires a published signed update feed; see
[Distribution](DISTRIBUTION.md#in-app-updates) for release preparation.

The app is **not notarized by Apple**. macOS may block the first launch. If you
trust the source, follow Apple's [per-app approval instructions](https://support.apple.com/102445)
under **System Settings → Privacy & Security → Open Anyway**. See
[DISTRIBUTION.md](DISTRIBUTION.md) for checksums, installation limits, and optional
Claude Code status-line setup. The download does not change that setup automatically.

To build and install from source instead, use `make install` with Xcode installed.
It installs to `~/Applications` and connects Claude Code's status line when no
custom command exists. Existing custom commands are preserved and must be composed
manually. Paid Apple Developer membership is not required.

## Distribution

`make package-unnotarized` produces the DMG, ZIP, Sparkle appcast with the ZIP’s signature, build
manifest, and checksums for this release route. `make package-draft` creates a review ZIP. The optional
`make package` command requires Developer ID signing and notarization; those are
not part of the current release plan. See [DISTRIBUTION.md](DISTRIBUTION.md).

## Accounts

The app uses sign-ins already stored on this Mac after you explicitly enable it.
Turn off **Show AI usage** to stop polling. After you have accepted the current
connection explanation, that choice is remembered across launches; an off choice
also stays off. The app never starts a new login for you.

| Provider | Local sign-in | Ring |
| --- | --- | --- |
| Codex | Codex CLI 0.160.1+ signed in with ChatGPT | Lowest remaining main window |
| Cursor | Cursor desktop session | Reported monthly plan percentage |
| Claude | Claude Code status-line output (v2.1.251+, Pro/Max) | Lowest remaining 5-hour / weekly window |
| Grok Bot | Same Cursor desktop account used by Grok Bot | Weekly allowance |

Codex uses the official local [Codex App Server](https://learn.chatgpt.com/docs/app-server#authentication-endpoints)
over stdio, with `account/rateLimits/read` and `account/rateLimits/updated`. Install
the official Codex CLI separately and sign in with ChatGPT using its normal login
flow. A Codex desktop app alone is not a supported substitute for that CLI.
The app checks fixed CLI locations: `/opt/homebrew/bin/codex`,
`/usr/local/bin/codex`, and `~/.local/bin/codex`; it does not execute a shell or
search arbitrary shell paths. Version 0.160.1 is the verified minimum.
Usage Rings does not directly read Codex's auth file or send Codex credentials to
an internal HTTP endpoint, and does not fall back to the old method. Missing or
unsupported CLIs show setup guidance; missing ChatGPT sign-in shows sign-in guidance.
The official CLI owns its existing login, and may refresh it or write its local
cache/state as part of its normal operation. Usage Rings does not request login,
logout, account changes, agent turns, or tool execution.

Cursor and Grok Bot still use internal endpoints, so provider changes may require
updates. Their tokens are not refreshed by Usage Rings. API-key billing accounts
and pooled Grok Bot enterprise quotas are unsupported.

Claude uses the official [status-line output](https://code.claude.com/docs/en/statusline#rate-limit-usage).
Use Claude Code once after connecting; usage appears after an API response. The helper
stores only the two main usage windows, receipt time, and hashed response markers under
`~/Library/Caches/Usage Rings/`. It does not store the session payload, conversation paths,
or workspace metadata. Usage Rings reads no Claude credentials or Keychain items and
makes no Claude API requests. Repeated status-line UI events do not refresh the age of
an old reading. Without new Claude Code activity, the ring becomes unavailable after
20 minutes or when a reported reset passes. App refresh reads the cache every five minutes;
use **Refresh** to pick it up immediately.

To disconnect only this integration while keeping other Claude settings:

```sh
python3 script/claude-statusline-setup.py --uninstall
```

Login credentials stay out of the repository, logs, and widget data. Usage requests go to the matching provider endpoints. Update checks and downloads
use the GitHub release feed; Sparkle verifies downloaded archives before installing. The sandboxed widget reads sanitized values
from the loopback-only `127.0.0.1:52388/v1/usage` bridge, then caches them in its own
container. Other local processes can read those usage values; there is no LAN listener.

macOS controls widget updates. Missing/failed readings, values older than 20 minutes,
and passed reset times display **—** until a new reading arrives. Extra spending
allowances are not substituted for included quota percentages.

The small widget uses a 2 × 2 grid of rings without percentage labels; VoiceOver
still reads each provider's remaining percentage. Missing or expired readings
show a **—** badge on the small ring. The medium widget keeps percentages below
the rings.

## Security and data FAQ

### Does Usage Rings send data to its developer?

No. The app has no developer-operated collection server or analytics. After
explicit enablement, Codex usage comes from the official local Codex CLI App
Server, which handles communication with OpenAI. Cursor and Grok Bot use
authenticated HTTPS requests to `cursor.com` and `api2.cursor.sh` respectively,
using the local Cursor session. These requests contain the credentials required
by that service; redirects are rejected. Claude usage is read locally from
official Claude Code status-line output; Usage Rings makes no Claude API requests.
Update checks and downloads contact GitHub separately from usage monitoring.
Sparkle manages its own update-check preference; it does not send provider credentials
or usage readings with these requests.

### Does it read my login details or conversations?

For Codex, the app asks the official CLI for account mode and rate limits over
local stdio; it does not directly read Codex credentials. The CLI manages its
existing login and can refresh its authentication and write cache/state/log files.
Usage Rings never invokes login or logout; it does not create a new sign-in.
For Cursor and Grok Bot, it reads Cursor's local session database in read-only mode. These
credentials are used in memory for the matching service's request and are not
copied into the widget cache or logs. Usage Rings does not refresh Cursor tokens
or change your accounts. It does not read Claude credentials, Keychain items, or conversation
files. The optional Claude helper receives status-line input, but saves only the
two main usage windows, receipt time, and hashed response markers—not the full
input, conversation paths, or workspace metadata.

### What is saved, and who can see it?

Usage Rings itself caches display data on this Mac: provider status, usage percentages,
reset times, and update times. Claude's helper saves its separate local cache
under `~/Library/Caches/Usage Rings/`. Cache files use owner-only permissions.
There is no Usage Rings usage-history database or cloud sync. The separate Codex
CLI can maintain its own local state, cache, and logs.

The app shares display data with the widget over `127.0.0.1:52388`, which is
accessible only on this Mac, not over the LAN. It does not expose credentials.
Other processes on the same Mac can read this bridge; its request header is not
authentication, and it is not a security boundary against other local apps.

### What happens when I turn off Show AI usage?

Before initial enablement (including migration from an older version), the host
app does not read provider credentials or the Claude usage cache, start Codex,
or contact usage providers. The local widget bridge returns empty display data.
macOS may briefly retain the widget's previously cached display until it updates.

Turning off **Show AI usage** stops scheduled polling and wake refreshes, clears
its current display data, and asks macOS to refresh the widget. It does not delete your sign-ins or
guarantee that an already-started request stops immediately. The local bridge
remains running with empty data, and the widget may retain its cache until macOS
updates it. Turning this setting off does not disconnect the optional Claude
status-line helper; use the disconnect command above to stop that integration.

### Is this an official integration, and are the numbers always current?

Usage Rings is an independent project, not endorsed by the providers. Codex uses
documented official App Server rate-limit operations; Claude uses documented
status-line output. Cursor and Grok Bot still use internal endpoints whose
compatibility or permitted use may change; provider approval is not established.
The app normally refreshes every five minutes, and macOS
controls widget updates. Missing or failed readings, readings older than 20
minutes, and passed reset times show **—** instead of an invented percentage.

### Why does macOS show a warning when opening the download?

The current download is not notarized by Apple and is not distributed through the
App Store. Download from this repository's Releases page and check the published
checksums. Checksums help detect a mismatched download; they do not establish
Apple approval or prove the app is safe. If you trust the source, follow Apple's
per-app approval instructions linked above. Never disable Gatekeeper globally.

## Development

```sh
make check   # parser, credential, snapshot, and bridge tests
make build   # build and verify signed app + widget bundles
make run     # run from dist without installing
swift run WidgetPreview dist/widget-preview.png # synthetic small/medium, light/dark fixture sheet
swift run WidgetPreview dist/widget-comparison.png dist/widget-before.png # compare with a saved baseline
```

`WidgetPreview` renders the production SwiftUI rings without starting the app,
reading credentials, contacting providers, or changing installed widgets. It
covers normal, missing, expired, and high/exhausted usage. The sheet uses fixed
170 × 170 and 360 × 170 point canvases; it does not emulate WidgetKit's desktop
compositing or the system's widget update scheduling.

### Source layout

- `Sources/UsageRings`: app entry point, `Views`, `Stores`, `Services`, and window `Support`.
- `Sources/UsageCore/Models`: shared usage values and freshness rules.
- `Sources/UsageCore/Parsing`: provider responses and official Claude status-line input.
- `Sources/UsageCore/Persistence`: sanitized snapshot and Claude status-line caches.
- `Sources/UsageCore/Views`: shared ring composition and provider marks; SVG assets stay in `Resources`.
- `Sources/UsageRingsWidget/Timeline`: timeline entries, preview data, and expiry scheduling.
- `Sources/UsageRingsWidget/Views`: WidgetKit view configuration; the snapshot reader stays at the target root.
- `Tools/WidgetPreview`: offline visual fixture renderer, excluded from the installed app bundle.

The Grok Bot mark is a transparent monochrome character glyph sized to match the
other provider marks. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sources.
