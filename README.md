# ato?

Remaining Codex, Claude, Cursor, Grok, and Gemini usage on **macOS 26+ / Apple silicon**.

Previously Usage Rings. The app folder and `usage-rings` command keep their original
names so existing helper settings and updates continue to work.

## Install and use

1. Download the [DMG](https://github.com/hayashiii-ghub/ato/releases/latest/download/usage-rings-macos.dmg)
   or ZIP from [Releases](https://github.com/hayashiii-ghub/ato/releases).
2. Quit ato? and replace the app in its existing Applications folder.
3. Open it, read the connection explanation, and choose **Enable**.
4. Desktop → **Edit Widgets** → **ato? → AI Usage**.

The app is ad-hoc signed, **not notarized**. If macOS blocks it and you trust the
source, use Apple's [per-app approval](https://support.apple.com/102445).
Use **Updates…** for later updates. Download verification:
save all five release assets together, then `shasum -a 256 -c usage-rings-macos.sha256`.

Choose a service in each row; selecting an existing service swaps the two rows.
Drag a ring to reorder. The chevron shows all limits and reset times.
Only the four selected services are monitored. **Auto** shows the lowest remaining
main window; **5 hours** and **Week** select a period. Choices also apply to the widget.
Missing, failed, expired, or 20-minute-old readings show **—**.

Monitoring refreshes every five minutes and after waking. Closing the window keeps
it running; **Quit** stops future polling, and reopening resumes it.
An in-flight request may finish. Widget updates follow macOS scheduling.
Claude and Gemini receive usage through CLI activity, so polling alone does not
produce a new reading. Gemini quota data that stays unchanged for 20 minutes also shows **—**.
Antigravity provides no quota observation timestamp. ato? filters repeats of the
current value and the latest 256 distinct readings; older replays may appear new.

## Accounts

Sign in separately; ato? starts no login flow. API-key billing and pooled
Grok enterprise allowances are unsupported.

| Service | Required sign-in |
| --- | --- |
| Codex | Codex CLI 0.160.1+ with ChatGPT; desktop sign-in alone is insufficient |
| Claude | Claude Code 2.1.251+ with Pro/Max and the optional helper below |
| Cursor | Cursor desktop |
| Grok | Cursor desktop account used by Grok |
| Gemini | Antigravity CLI 1.1.11+ (`agy`) with Google and the helper below; Gemini CLI is unsupported |

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

### Gemini helper

Available in ato? 0.2.3 or later.
ato? reads Antigravity's status line data without starting `agy`. Source installation
connects the helper unless a custom status line exists. For downloads, merge this
into `~/.gemini/antigravity-cli/settings.json`, preserving
other settings and any existing custom command:

```json
{"statusLine":{"type":"command","command":"\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\" --provider gemini","stack_with_default":true}}
```

For user Applications, replace `/Applications` with `$HOME/Applications`. Usage
arrives the next time you use Antigravity. If Gemini shows **—** before its first
reading, connect this helper and use Antigravity to provide usage data.
To disconnect, remove only this invocation; remove source-installer setup with
`python3 script/antigravity-statusline-setup.py --uninstall`.

## CLI and AI skill

```sh
"$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Adjust the app path as needed; use `--help` for options. The CLI reads the running
app without refreshing or changing settings.

In **AI Tools** on ato?'s main screen, choose **Set Up** for Codex, Claude Code, Cursor,
or Antigravity. This links `~/.local/bin/usage-rings`, copies the bundled
[skill](Skills/usage-rings-budget/SKILL.md), and merges that assistant's budget hook.
Antigravity receives skills for both its CLI and App/IDE. Setup uses the native
`Contents/Helpers/UsageRingsBudgetHook`; no Python installation is needed.
In Codex CLI, use `/hooks` to review and trust the new hook if needed. Start a new assistant session
after setup. Configuration alone does not prove the hook is approved or running.

The same screen checks setup, updates managed tools after app updates, and
disconnects them. Existing settings and status lines are preserved; edited skills,
unrelated links, and unrecognized ato? hooks need review before changes. Settings
are backed up beside their original files; failed setup restores earlier files. The shared CLI is
kept while another configured assistant uses it. Ownership records are stored
under `~/Library/Application Support/Usage Rings/`. Setup does not enable monitoring,
connect status-line helpers, sign in, or launch an assistant.

The skill alone checks at work boundaries; it cannot interrupt ongoing reasoning.
The CLI is stateless, so manual use tracks noticed stages in the conversation.
Fresh observations usually arrive every five minutes; unchanged data is not a new
reading. Exit `1` means the snapshot is unavailable/invalid; exit `2` means invalid
arguments. An unavailable reading does not automatically stop the agent's task.

### Budget hooks

The native helper supports local Codex, Claude Code,
Cursor Agent, and Antigravity CLI sessions. It reads the same running-app snapshot and supplies
account-allowance context at new below-20/10/5% stages. It neither interrupts a
running model request nor starts a conversation. It does not launch the app,
refresh providers, change sign-in, or stop work when usage is unknown.

The Python prototype from 0.2.5 remains available for manual setup (Python 3.9+).
Preview a configuration fragment from the installed app. Choose `codex`, `claude`,
`cursor`, or `antigravity`:

```sh
python3 "$HOME/Applications/Usage Rings.app/Contents/Resources/Skills/usage-rings-budget/scripts/hook_config.py" --client codex \
  --cli "$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings"
```

The preview changes no settings. Use a stable absolute script path; merge the
fragment into existing hooks rather than replacing the configuration:

| Client | Configuration | When context is supplied |
| --- | --- | --- |
| Codex | `.codex/hooks.json` in a trusted project, or `~/.codex/hooks.json`; approve the hook with `/hooks` | After tools, in the background; next safe model request |
| Claude Code | `.claude/settings.local.json` or `~/.claude/settings.json` | After tools |
| Cursor Agent | `.cursor/hooks.json` or `~/.cursor/hooks.json` | After tools |
| Antigravity CLI | `.agents/hooks.json` or `~/.gemini/config/hooks.json` | Before each model invocation |

Adjust both app paths for `/Applications` if needed. Keep unrelated hooks and status lines.
Antigravity uses a named-hook map; do not
wrap its generated fragment in another `hooks` object. Gemini CLI is unsupported.
Cloud agents cannot read this Mac's snapshot. Synthetic tests cover the output
formats. Automatic reads with both the Python prototype and native helper were verified in new Codex CLI
sessions, with the native hook approved through `/hooks`. Live low-usage delivery and
native execution inside Claude Code, Cursor Agent, and Antigravity still need verification.
Reloading an already-open Desktop chat is unverified.

Checks are limited to once per minute per client/conversation, with a two-second
CLI deadline. Hashed conversation IDs and noticed stages are kept in an owner-only
temporary directory (`ato-budget-native-hooks-<uid>` for the native helper,
`ato-budget-hooks-<uid>` for Python), with at most 128 conversations
retained for seven days. No prompts, tool arguments, or full usage reports are
saved. Each conversation retains eight windows and eight reset boundaries per
window. The cache may be cleared or evicted, after which a stage can be noticed again.
Only new observations and reset boundaries affect notices; stale/unknown data is quiet.
The two helpers use separate caches, so switching helpers can repeat an earlier notice.

## Security and data FAQ

**Reads:** Codex uses its CLI, which manages authentication/cache.
Cursor/Grok read Cursor's session for HTTPS requests to `cursor.com` and `api2.cursor.sh`;
redirects are rejected, and these internal endpoints may change. Claude/Gemini read
only their helpers' usage caches; ato? does not launch Antigravity. No conversations,
analytics, or usage go to the developer.

**Local data:** Other local processes can read usage, times, and display settings at
`127.0.0.1:52388/v1/usage`; no credentials are exposed. The widget cache and the helpers'
`~/Library/Caches/Usage Rings/` caches are owner-only; there is no history/cloud sync.
Claude session identifiers are hashed. Sharing CLI output with an AI shares those
values with its service. Update checks contact GitHub separately.

**Consent:** No provider reads occur before consent; an older saved Off choice requires
consent again. Disconnect the Claude/Gemini helpers separately when stopping. macOS may retain
the widget cache. A reset never implies a full allowance.

## Build from source

With Xcode installed, set `app_version` (`x.y.z`) and `app_build` (1–9999) for the
build. Keep the version at least as high as installed and increase the build number.

```sh
make check
APP_VERSION="$app_version" APP_BUILD="$app_build" make install
```

This builds/verifies, replaces `~/Applications/Usage Rings.app`, restarts its widget,
and opens the app. Custom Claude/Antigravity status lines are preserved. Development and
release instructions: [AGENTS.md](AGENTS.md). Licenses: [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

`Assets/AppIcon.svg` owns the icon shape. After editing it, run
`swift run IconAssets` to regenerate the native light/dark icon layers and web
icons using the widget's SwiftUI colors. Builds compile `Assets/AppIcon.icon`
with Xcode's asset compiler; macOS chooses its appearance using the system icon style.

## Website

The [public website](https://ato.shigoto.dev) is hosted on Vercel.
Its source lives in [`site/`](site), using Bun and TypeScript with static HTML/CSS.
Python is used by source installation, packaging, manual hook scripts, and tests.

```sh
cd site
bun install --frozen-lockfile
bun run dev
```

From the repository root, `make site-check` checks types and `make site-build`
generates `site/dist/` for static hosting. Run `cd site && bun run test` to check
the generated site. Edit `site/src/` and `site/public/`;
the generated `dist/` is not tracked. Website commands are separate from the
Swift app's build and installation commands.
