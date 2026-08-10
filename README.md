# Claude Session Kit

Claude Code keeps every conversation as a session, and sessions pile up. Tabs named
"documents-41" that could be anything. A session you reopen after a week that
remembers nothing about where you left off. Half-finished work stranded on the
other laptop. This kit fixes those: it gives sessions real names, leaves you a note
for next time, and moves or splits sessions cleanly.

It is plain bash plus `jq`. No server, no telemetry, nothing to build. It pairs
with [Claude Memory Kit](https://github.com/sabilmakbar/claude-memory-kit), which
does the same job for memory.

## What you get

Three skills to use inside any session:

| Skill | What it does |
|---|---|
| `/rename-session` | Writes a proper title for the current session. Shows up in the tab and the session picker. |
| `/session-note` | Saves a short "decided / done / next" note. It greets you when you reopen the session. |
| `/handoff` | Moves sessions to another machine, or splits an overgrown session into a fresh one. |

And four optional background hooks:

- **session-note** hands a reopened session its own note back.
- **session-guard** reminds a session where a split-off topic went.
- **session-drift** notices when a session no longer matches its title, or when a
  message landed in the wrong tab.
- **version-check** re-tests the kit after Claude Code updates.

The hooks stay quiet unless they have something useful to say. If anything inside
them fails, they do nothing. They cannot break a session.

## Install

```bash
./install.sh     # --dry-run to preview, --uninstall to remove
```

The installer runs the test suite first and refuses to install if anything fails.
It never touches `settings.json`. To turn the hooks on, merge this in yourself:

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

## Try it from a checkout

```bash
. core/sessions.sh
cs_list                    # every session, with its best-known name
cs_find "memory review"    # find a session by name or id

bash tests/run.sh          # the test suite, runs on any machine
bash tests/smoke.sh        # checks the kit against your real ~/.claude
```

If a Claude Code update changes something the kit depends on, `smoke.sh` fails and
writes a report you can paste straight into an issue. The report contains version
numbers and check names only. Never your titles, paths, or username.

## Reading more

- [docs/FLOWS.md](docs/FLOWS.md) shows how everything behaves, with diagrams.
- The three `docs/DESIGN-*.md` files are decision records. Read them before
  changing the kit; every rule in the code has its reason written down there.

## Good to know

- Works with bash and zsh. The full test suite runs under both, on macOS and Linux.
- Needs `jq`. Everything else is stock unix.
- The kit reads Claude Code's own files but only ever appends to them. It never
  rewrites a transcript and never touches VS Code's database.
- Your notes live in their own folder. Uninstalling the kit never deletes them.
- Claude Code's internals are undocumented and can change. The kit is built to
  fail loudly and safely when they do, and to tell you what to run next.
