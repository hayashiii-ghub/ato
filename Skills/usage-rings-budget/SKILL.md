---
name: usage-rings-budget
description: Keep the working agent aware of its account allowance through ato? on macOS, with below-20/10% notices and reset times.
---

Below 20%, continue the authorized task while avoiding unnecessary exploration and repeated checks. Below 10%, prioritize required verification and organizing handoff information toward a safe stopping point. Preserve required checks and quality. Do not create a new document without approval. A low reading alone does not require stopping, splitting, or switching to another AI.
Keep notices in working context; tell the user only if asked or delivery is affected. When reporting, briefly include the remaining allowance, reset countdown if known, and the next steps.
Registered hooks supply notices at their supported boundaries; do not repeat them manually. This skill itself neither registers hooks nor runs in the background.

Without hooks, read once when starting substantial work and at natural pauses; do not poll repeatedly or automatically start/configure the app or providers.
Use the task's account: `codex`, `claude`, `cursor`, `grok`, or `gemini` (Antigravity only); ask which only if unclear. After AI Tools setup, for Codex:

```sh
"$HOME/.local/bin/usage-rings" status --json --provider codex
```

Without AI Tools setup, use `Contents/Helpers/usage-rings` inside the intended `Usage Rings.app` (`~/Applications` or `/Applications`). Select the intended app if both exist. The CLI reads the running app without refreshing providers or changing settings.
For schema `1`, use each fresh `alerts` entry even when other windows are unknown; retain provider, window, remaining percentage, and reset countdown. A missing reset is unknown.
Use strict <20/<10% stages, choosing only the lowest crossed threshold (4% means the 10% stage). In this conversation, remember the lowest noticed stage per provider/window/reset; do not repeat it after recovery or a hook notice.
Unchanged or older `observedAt` is not new. Null, stale, disabled, unavailable, expired, or failed output is unknown; emit no low-usage notice from it. Empty `alerts` do not prove available quota; do not retry in a loop.
These are account limits, not conversation context or API credits. Re-read after reset or `validUntil`; never infer a refill or convert percentages into task/token counts. Calculate reset countdowns from the actual read time.
