# ato?

AI account usage in a macOS app and desktop widget. **macOS 26+ / Apple silicon.**
[Website](https://ato.shigoto.dev) · [Download](https://github.com/hayashiii-ghub/ato/releases/latest)

## Install and use

Install the DMG or ZIP, open ato?, and choose **Enable** after reading the connection explanation.
Add the widget from **Edit Widgets → ato? → AI Usage**. Update through **Updates…**.
The app is ad-hoc signed, not notarized; use Apple's [per-app approval](https://support.apple.com/102445) only if you trust the download.

Only selected services are monitored. Closing the window keeps polling; **Quit** stops it.
Missing, failed, expired, or 20-minute-old readings show **—**. Widget refresh follows macOS scheduling.
After an app update, ato? restarts its own widget once so an older running copy cannot block new readings.
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

Use Claude Code in a terminal with this helper connected. After a response, refresh ato? to read its
updated usage. Refresh only rereads saved usage; it does not request a new reading from Claude.

Sessions in the Claude desktop app's Code tab have been [reported not to run the status-line helper](https://github.com/hayashiii-ghub/ato/issues/29).
Use a terminal session to update ato?.

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
Budget notices use below-20% and below-10% stages. At 20%, the AI continues the authorized task while avoiding unnecessary exploration and repeated checks. At 10%, it prioritizes required verification and organizing handoff information, without skipping required checks, stopping automatically, or switching assistants. Unavailable data stays quiet.

In **Notifications**, enable **Low usage alerts** to allow macOS notifications at 20% and 10% remaining for each main allowance in your rings. Alerts and sounds start off; **Play a sound** is optional. Each stage is sent once per allowance/reset period, including across app restarts. Old or unavailable readings do not trigger alerts. Monitoring must be enabled and ato? must be running; alerts follow its five-minute refresh, and macOS controls their presentation. Clicking a notification opens ato?.
When macOS asks, allow notifications in its permission dialog. If access was denied before, use **Open Notification Settings…** to change it.

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

## Cloudflare website preview

Production remains on Vercel. The existing `site/` build targets `ato-site-preview` by default and `ato-site` with `--mode production`. The Cloudflare configuration attaches no custom domains or routes. The app and update feeds are unchanged.

Use Node.js 24.22.1, Bun 1.4.2, and `dev-environment:0.1.1`. `site/package.json` and `bun.lock` pin cf `1.0.0-beta.28` and Wrangler `4.158.0`. cf runs on Node.

For first use, follow `/Users/hayashi/work/projects/dev-environment/README.md` to create and initialize `ato-cf-preview-home` and `ato-cf-preview-node-modules` with UID/GID `501:20`. Run from this repository's root:

```sh
container run -d --name ato-cf-preview-dev -w /workspace/site -e HOME=/home/dev \
  -v "$PWD:/workspace" -v ato-cf-preview-home:/home/dev \
  -v ato-cf-preview-node-modules:/workspace/site/node_modules \
  -p 127.0.0.1:8796:8796 dev-environment:0.1.1 sleep infinity
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun install --frozen-lockfile
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun run check
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun run test
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun run cf:check
container exec -it -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun run cf:dev
```

Preview at `http://localhost:8796`. The website builds into `site/dist/`, Cloudflare Build Output into `site/.cloudflare/output/v0/`, and dependencies/cache stay in the named volumes. Stop the dev server with Ctrl+C, then `container stop ato-cf-preview-dev`. Resume with `container start ato-cf-preview-dev`.

Authenticate and deploy on the Mac. cf `1.0.0-beta.28` is installed globally in the Mac's existing Node.js 24.22.1 environment; the default Node.js environment is unchanged. Sign in with `fnm exec --using=24.22.1 cf auth login`, then run `fnm exec --using=24.22.1 cf deploy --prebuilt --worker ato-site-preview` from `site/` to publish a default build to the preview Worker. Do not copy credentials into the container.

Build and dry-run a production candidate with `container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.2 bun run cf:check:production`. After review, publish it from the Mac's `site/` directory with `fnm exec --using=24.22.1 cf deploy --prebuilt --mode production --worker ato-site --no-provision`. The candidate is live at [ato-site.hayashigoto.workers.dev](https://ato-site.hayashigoto.workers.dev/). `ato.shigoto.dev` is still served by Vercel; publishing the candidate and attaching the custom domain are separate steps.

Build Output is shared across modes and replaced by the last build. In cf beta.28, omitting `--mode` uses the mode recorded in that output; it does not select the preview target. Before a prebuilt command, inspect `buildContext.mode` in `.cloudflare/output/v0/config.json` and `name` in `.cloudflare/output/v0/workers/default/worker.config.json`, then pass `--mode production --worker ato-site` for production output. Rebuild with `cf:check` before publishing to the preview Worker again. DNS cutover, production deployment, and disabling Vercel are separate steps.
