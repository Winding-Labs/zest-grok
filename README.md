# Zest Tracker — Grok Build CLI Plugin

Automatically track Grok Build coding sessions with Zest, the same productivity insights available for Claude Code and Cursor.

## Overview

This plugin captures Grok Build session transcripts, redacts sensitive content, and syncs them to Zest so they show up in your dashboard alongside every other tool you code with.

**Users** install from the public marketplace repo [`Winding-Labs/zest-grok`](https://github.com/Winding-Labs/zest-grok). **This directory** is the monorepo source; `cd-deploy-grok-plugin.yml` compiles it and publishes the tree.

```bash
grok plugin marketplace add Winding-Labs/zest-grok
grok plugin install zest@zest-grok --trust
```

Pin `@zest-grok`. Grok also lists Claude Code's `zest-marketplace`, and both plugins are named `zest` — unqualified `install zest` fails with "Couldn't scan every marketplace".

Then in a Grok session: `/zest_login` (Grok's built-in `/login` is xAI auth, not Zest).

## Features

- **Automatic session tracking** — captures every Grok Build session via a native hook, no manual export
- **Queue-first architecture** — sessions queue locally and sync once authenticated; nothing is lost if you're offline or signed out
- **Self-healing hook registration** — survives Grok Build upgrades and the plugin checkout moving on disk
- **Privacy-redaction** — the same shared redaction pipeline every Zest plugin uses runs before anything leaves this machine
- **Terminal-only status** — no IDE status line here, so `/zest_status` is the one diagnostic surface; it reports auth, workspace, sync state, the current Grok session, daemon state, hook health, and the current folder's tracked/ignored status truthfully
- **Standup** — `/zest_standup` generates today's standup the same way Claude and Hermes do

## Local development

### Prerequisites

- A real Grok Build install on this machine (`grok --version` should work)
- `bun install --linker=isolated` from the repo root, so this package's workspace deps (`@zest/plugin-common`, `@zest/privacy-redaction`, `@zest/types`, `@zest/utils`) are linked
- Local Supabase running: `bun infra:start` from the repo root

### Environment setup

Copy `.env.example` to `.env` for local dev, or to `.env.staging` for staging:

```bash
cp .env.example .env
```

Fill in `ZEST_SUPABASE_URL` / `ZEST_SUPABASE_ANON_KEY`:

- **Local**: from `bunx supabase status` (repo root), after `bun infra:start`
- **Staging**: ask the team

No build step bakes these into a binary for dogfood. Two scripts:

| Script | What it is |
|---|---|
| `bun run dev` / `dev:staging` | Long-running session. Parks `~/.grok-zest`, attaches this checkout, watches. |
| `bun run cli` / `cli:staging` | Plugin CLI once and exit. No session swap. Tests, verification, and commands while `dev` is running. |

`.env` vs `.env.staging` is whichever script you launched. The hook and daemon still do **not** run with this package as cwd (they start in the user's project), so `login` / `status` / `installHook` snapshot `ZEST_SUPABASE_URL` / anon key / web URL into `~/.grok-zest/runtime.env`. Look at that file, not `echo $ZEST_SUPABASE_URL` in a random shell.

### CLI (`bun run cli`)

```bash
cd apps/grok-cli-plugin
bun run cli command login
bun run cli command status
bun run cli command standup
bun run cli:staging command login
```

Runs `src/cli.ts` once against the current live `~/.grok-zest`. `login` writes the hook + launcher there. Does not park or restore a production session.

### Dev mode (swap in this checkout, restore on exit)

`bun run dev` is a long-running session, not the CLI.

```bash
cd apps/grok-cli-plugin
bun run dev              # local Supabase (.env), parks ~/.grok-zest as ~/.grok-zest.prod
bun run dev:staging      # staging (.env.staging), uses the ~/.grok-zest.staging slot
```

On enter it:

1. Stops the live daemon, parks `~/.grok-zest` as `.prod` (or restores a previous `.dev` / `.staging` slot)
2. Writes the native hook + launcher pointing at this checkout's `src/cli.ts`
3. Writes a local marketplace at `~/.grok/marketplaces/zest-grok-dev` and the auto-trusted plugin at `~/.grok/plugins/zest`, then runs `grok plugin marketplace add` + `grok plugin install zest@zest-grok --trust` so `/plugins` lists Zest and `/zest_login` works
4. Starts a daemon from that launcher
5. Watches `src/`, `commands/`, and `packages/plugin-common/src/` — a change refreshes the plugin files and restarts the daemon

On Ctrl+C **in that terminal** it restores `.prod` and **always** deletes the local marketplace and `~/.grok/plugins/zest` (the `/plugins` dogfood row). Grok does not refresh that UI itself — open `/plugins` and press **`r`** (now, and again after Ctrl+C). If there was never a production session, it also **removes** `~/.grok/hooks/zest.json` so Grok is not left exec-ing a launcher that no longer exists.

Grok also lists plugins from `~/.claude/plugins/` (Claude Code compatibility). After dogfood stops you may see **zest v1.5.2 / zest-marketplace** — that is the Claude plugin, not Grok. Leave it; do not uninstall it from here.

Capture is the native hook (plugin-sourced hooks do not load on spawn). The marketplace tree is the `/plugins` surface and slash commands. Swapping `~/.grok-zest` swaps launcher contents while the hook path stays stable. Slash markdown is `@zest/plugin-common/slash` (Claude will pass `${CLAUDE_PLUGIN_ROOT}/bin/zest …` as `invoke`). Grok's invoke locates `zest-grok` on disk: `GROK_PLUGIN_ROOT` (from the host, or `~/.grok-zest/plugin-root` written at hook install), user plugin, newest `installed-plugins/zest-*` (clean marketplace), then the `~/.grok-zest` launcher login writes for the hook. `bun run generate:commands` rewrites `commands/*.md`.

### Native hook

Grok can load hooks two ways. **Plugin hooks** live in the plugin package (`hooks/hooks.json`) — on Grok Build 1.0.3 they do **not** load when a session spawns. **Native hooks** live in the host directory (`~/.grok/hooks/*.json`) and do load every spawn. We write `~/.grok/hooks/zest.json`; it runs `~/.grok-zest/bin/zest-grok hook SessionStart` (self-heal, active projects, daemon). Capture is the daemon, not the marketplace listing. Slash commands (`/zest_*`) are a third surface: they resolve the same `zest-grok` binary from the installed plugin tree so `/zest_login` works on a clean marketplace install, before the launcher exists.

### When to reload Grok

| Change | Restart the Grok session? |
|---|---|
| `bun run cli command …` | No |
| daemon / `src/` while `bun run dev` is running | No — the watcher restarts the daemon |
| `/zest_*` command markdown | Press **`r`** in `/plugins`, or start a new session |
| Native hook file | Current session already fired SessionStart; the new file applies on the **next** SessionStart |
| New marketplace / plugin install | **`r`** in `/plugins`, or a new session |

**Commands while the watcher is running** (second terminal, same package) — `cli` talks to the live work session:

```bash
bun run cli command login
bun run cli command status
bun run cli:staging command login
```

First enter parks whatever is currently in `~/.grok-zest` as production, so you will need to `command login` once in the new work session.

**Double-check which backend you're pointed at before driving a session that touches real data** — `command status` prints the authenticated workspace (and `Dev mode: active` while the watcher is up), not which Supabase project that workspace lives in.

### Installing into a real Grok Build session

Preferred: leave `bun run dev` running, then `bun run cli command login`. `login` is the device-code flow and (re)writes:

- `~/.grok-zest/bin/zest-grok` — the CLI slash commands and the SessionStart hook both exec. It `exec`s `bun --env-file=~/.grok-zest/runtime.env run "<this-checkout>/src/cli.ts"`; both paths are absolute, written at install time
- `~/.grok-zest/runtime.env` (0600) — snapshot of `ZEST_SUPABASE_*` / `ZEST_WEB_APP_URL`
- a native hook file at `~/.grok/hooks/zest.json` pointing at that launcher

Start any real Grok Build session afterward. `SessionStart` fires the hook, which self-heals the registration if anything moved (Grok Build upgrade, checkout relocated), registers the **session cwd** (hook stdin `cwd` / `~/.grok/active_sessions.json` — same role as Claude Code's `CLAUDE_PROJECT_DIR`, not the git workspace root), and restarts the background daemon. Self-heal runs when our process actually starts (`login`, `status`, or a *working* SessionStart). A deleted or unexecutable hook file cannot repair itself until you run a `zest-grok` command by hand.

**To stop dogfooding:** Ctrl+C the watcher (restores production, or removes the hook if there was none). `bun run cli command logout` still signs out of the *current* `~/.grok-zest` session and removes the hook; queued entries stay (identity matching at upload, not deleted on logout).

## Commands

All run via `bun run cli command <name>` (local) or `bun run cli:staging command <name>` (staging). While `bun run dev` is up they hit the work session.

- `login` — device-code authentication; always installs/repairs the native hook, including when already signed in
- `logout` — clears the stored session; stops the daemon first so it can't regenerate `session.json`
- `status` — the only diagnostic surface for a terminal-only user: auth, workspace, synced-last-hour, pending queue, this Grok session, sync errors, daemon state, hook health, remote-sync on/off, current folder tracked/ignored
- `sync` — capture the current directory, then drain the queue (runs even when no transcript changed)
- `standup` — generate today's standup (`/zest_standup`)
- `enable` / `disable` — write `enableRemotePersistence` (capture still queues when disabled)
- `ignore` / `unignore` — write `excludedFolders` for the current directory
- `workspace` — list or switch the Zest workspace
- `privacy` — view or write detection settings (`--aggressive`, `--gitignore`, `--zest-rules`, `--exclude`)

## Testing

```bash
bun test              # unit tests
bun run types:check   # tsc --noEmit
bun run biome:check   # lint
bun run cli command status   # plugin CLI against the current ~/.grok-zest (no watcher)
```

For an end-to-end pass against a real Grok Build session and real (local) Supabase, follow `docs/agents/grok-local-verification.md` — it's the repeatable procedure the acceptance tests in this app are built around, including a direct-Postgres verification query so you don't need the web UI to confirm a session landed.

## Distribution

Published by `.github/workflows/cd-deploy-grok-plugin.yml` (manual dispatch on `main`) into [`Winding-Labs/zest-grok`](https://github.com/Winding-Labs/zest-grok). Operator runbook: `docs/ops/release-process.md` §5.5.

The job compares the intended version to the mirror **before** compile (`publish` / `complete` / `reject`). Re-running the same bump after a mid-flight failure completes tag, GitHub Release, and `extension_versions` without rewriting binaries. New bits need a new version — `none` is not a rebuild. First live ship: `dry_run=true`, then `version_bump=minor` (`0.0.1` → `0.1.0`).

Marketplace identity (do not rename after the first public install):

| Field | Value |
|---|---|
| Catalog `name` | `zest-grok` |
| Plugin `name` | `zest` |
| Binary | `bin/zest-grok` (not `zest` — Claude already owns that) |
| `extension_versions.platform` | `grokBuild` |

Grok Build 1.0.5 only lists a plugin when `source` is `{ "type": "local", "path": "./plugins/zest" }`. A root-level `"source": "."` shows zero plugins.

Order of the deploy job is load-bearing: build → verify → push mirror → upsert `extension_versions` → bump this `package.json` last.

```bash
bun run build:binary          # production bake + all platform binaries
bun run assemble:release /tmp/zest-grok 0.1.0
```
