# ato?

AI account usage in a macOS app and desktop widget. **macOS 26+ / Apple silicon.**
[Website](https://ato.shigoto.dev) · [Download](https://github.com/hayashiii-ghub/ato/releases/latest)

## Install and use

Install the DMG or ZIP, open ato?, and choose **Enable** after reading the connection explanation.
Add the widget from **Edit Widgets → ato? → AI Usage**. Update through **Updates…**.
The app is ad-hoc signed, not notarized; use Apple's [per-app approval](https://support.apple.com/102445) only if you trust the download.

Only selected services are monitored. Closing the window keeps polling; **Quit** stops it.
Missing, failed, expired, or 20-minute-old readings show **—**. Widget refresh follows macOS scheduling.
The former `Usage Rings.app` name and `usage-rings` command remain for compatibility.

## Accounts

Sign in separately; ato? does not start login flows. API-key billing and pooled Grok enterprise allowances are unsupported.

| Service | Sign-in |
| --- | --- |
| Codex | Codex CLI 0.160.1+ with ChatGPT; desktop sign-in alone is insufficient |
| Claude | Claude Code 2.1.251+ with Pro/Max and its status-line helper below |
| Cursor / Grok | Cursor desktop account |
| Gemini | Antigravity CLI 1.1.11+ (`agy`) with Google and its helper below; Gemini CLI is unsupported |

ato? v0.2.8 supports Cursor's encrypted sign-in storage. If Cursor or Grok asks
for access, choose **Allow Cursor Access…** in ato? and approve the macOS Keychain
prompt. **Always Allow** keeps permission after reopening; an app update may ask
again because the app is ad-hoc signed. **Allow Once** lasts for the current app
session. Automatic refresh never opens a Keychain prompt; denied access shows
**—** until you choose to retry.
ato? also uses Cursor's reported allowance period and reset time: monthly
for legacy plans, or weekly for current shared-allowance plans. A weekly reading
does not reuse monthly breakdowns or a monthly billing reset.

### Claude helper

Merge into `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`), preserving other settings and custom status lines:

```json
{"statusLine":{"type":"command","command":"\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""}}
```

### Gemini helper

Merge into `~/.gemini/antigravity-cli/settings.json`, preserving other settings and custom status lines:

```json
{"statusLine":{"type":"command","command":"\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\" --provider gemini","stack_with_default":true}}
```

Use the actual app path, including `$HOME/Applications` if applicable. Both helpers receive readings through CLI activity;
polling alone creates no new observation. Disconnect by removing only the helper invocation.
Explicitly disabled limits, including their cached values, are not shown.

## CLI and AI skill

In **AI Tools**, choose **Set Up** or **Update** for Codex, Claude Code, Cursor, or Antigravity.
This installs the read-only CLI, [skill](Skills/usage-rings-budget/SKILL.md), and budget hook while preserving unrelated settings and edited files.
In Codex CLI, approve the hook through `/hooks` and start a new session. Setup does not enable monitoring or connect status-line helpers.

```sh
"/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Use `--help` for options. The CLI reads the running app without refreshing providers or changing settings.
Budget notices do not interrupt model requests; unavailable data stays quiet.

## Security and data FAQ

**Reads:** Codex uses its CLI, which manages authentication/cache.
Cursor/Grok read Cursor's session for HTTPS requests to `api2.cursor.sh`
(older builds also use `cursor.com`).
For Cursor's encrypted storage, ato? reads only the `Cursor Safe Storage`
Keychain item, with interactive permission requested only by **Allow Cursor Access…**.
The derived decryption key stays only in the host app's memory until it quits;
neither the key nor decrypted sign-in is written to disk. No Keychain item or
Cursor setting is changed by ato?; macOS manages the permission you grant.
Redirects are rejected, and these internal endpoints may change. Claude/Gemini read
only their helpers' usage caches; ato? does not launch Antigravity. No conversations,
analytics, or usage go to the developer.

Other processes on the same Mac can read usage, times, and display settings at `127.0.0.1:52388/v1/usage`, without credentials.
Helper/widget caches are owner-only; sharing CLI output with an AI shares those values with its service.
Update checks contact GitHub. No provider reads occur before consent.

Antigravity supplies no observation timestamp. ato? filters the current value and latest 256 distinct readings;
older replays can appear new. A reset never implies a full allowance.

## Build from source

See [AGENTS.md](AGENTS.md#development) for build, installation, website, and release commands.
[MIT](LICENSE) · [Third-party licenses](THIRD_PARTY_NOTICES.md)
