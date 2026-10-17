# ato?

Remaining Codex, Claude, Cursor, Grok, and Gemini usage on **macOS 26+ / Apple silicon**.

Previously Usage Rings. The app folder and `usage-rings` command keep their original
names so existing helper settings and updates continue to work.

## Install and use

1. Download the [DMG](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
   or ZIP from [Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
2. Quit ato? and replace the app in its existing Applications folder.
3. Open it, read the connection explanation, and choose **Enable AI usage**.
4. Desktop → **Edit Widgets** → **ato? → AI Usage**.

The app is ad-hoc signed, **not notarized**. If macOS blocks it and you trust the
source, use Apple's [per-app approval](https://support.apple.com/102445).
Use **Check for Updates…** for later updates. Download verification:
save all five release assets together, then `shasum -a 256 -c usage-rings-macos.sha256`.

Select a ring for details; **Change service** replaces it or swaps existing selections. Drag to reorder.
Only the four selected services are monitored. **Auto** shows the lowest remaining
main window; **5 hours** and **Week** select a period. Choices also apply to the widget.
Missing, failed, expired, or 20-minute-old readings show **—**.

Monitoring refreshes every five minutes and after waking. Closing the window keeps
it running; **Quit ato?** stops future polling, and reopening resumes it.
An in-flight request may finish. Widget updates follow macOS scheduling.

## Accounts

Sign in separately; ato? starts no login flow. API-key billing and pooled
Grok enterprise allowances are unsupported.

| Service | Required sign-in |
| --- | --- |
| Codex | Codex CLI 0.160.1+ with ChatGPT; desktop sign-in alone is insufficient |
| Claude | Claude Code 2.1.251+ with Pro/Max and the optional helper below |
| Cursor | Cursor desktop |
| Grok | Cursor desktop account used by Grok |
| Gemini | Antigravity CLI 1.1.11+ (`agy`) with Google, not Gemini CLI |

### Claude helper

Source installation connects the helper unless a custom status line exists.
For downloads, merge this into `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`)
without replacing other settings or an existing custom command:

```json
{"statusLine":{"type":"command","command":"\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""}}
```

For user Applications, replace `/Applications` with `$HOME/Applications`. Usage arrives with Claude Code activity.
To disconnect, remove only this invocation; remove source-installer setup
with `python3 script/claude-statusline-setup.py --uninstall`.

## CLI and AI skill

```sh
"$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Adjust the app path as needed; use `--help` for options. The CLI reads the running
app without refreshing or changing settings. For agent notices, read or copy the
bundled [skill](Skills/usage-rings-budget/SKILL.md) from
`Contents/Resources/Skills/usage-rings-budget`. Installation does not configure assistants.

## Security and data FAQ

**Reads:** Codex/Gemini use their CLIs, which manage authentication/cache.
Cursor/Grok read Cursor's session for HTTPS requests to `cursor.com` and `api2.cursor.sh`;
redirects are rejected, and these internal endpoints may change. Claude reads only
the helper's usage cache. No conversations, analytics, or usage go to the developer.

**Local data:** Other local processes can read usage, times, and display settings at
`127.0.0.1:52388/v1/usage`; no credentials are exposed. The widget cache and Claude's
`~/Library/Caches/Usage Rings/` cache are owner-only; there is no history/cloud sync.
Claude session identifiers are hashed. Sharing CLI output with an AI shares those
values with its service. Update checks contact GitHub separately.

**Consent:** No provider reads occur before consent; an older saved Off choice requires
consent again. Disconnect the Claude helper separately when stopping. macOS may retain
the widget cache. A reset never implies a full allowance.

## Build from source

With Xcode installed, set `app_version` (`x.y.z`) and `app_build` (1–9999) for the
build. Keep the version at least as high as installed and increase the build number.

```sh
make check
APP_VERSION="$app_version" APP_BUILD="$app_build" make install
```

This builds/verifies, replaces `~/Applications/Usage Rings.app`, restarts its widget,
and opens the app. Custom Claude status lines are preserved. Development and
release instructions: [AGENTS.md](AGENTS.md). Licenses: [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Website

The [public website](https://ato.hayashiii-gpt.chatgpt.site) is hosted on Sites.
Its source lives in [`site/`](site), using Bun and TypeScript with static HTML/CSS.
Python is used only by the app's setup, packaging, and tests.

```sh
cd site
bun install --frozen-lockfile
bun run dev
```

From the repository root, `make site-check` checks types and `make site-build`
generates `site/dist/` for static hosting. Edit `site/src/` and `site/public/`;
the generated `dist/` is not tracked. Website commands are separate from the
Swift app's build and installation commands.
