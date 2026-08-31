# Zest for Grok Build

Track your Grok Build sessions in Zest: automatic standups, token and cost
analytics, and a picture of how your team actually works across every AI tool.

## Install

    grok plugin marketplace add Winding-Labs/zest-grok
    grok plugin install zest@zest-grok --trust

Then run `/zest_login` inside a Grok session.

Full instructions: https://app.meetzest.com/docs/install/grok-build

## What it captures

Sessions, messages, tool calls, models, per-turn token usage and context
pressure. Everything is redacted on your machine before it is sent, using
the same privacy pipeline every Zest plugin uses.

## Commands

| Command | What it does |
|---|---|
| `/zest_login` | Connect this machine to your Zest workspace |
| `/zest_logout` | Sign out of Zest |
| `/zest_status` | Auth, workspace, sync state, daemon and hook health |
| `/zest_sync` | Force a sync now |
| `/zest_standup` | Generate today's standup |
| `/zest_enable` | Enable remote sync of sessions to Zest |
| `/zest_disable` | Disable remote sync (keep capturing locally only) |
| `/zest_workspace` | View or switch workspace |
| `/zest_privacy` | View or configure privacy redaction |
| `/zest_ignore` | Stop tracking the current folder |
| `/zest_unignore` | Resume tracking the current folder |

## Runtime

The plugin fetches its compiled runtime on first interactive use (one
time). The first `/zest_login` waits until that download finishes because
Grok buffers slash-command output. This is expected, not a hang.

Set `ZEST_BINARY_PATH` to point at a local binary,
`ZEST_DOWNLOAD_BASE_URL` to use an internal mirror, or
`ZEST_NO_PREFETCH=1` to disable background pre-fetching of new versions
on metered or locked-down setups.

### Updating from an older version

When updating from a version that shipped before Release-based
distribution, run any Zest command once after the update (e.g.
`/zest_login` or `/zest_status`). Hooks never download the runtime, so
capture resumes at the first interactive command. This is a one-time
transition.

## Notes

Source lives in the Zest monorepo; this repository is the distribution
mirror and is regenerated on every release.

## License

Proprietary — see LICENSE.md. Third-party components included in this
distribution are listed in THIRD-PARTY-NOTICES.md.

Questions: hi@winding.ai
