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

Sign in separately. ato? does not start login flows. API-key billing is unsupported.

The Grok Build and direct Antigravity connections below apply to builds from current source.
The published v0.3.3 app also supports Cursor monitoring and uses the Cursor Grok allowance and an Antigravity status-line helper.

| Service | Sign-in |
| --- | --- |
| Codex | Codex CLI 0.160.1+ with ChatGPT; desktop sign-in alone is insufficient |
| Claude | Claude Code 2.1.251+ with Pro/Max and its status-line helper below |
| Grok | A Grok Build subscription signed in with `grok login` |
| Gemini | Antigravity CLI (`agy`) with a Google account. Gemini CLI and Application Default Credentials are unsupported |

Current source builds use a full circle for one allowance and split the circle for two.
When both 5-hour and weekly allowances are present, 5h is on top and Week is on the bottom.
If a refresh temporarily fails, the ring keeps its last known shape and hides unavailable values.

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

Current source builds query Antigravity directly. If prompted in ato?, choose **Allow Antigravity Access…**.
Use `agy` to renew an expired sign-in. The Gemini ring shows the standard Gemini allowance.
Other model groups appear in its details when available. Existing status-line commands can stay in place.

<details>
<summary>Gemini status line for version 0.3.3</summary>

Merge into `~/.gemini/antigravity-cli/settings.json`, preserving other settings and status lines.

```json
{"statusLine":{"type":"command","command":"\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\" --provider gemini","stack_with_default":true}}
```

Use the actual app path and run `agy` to receive a reading.

</details>

## CLI and AI skill

In **AI Tools**, choose **Set Up** or **Update** for Codex, Claude Code, Grok Build (current source builds), or Antigravity.
This installs the read-only CLI, [skill](Skills/usage-rings-budget/SKILL.md), and budget hook while preserving unrelated settings and edited files.
In Codex CLI, approve the hook through `/hooks` and start a new session. Grok Build runs the hook only in folders it trusts (`/hooks-trust`). Setup does not enable monitoring or connect status-line helpers. Existing Cursor Agent integrations can be disconnected from AI Tools.

```sh
"/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Use `--help` for options. The CLI reads the running app without refreshing providers or changing settings.
Budget notices use below-20% and below-10% stages. At 20%, the AI continues the authorized task while avoiding unnecessary exploration and repeated checks. At 10%, it prioritizes required verification and organizing handoff information, without skipping required checks, stopping automatically, or switching assistants. Unavailable data stays quiet.

In **Notifications**, enable **Low usage alerts** to allow macOS notifications at 20% and 10% remaining for each main allowance in your rings. Alerts and sounds start off; **Play a sound** is optional. Each stage is sent once per allowance/reset period, including across app restarts. Old or unavailable readings do not trigger alerts. Monitoring must be enabled and ato? must be running; alerts follow its five-minute refresh, and macOS controls their presentation. Clicking a notification opens ato?.
When macOS asks, allow notifications in its permission dialog. If access was denied before, use **Open Notification Settings…** to change it.

## Security and data FAQ

**Reads:** Codex uses its CLI, which manages authentication/cache.
Current source builds request Grok Build billing from `cli-chat-proxy.grok.com` using the CLI's saved sign-in.
In current source builds, Gemini reads Antigravity's unexpired access token from the CLI file or the
`gemini` / `antigravity` Keychain item. It queries Google's
`daily-cloudcode-pa.googleapis.com` and `cloudcode-pa.googleapis.com`.
Grok Build and Antigravity manage their sign-ins and renewal. ato? does not launch these CLIs,
write their credentials, or request interactive Keychain access during polling.
Redirects are rejected. Claude reads its helper's local usage cache. No conversations,
analytics, or usage go to the developer.

Other processes on the same Mac can read usage, times, and display settings at `127.0.0.1:52388/v1/usage`, without credentials.
Helper/widget caches are owner-only; sharing CLI output with an AI shares those values with its service.
Update checks contact GitHub. No provider reads occur before consent.

A reset never implies a full allowance.

## Build from source

See [AGENTS.md](AGENTS.md#development) for build, installation, website, and release commands.
[MIT](LICENSE) · [Third-party licenses](THIRD_PARTY_NOTICES.md)

## Cloudflare website deployment

The existing `site/` build targets `ato-site-preview` by default and `ato-site` with `--mode production`. Only the production configuration declares `ato.shigoto.dev`; previews have no custom domain. Validate the actual DNS and HTTPS cutover separately from configuration and build success. The app and update feeds are unchanged.

Use Node.js 24.22.1, Bun 1.4.4, and `dev-environment:0.1.1`. `site/package.json` and `bun.lock` pin cf `1.0.0-beta.28` and Wrangler `4.158.0`. cf runs on Node.

For first use, follow `/Users/hayashi/work/projects/dev-environment/README.md` to create and initialize `ato-cf-preview-home` and `ato-cf-preview-node-modules` with UID/GID `501:20`. Run from this repository's root:

```sh
container run -d --name ato-cf-preview-dev -w /workspace/site -e HOME=/home/dev \
  -v "$PWD:/workspace" -v ato-cf-preview-home:/home/dev \
  -v ato-cf-preview-node-modules:/workspace/site/node_modules \
  -p 127.0.0.1:8796:8796 dev-environment:0.1.1 sleep infinity
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun install --frozen-lockfile
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun run check
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun run test
container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun run cf:check
container exec -it -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun run cf:dev
```

Preview at `http://localhost:8796`. The website builds into `site/dist/`, Cloudflare Build Output into `site/.cloudflare/output/v0/`, and dependencies/cache stay in the named volumes. Stop the dev server with Ctrl+C, then `container stop ato-cf-preview-dev`. Resume with `container start ato-cf-preview-dev`.

Authenticate and deploy on the Mac. cf `1.0.0-beta.28` is installed globally in the Mac's existing Node.js 24.22.1 environment; the default Node.js environment is unchanged. Sign in with `fnm exec --using=24.22.1 cf auth login`, then run `fnm exec --using=24.22.1 cf deploy --prebuilt --worker ato-site-preview` from `site/` to publish a default build to the preview Worker. Do not copy credentials into the container.

Build and dry-run production with `container exec -w /workspace/site ato-cf-preview-dev bunx --package bun@1.4.4 bun run cf:check:production`. Before any production deployment, confirm that the existing DNS is preserved, the zone is active, and HTTPS is ready. `cf deploy` also applies configured custom domains, so do not run it before these checks.

After readiness checks and review, update code and domains from the Mac's `site/` directory with `fnm exec --using=24.22.1 cf deploy --prebuilt --mode production --worker ato-site --no-provision`. `--no-provision` only prevents missing binding resources from being created; it does not prevent domain changes. To update only domain settings on an already uploaded Worker, use `fnm exec --using=24.22.1 cf workers triggers deploy --prebuilt --mode production --worker ato-site` instead, after the same readiness checks. Then verify both [workers.dev](https://ato-site.hayashigoto.workers.dev/) and `https://ato.shigoto.dev`.

After those readiness checks, enable Cloudflare Builds production publishing for `main` only. Set the root directory to `site/`, Node.js to 24.22.1, Bun to 1.4.4, the build command to `bun run check && bun run test && bun run cf:build:production`, and the deploy command to `node node_modules/cf/bin/cf deploy --prebuilt --mode production --worker ato-site`. Once enabled, main pushes run checks and publish; other branches do not publish production. The manual Mac commands above remain available.

Build Output is shared across modes and replaced by the last build. In cf beta.28, omitting `--mode` uses the mode recorded in that output; it does not select the preview target. Before a prebuilt command, inspect `buildContext.mode` in `.cloudflare/output/v0/config.json` and `name`/`domains` in `.cloudflare/output/v0/workers/default/worker.config.json`, then pass `--mode production --worker ato-site` for production output. Rebuild with `cf:check` before publishing to the preview Worker again.

The old Vercel project, deployments, and domain assignments were deleted on 2026-11-09 after backup and migration verification. `ato.shigoto.dev` remains on Cloudflare. To restore Vercel serving in the future, recreate the Vercel project, redeploy the site, and verify the deployment before detaching the Cloudflare Custom Domain or changing DNS. Restoring the saved Vercel DNS records alone is insufficient. After switching, verify HTTPS and public pages. Do not revert the whole zone or email DNS for a website recovery.
