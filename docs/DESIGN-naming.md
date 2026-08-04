# Design: session identity & naming

## The problem

One session has three identities, stored in three places that never talk to each other:

| Layer | Example | Where it lives | Who writes it |
|---|---|---|---|
| Display title (what the user sees) | "Review memories and feedbacks" | VS Code `workspaceStorage/<hash>/state.vscdb` (workbench editor memento) | VS Code extension, generated from the opening message |
| CLI registration name | `documents-2d` | `~/.claude/sessions/<pid>.json` (`name`, `nameSource: derived`) | Claude Code CLI at session start |
| Transcript identity | `0d15803a-…` | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | Claude Code, one file per session |

Verified on Claude Code v2.1.220 (macOS, VS Code extension). Notes:

- The pid-file is per **process**, keyed by pid, and only exists for sessions that ran
  on this machine. Imported transcripts have no registration at all.
- Transcripts in this version carry **no title/summary entries** — display names are
  derived at list time (first user message) or read from VS Code state.
- The display title is set once from the opening message and never revised, so any
  session that outgrows its first question has a stale title ("drift").

## Existing behavior rule

The memory `feedback_session_identifiers` (miner P-009) already tells Claude to refer
to sessions by title, flag drift, and suggest renames. What is missing is tooling:
detection is manual and renaming is buried in the UI.

## Proposed pieces

1. **`core/sessions.sh`** — resolve a session from any identifier (title substring,
   short id, full UUID) to all three layers; list sessions with their best-known name.
   Read-only first; this is the backbone both features build on.
2. **Drift detector** — compare a session's stored title against its recent content
   (cheap heuristic first: does any title word appear in the last N user messages?).
   Surfaced as a session-end or session-start ping, same `additionalContext` pattern
   as the memory kit's hooks. Optionally a headless-Claude scorer later, only if the
   heuristic proves too dumb. On drift the ping offers a fork: **rename** (same work,
   evolved topic) or **split** into a fresh session via a handoff note — the drift
   guardrail described in DESIGN-handoff.md's same-machine use case.
3. **Rename helper** — a skill (`/rename-session`) that proposes a title from the
   transcript and applies it where writable. Open question below decides "where".

## Open questions (answer before building)

- **Is the VS Code title writable safely?** `state.vscdb` is VS Code-owned sqlite;
  writing it while VS Code runs is risky and unsupported. Investigate: does the
  extension or CLI expose a rename (command, slash command, or API)? If not, the
  honest scope is CLI-side naming only (own name file keyed by session UUID, shown by
  our own tooling and statusline), leaving the VS Code tab alone.
- **Where does a durable name live?** The pid-file dies with the process. Proposal: a
  sidecar `~/.claude/projects/<encoded-cwd>/<session-id>.name` (or one index file per
  project dir) owned by this kit — survives restarts, travels with handoff (see
  DESIGN-handoff.md), and never touches files other tools own.
- **Cross-version fragility** — all three storage locations are undocumented
  internals. Every accessor belongs in `core/` with a version check and a fail-quiet
  path, so a Claude Code update degrades the kit to "no data" rather than breakage.
