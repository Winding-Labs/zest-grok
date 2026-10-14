# Zest for Grok Build

Track your Grok Build sessions in Zest: automatic standups, token and cost
analytics, and a picture of how your team actually works across every AI tool.

## Install

    grok plugin marketplace add Winding-Labs/zest-grok
    grok plugin install zest@zest-grok --trust

Then run `/zest-login` inside a Grok session.

Full instructions: https://app.meetzest.com/docs/install/grok-build

## What it captures

Sessions, messages, tool calls, models, per-turn token usage and context
pressure. Everything is redacted on your machine before it is sent, using
the same privacy pipeline every Zest plugin uses.

## Commands

| Command | What it does |
|---|---|
| `/zest-login` | Connect this machine to your Zest workspace |
| `/zest-logout` | Sign out of Zest |
| `/zest-status` | Auth, workspace, sync state, daemon and hook health |
| `/zest-sync` | Force a sync now |
| `/zest-standup` | Generate today's standup |
| `/zest-enable` | Enable remote sync of sessions to Zest |
| `/zest-disable` | Disable remote sync (keep capturing locally only) |
| `/zest-workspace` | View or switch workspace |
| `/zest-privacy` | View or configure privacy redaction |
| `/zest-ignore` | Stop tracking the current folder |
| `/zest-unignore` | Resume tracking the current folder |

## Runtime

The plugin fetches its compiled runtime on first interactive use (one
time). The first `/zest-login` waits until that download finishes because
Grok buffers slash-command output. This is expected, not a hang.

Set `ZEST_BINARY_PATH` to point at a local binary,
`ZEST_DOWNLOAD_BASE_URL` to use an internal mirror, or
`ZEST_NO_PREFETCH=1` to disable background pre-fetching of new versions
on metered or locked-down setups.

### Updating from an older version

When updating from a version that shipped before Release-based
distribution, run any Zest command once after the update (e.g.
`/zest-login` or `/zest-status`). Hooks never download the runtime, so
capture resumes at the first interactive command. This is a one-time
transition.

### Updating from a version predating symlink-aware path resolution

This release resolves symlinked project paths correctly. If your projects
live under a symlink (e.g. macOS `/tmp` → `/private/tmp`), the update resets
the sync watermark for those paths, since prior versions never captured them.
The first sync after updating can attempt to upload your full session history
for that project. This is expected, not a runaway sync: uploads are capped at
50 sessions and 1,000 messages per sync cycle, so a large backlog drains over
several cycles (roughly one cycle per 60s daemon tick) instead of uploading
all at once. No action needed — let it run.

## Notes

Source lives in the Zest monorepo; this repository is the distribution
mirror and is regenerated on every release.

## License

Proprietary — see LICENSE.md. Third-party components included in this
distribution are listed in THIRD-PARTY-NOTICES.md.

Questions: hi@winding.ai
