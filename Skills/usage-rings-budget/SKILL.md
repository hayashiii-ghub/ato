---
name: usage-rings-budget
description: Check remaining AI usage through Usage Rings on macOS and ask the user how to continue when a main allowance drops below a configurable threshold, 20% by default. Use when the user wants low-usage notices with the time until reset.
---

# Usage Rings budget

Report low usage and let the user decide how to continue. Do not automatically
split, reduce, stop, or switch the task based on the percentage.

## Check usage

Use the provider backing this task: `codex`, `claude`, `cursor`, `grok`, or
`gemini` (Antigravity CLI's Gemini allowance). If the relevant account is unclear,
ask which to check. These are account limits, not remaining conversation context
or API credits.

Find `Contents/Helpers/usage-rings` in the installed Usage Rings app. The normal
locations are `~/Applications/Usage Rings.app` and `/Applications/Usage Rings.app`;
use the known installation when both exist. For example, for a Codex task:

```sh
"$HOME/Applications/Usage Rings.app/Contents/Helpers/usage-rings" status --json --provider codex
```

The threshold defaults to **20%**. When the user says, for example, "tell me at
10%", add `--threshold 10` to subsequent calls. Remember that choice in the
conversation. The CLI accepts percentages greater than 0 and up to 100 and does
not save settings. A value exactly equal to the threshold is not below it.

Read once when beginning substantial work and again at natural pauses before
continuing. The command reads the running app's snapshot without refreshing
providers or changing settings. Observations usually update every five minutes;
do not poll repeatedly or treat an unchanged `observedAt` as a new reading.
This skill has no background process and cannot interrupt an AI that has not
called the CLI.

## Ask when usage is low

For JSON schema version `1`, use `alerts`. Each entry identifies a fresh main
window below the threshold, independently of the ring's displayed period.
It includes the remaining percentage, observation time, reset time, and
`secondsUntilReset`. An alert can exist while another window is unknown.

When an alert first appears, briefly give the provider, window, remaining
percentage, and time until reset in hours/days appropriate to its length. Include
the observation time if it is old enough to affect the decision. For example:

> Codexの週枠が残り18%です。リセットまであと2日6時間あります。
> このまま続けますか、それとも一区切りにしますか？

Use the available user-input mechanism and let the answer determine the next
substantial work. The choices may be to continue, finish the current piece, or
pause. Do not silently choose one. If the user already gave a standing preference,
follow it. If they pause, leave a short handoff in the conversation; do not create
extra planning documents or schedule a restart.

Avoid repeating the same question for the same provider, window, reset boundary,
and threshold once the user has answered. Reconsider when the reset boundary or
threshold changes, or the allowance reaches 0%. The CLI is stateless: it reports
current low windows, not evidence that a threshold was crossed since its last call.

An empty `alerts` array does not guarantee available quota. Check service/window
states: `null`, stale, disabled, or unavailable readings are unknown. Mention an
unavailable reading once and continue the original task unless the user required
a verified budget. Do not enable accounts or retry in a loop. Exit `1` means the
snapshot was unavailable/invalid; exit `2` means invalid arguments. After a reset
or `validUntil`, get a new reading instead of assuming the allowance is full.
Use the actual read time for reset countdowns and say "unknown" for a missing reset.
Never convert the percentage to an exact number of tasks or tokens.
