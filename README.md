# Usage Rings

A macOS widget for remaining Codex, Claude, Cursor, Grok, and Gemini usage.
Requires **macOS 26+ and Apple silicon**. Xcode is needed only to build from source.
This is independent of cc: and the usage providers.

Gemini, ring editing and period selection, and the CLI/skill currently require a
source/local build; these changes are not yet in the published download.

## Install or update

1. Download the latest [DMG](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
   or ZIP from [GitHub Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
2. Quit Usage Rings and drag the app into Applications. Replace the existing copy
   in its current location, including `~/Applications` if used; avoid duplicate installations.
3. Open the app, read the connection explanation, and choose **Enable AI usage**.
4. Right-click the desktop → **Edit Widgets** → **Usage Rings → AI Usage**.

The download is ad-hoc signed and **not notarized by Apple**. If macOS blocks first
launch and you trust the source, follow Apple's [per-app approval instructions](https://support.apple.com/102445)
in **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper
or remove quarantine. Fresh installation and first-launch approval on a separate
Mac have not been verified.

For checksum verification, download all five assets from the same release:
`usage-rings-macos.dmg`, `usage-rings-macos.zip`, `appcast.xml`,
`usage-rings-macos.json`, and `usage-rings-macos.sha256`. Run
`shasum -a 256 -c usage-rings-macos.sha256` in that folder. The JSON records the
source commit and build details. Checksums detect mismatches; they do not establish Apple approval.

Use **Check for Updates…** for Sparkle's signed download and relaunch flow.
Automatic update checks have their own preference, separate from usage monitoring.
Versions without Sparkle need one manual update first.

## Use

Keep the app running; it refreshes every five minutes and after waking. There is
no menu-bar icon. Closing the window keeps monitoring active; reopen the app or
click the widget for details. **Quit Usage Rings** or Command-Q stops the app.
Add it to macOS Login Items if desired.

Click a ring to select its service; drag to reorder or use the picker's left/right
buttons. Selecting an existing service swaps positions. Only the four selected
services are monitored; the defaults are Codex, Claude, Cursor, and Grok.

Choose **Auto**, **5 hours**, or **Week** in the picker. Auto uses the lowest
remaining main window. Service order and period choices are saved and shared with
the widget; changing the display period does not refresh usage. Missing, failed,
expired, or over-20-minute-old readings show **—**. Small widgets use a 2 × 2 grid;
medium widgets also show percentages. macOS controls widget refresh timing.

## Accounts

Install and sign in to the relevant apps or CLIs separately. Usage Rings starts
no login flow. Gemini here means **Antigravity CLI**, not Gemini CLI or the Gemini web app.

| Provider | Required local sign-in | Allowance |
| --- | --- | --- |
| Codex | Codex CLI 0.160.1+ with ChatGPT; the desktop app alone is insufficient | Reported main windows |
| Claude | Claude Code 2.1.251+ with Pro/Max and optional status-line setup below | 5-hour / weekly |
| Cursor | Cursor desktop session | Monthly plan percentage |
| Grok | Cursor desktop account used by Grok | Weekly |
| Gemini | Antigravity CLI 1.1.11+ (`agy`) with Google | Gemini 5-hour / weekly |

API-key billing and pooled Grok enterprise quotas are unsupported. Extra spending
allowances are not substituted for included quota.

### Optional Claude Code status line

Downloading or moving the app does not change Claude settings. To connect it,
merge this property into `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`).
Preserve other settings; compose an existing custom `statusLine` instead of replacing it.

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""
  }
}
```

For `~/Applications`, replace `/Applications` in the command with `$HOME/Applications`.
Use Claude Code once; usage arrives after an API response. To disconnect a manual
setup, remove only this helper invocation, keeping any composed custom command.
For a source-installer setup, use `python3 script/claude-statusline-setup.py --uninstall`;
that command recognizes only the form written by the installer.

## CLI and AI skill

The app includes a read-only CLI and the [usage-rings-budget skill](Skills/usage-rings-budget/SKILL.md):

```sh
"$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Use `/Applications/Usage Rings.app` when installed there. Provider names are
`codex`, `claude`, `cursor`, `grok`, and `gemini`; omit `--provider` for all services,
omit `--json` for readable text, or use `--help`.

The CLI reads the running app's snapshot, with all reported windows independent
of the ring's display period. It does not refresh, launch the app, sign in, or
change settings. Schema version `1` includes remaining percentages, observation/reset
times, and validity; unknown or expired values are `null`. Exit `0` means the read
succeeded even if readings are stale or disabled; `1` means no valid snapshot;
`2` means invalid arguments.

`alerts` contains fresh main windows strictly below **20%**. Add `--threshold 10`
for a different threshold on that call. Alerts include time until reset; the CLI
saves no notice history. The skill asks how to continue and follows your answer,
without automatically splitting or stopping tasks. Say “tell me at 10%” to change
its threshold for the conversation. It checks only before work and at natural
pauses; it has no background monitor. Percentages cannot predict exact tasks or tokens.

The bundled skill is at `Contents/Resources/Skills/usage-rings-budget/SKILL.md`.
Ask your assistant to read it or copy its folder into the assistant's skill directory.
App installation does not add it to assistant settings or change shell PATH.

## Security and data FAQ

**What is read or sent?** After explicit enablement, Codex uses the official
[local App Server](https://learn.chatgpt.com/docs/app-server#authentication-endpoints)
and Gemini uses Antigravity CLI's read-only quota command. Those CLIs manage their
existing authentication and may update their own local state. Usage Rings reads
Cursor's session database read-only for Cursor/Grok HTTPS requests to `cursor.com`
and `api2.cursor.sh`; credentials stay in memory and redirects are rejected.
Claude uses official [status-line output](https://code.claude.com/docs/en/statusline#rate-limit-usage),
without reading Claude credentials or making Claude API requests. The app does not
read conversation files, collect analytics, or send usage to its developer.
Cursor/Grok endpoints are internal; their compatibility or permitted use may change.

**What is stored or exposed?** Only provider status, percentages, observation/reset
times, and display choices are shared over `127.0.0.1:52388/v1/usage`. Other local
processes can read this bridge; its header is not authentication. It has no LAN
listener or credential endpoints. The widget keeps a cache in its own container.
Claude's separate helper stores the two main windows and hashed response markers
in `~/Library/Caches/Usage Rings/`, not full input or conversation/workspace paths.
Cache files use owner-only permissions; there is no usage history or cloud sync.
Passing CLI output to an AI shares these usage values with that conversation service.
Update checks contact GitHub separately and do not include provider credentials or usage.

**What happens when monitoring is off?** Before consent, including upgrades from
a pre-consent version, the app does not read provider data or start provider CLIs.
Turning off **Show AI usage** stops future polling and clears current display data. An in-flight
request can still finish, and macOS may retain the widget's cached display until
its next update. The optional Claude helper remains connected until separately removed.
A reset or stale reading never implies a restored allowance; use a fresh reading.

## Build from source

With Xcode installed, run `make check`, then `make install`. It installs into
`~/Applications` and connects Claude's helper if no custom command exists; an
existing custom status line is preserved. For updates, choose version/build
metadata as described in [AGENTS.md](AGENTS.md), which also covers checks and packaging.

Provider marks and dependency licenses are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
