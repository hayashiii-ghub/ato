---
name: usage-rings-budget
description: Give the working agent remaining-usage notices at 20%, 10%, and 5%, with time until reset, through Usage Rings on macOS. Use when the user wants the agent to stay aware of its account allowance while working.
---

# Usage Rings budget

Give the agent usage awareness while it continues the authorized task. A low-usage
notice does not require a user reply or automatically split, stop, or switch work.

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

Read once when beginning substantial work and again at natural pauses before
continuing. The command reads the running app's snapshot without refreshing
providers or changing settings. Observations usually update every five minutes;
do not poll repeatedly or treat an unchanged `observedAt` as a new reading.
This skill has no background process and cannot interrupt an AI that has not
called the CLI.

## Notice the 20%, 10%, and 5% stages

For JSON schema version `1`, use `alerts` with the CLI's default 20% threshold.
Each entry identifies a fresh main window below 20%, independently of the ring's displayed period.
It includes the remaining percentage, observation time, reset time, and
`secondsUntilReset`. An alert can exist while another window is unknown.

Choose the lowest stage strictly above `remainingPercent`: below 20%, below 10%,
or below 5%. Equality does not count as below. Remember the lowest stage already
noticed for each provider, window, and reset boundary in this conversation.
Notice it once, then again only when a lower stage is reached or the reset boundary
changes. A reading that rises and falls within the same reset window does not
repeat an earlier stage. If the first reading is 4%, or a reading jumps from 25%
to 4%, use only the 5% stage; do not queue all three notices. Zero stays in the 5% stage.

For a new stage, retain a short working-context notice with the provider, window,
remaining percentage, and time until reset in appropriate hours/days. For example:

> Codex / Week: 8% remaining; reset in 2d 6h (below 10%).

This is context for the agent, not a routine user-facing alert or approval request.
Continue the task; tell the user only if they ask or the usage affects delivery.
The CLI is stateless and reports current low windows; stage tracking belongs to
the conversation, not a settings file or background process.

An empty `alerts` array does not guarantee available quota. Check service/window
states: `null`, stale, disabled, or unavailable readings are unknown. Do not emit a
low-usage stage from an unknown reading. Continue the original task unless the user
required a verified budget. Do not enable accounts or retry in a loop. Exit `1` means the
snapshot was unavailable/invalid; exit `2` means invalid arguments. After a reset
or `validUntil`, get a new reading instead of assuming the allowance is full.
Use the actual read time for reset countdowns and say "unknown" for a missing reset.
Never convert the percentage to an exact number of tasks or tokens.
