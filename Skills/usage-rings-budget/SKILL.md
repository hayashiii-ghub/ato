---
name: usage-rings-budget
description: Keep the working agent aware of its account allowance through ato? on macOS, with below-20/10/5% notices and reset times.
---

Continue the authorized task. Keep notices in working context; tell the user only if asked or delivery is affected. A low reading alone does not require a reply, stop, split, or switch.
Registered hooks supply notices at their supported boundaries; do not repeat them manually. This skill itself neither registers hooks nor runs in the background.

Without hooks, read once when starting substantial work and at natural pauses; do not poll repeatedly or automatically start/configure the app or providers.
Use the task's account: `codex`, `claude`, `cursor`, `grok`, or `gemini` (Antigravity only); ask which only if unclear. For Codex:

```sh
"$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

Use `/Applications/Usage Rings.app` if installed there; select the intended app if both exist. The CLI reads the running app without refreshing providers or changing settings.
For schema `1`, use each fresh `alerts` entry even when other windows are unknown; retain provider, window, remaining percentage, and reset countdown. A missing reset is unknown.
Use strict <20/<10/<5% stages, choosing only the lowest crossed threshold (4% means the 5% stage). In this conversation, remember the lowest noticed stage per provider/window/reset; do not repeat it after recovery or a hook notice.
Unchanged or older `observedAt` is not new. Null, stale, disabled, unavailable, expired, or failed output is unknown; emit no low-usage notice from it. Empty `alerts` do not prove available quota; do not retry in a loop.
These are account limits, not conversation context or API credits. Re-read after reset or `validUntil`; never infer a refill or convert percentages into task/token counts. Calculate reset countdowns from the actual read time.
