# claude-session-kit

Tools for managing Claude Code **sessions** across machines — a sibling to
[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit), which does the
same for memory.

**Status: built, tested, and in daily use.** Naming, per-session notes, cross-machine
handoff, same-machine splits, and a drift detector — all live. Start with
[docs/FLOWS.md](docs/FLOWS.md) for how everything behaves (flowcharts included); the
three design docs record every decision and what it overturned.

```bash
./install.sh            # idempotent; --dry-run to preview, --uninstall to remove
```

Installs the libraries to `~/.claude/session-kit/` and three skills —
`/rename-session`, `/session-note`, `/handoff` — to `~/.claude/skills/`. It runs the
test suite first and refuses to install if it fails, and it never edits
`settings.json`: wiring the four optional hooks is your call. Merge this into
`~/.claude/settings.json` to enable all of them:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/version-check.sh\" 2>/dev/null || true" }
      ]}
    ],
    "UserPromptSubmit": [
      { "hooks": [
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/session-note.sh\" 2>/dev/null || true" },
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/session-guard.sh\" 2>/dev/null || true" },
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/session-drift.sh\" 2>/dev/null || true" }
      ]}
    ]
  }
}
```

Each hook degrades to silence on any failure — none of them can break a session.
(If you converge machines from a manifest, declare these four lines there instead
and skip the paste.) From a checkout, the scripts also work in place:

```bash
. core/sessions.sh
cs_list                                  # every session, live flag, best-known name
cs_resolve_name "$CLAUDE_CODE_SESSION_ID"
cs_find "memory review"                  # UUID, short-id prefix, or name substring

. naming/rename.sh
rename_apply "A new title"               # the session you are in, and only that one

bash tests/run.sh                        # fixtures, runs anywhere
bash tests/smoke.sh                      # real ~/.claude, invariants only, skips on CI
bash tests/smoke.sh --report             # last failure, redacted and safe to paste
```

`smoke.sh` is what you run when Claude Code updates and the kit warns that internals
may have moved. A `SessionStart` hook can do it for you; `install.sh` prints the line
to add. On failure it writes a report built from safe fields only — versions, check
names, and 8-character session ids, never titles or paths — so it can be pasted into
an issue without carrying your work into it.

## The three problems it solves

1. **Session identity** ([docs/DESIGN-naming.md](docs/DESIGN-naming.md)) — a session has
   three names in three places (VS Code tab title, CLI registration name, transcript
   UUID), none of them synced. Titles drift from what the session is actually about,
   and generic derived names ("documents-2d") make past work unfindable. The drift
   detector closes the loop: it schedules the "does this still match?" question and
   the in-session agent judges it, silently unless something is off.
2. **Session continuity** ([docs/DESIGN-notes.md](docs/DESIGN-notes.md)) — a reopened
   session starts cold. A per-session note (decided / done / next) written at
   milestones is handed back on the first message after reopening, age-stamped so a
   stale note can never masquerade as current.
3. **Session handoff** ([docs/DESIGN-handoff.md](docs/DESIGN-handoff.md)) — moving work
   is manual: tar the transcripts, carry a WIP note, rename files by hand, lose the
   titles on the way. Now: a checksummed bundle with atomic import across machines,
   or a note-only split into a fresh session on the same machine, with a soft guard
   on the old one.

## Layout

```
core/       read-only resolver over the transcript and pid-file layers
naming/     rename helpers — every write the kit makes to a live session lives here
notes/      per-session working notes (decided / done / next)
handoff/    export, import, split, claim, release
hooks/      version-check, session-note, session-guard, session-drift
skills/     rename-session, session-note, handoff
tests/      run.sh (fixtures, runs anywhere) + smoke.sh (real ~/.claude)
install.sh  idempotent installer, refuses to install if the tests fail
```

`core/` reads two layers, the transcript and the pid-file. VS Code's `state.vscdb` is
deliberately excluded: it only caches the rendered tab, and the tab resolves from the
transcript anyway. See [docs/DESIGN-naming.md](docs/DESIGN-naming.md).

## Shells

**bash and zsh.** Both are tested by running the *whole* suite under each, not by
checking that the library loads. An earlier version only checked loading, and passed
while `cs_find`, `cs_list` and `cs_pid_file` were all broken under zsh — the two shells
differ both in how a sourced file learns its own path (`BASH_SOURCE` vs `$0`) and in
what an unmatched glob does (literal vs fatal).

Other shells fail at parse time (`dash: Syntax error: redirection unexpected`), which is
a deliberate, loud failure rather than a silent misbehaviour. If you need to source the
library from somewhere that cannot report the sourced file's path, set
`CLAUDE_SESSION_KIT_ROOT` to the kit root; a wrong or missing root produces an error
naming that variable rather than a confusing path.

Design rule carried over from the memory kit: plain files, plain bash, no server, no
telemetry; every behavior covered by the test suite; installers idempotent.
