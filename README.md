# Claude Session Kit

[![tests](https://github.com/sabilmakbar/claude-session-kit/actions/workflows/tests.yml/badge.svg)](https://github.com/sabilmakbar/claude-session-kit/actions/workflows/tests.yml)

Claude Code keeps every conversation as a session, and sessions pile up. Tabs named
"documents-41" that could be anything. A session you reopen after a week that
remembers nothing about where you left off. Half-finished work stranded on the
other laptop. This kit fixes those: it gives sessions real names, leaves you a note
for next time, and moves or splits sessions cleanly.

It is plain bash plus `jq`. Moving sessions between machines also needs `shasum` or
`sha256sum`, one of which is stock on macOS and Linux; without one, export and import
refuse rather than write a bundle nothing can verify. No server, no telemetry, nothing
to build.

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
git clone https://github.com/sabilmakbar/claude-session-kit.git ~/claude-session-kit
~/claude-session-kit/install.sh     # --dry-run to preview, --uninstall to remove
```

The installer runs the test suite first and refuses to install if anything fails, then
checks that the copy it just installed loads. Re-running it is safe.

To confirm it works, ask it to list your sessions:

```bash
. ~/.claude/session-kit/core/sessions.sh && cs_list
```

You should get one line per session: its id, whether it is live or dead, and the best name
the kit can find for it. If nothing prints, or the name column comes back empty, the usual
cause is a missing `jq` (see [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)). The three
skills are available in any new session; `/rename-session` is the quickest one to try.

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

## Is it working?

If something seems off, or Claude Code has just updated itself, run the smoke suite. It
checks the installed kit against your real `~/.claude` rather than against fixtures, and
it only reads:

```
$ bash ~/.claude/session-kit/tests/smoke.sh
smoke: 23 transcripts

layout
  ok   every transcript is at the expected depth
  ok   a Claude Code version is readable from the pid-files
...
13 passed, 0 failed, 0 skipped
verified against Claude Code 2.1.222
```

`0 failed` is the answer you want, and the last line tells you which Claude Code version
the kit has been checked against on this machine. A skip is fine; it means a check had no
data to run against.

If something fails, [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) works through it by
symptom. To report it, paste the report rather than your terminal:

```bash
bash ~/.claude/session-kit/tests/smoke.sh --report
```

That report is built to be published. It carries versions, check names, and the first eight
characters of a session id, never a title or a path. The terminal output is deliberately not
redacted, because seeing the offending title is what makes a failure debuggable on your own
machine.

## Reading more

- [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) tells the whole story in plain words,
  and it is the only one you need in order to use the kit.
- [docs/FLOWS.md](docs/FLOWS.md) is the next step down: diagrams of what runs when,
  with the specifics the plain-language version leaves out.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) is symptom, check, fix. Start
  there when something is actually broken.
- [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) lists what the kit needs. Short
  version: `jq`.
- The three `docs/DESIGN-*.md` files are decision records. Read them before
  changing the kit; every rule in the code has its reason written down there.

## Good to know

- Works with bash and zsh. The full test suite runs under both, on macOS and Linux.
- The kit reads Claude Code's own files but only ever appends to them. It never
  rewrites a transcript and never touches VS Code's database.
- Your notes live in their own folder. Uninstalling the kit never deletes them.
- The timing knobs (when drift checks start, how often they repeat, the handoff
  pickup window) live in `~/.claude/session-kit/config`. Edit it freely; upgrades
  never overwrite it.
- Claude Code's internals are undocumented and can change. The kit is built to
  fail loudly and safely when they do, and to tell you what to run next.
- Verified against Claude Code 2.1.222. The real-data suite also passes over
  transcripts written by 20 versions, 2.1.177 through 2.1.222. Older versions are
  untested.

## FAQ

**Why doesn't the tab title change right after a rename?**
The tab reads its title when it opens. Close and reopen the tab to see the new
name; the session picker shows it immediately.

**Can it rename a session other than the one I'm in?**
No, on purpose. A title should be written by the session that can actually see the
conversation. The one exception is import, which titles the sessions it just
installed from a bundle. The reasoning lives in the naming design doc.

**Does it fight Claude Code's built-in `/rename`?**
No. The kit writes the same kind of title entry `/rename` writes, one appended
line. The newest title wins, cleanly, whichever tool wrote it.

**Do I need all four hooks?**
No. Each one works alone; wire the ones you want. The skills work with no hooks at
all; you just lose the automatic reminders.

**Does anything leave my machine?**
No. There is no network code. Even the failure report is written locally and
redacted, for you to paste somewhere only if you choose to.

**What happens when Claude Code updates?**
A startup hook notices and re-tests the kit against your real data, once, in the
background. Silence means everything still works. If something moved, the kit
warns you until it is looked at.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the installed libraries, the three skills, and the knobs config (it
configures nothing once the kit is gone). It leaves your notes
(`~/.claude/session-notes/`), your handoff folders (`~/.claude/session-handoffs/`),
and every transcript exactly where they are. The kit never owned those. If you
wired the hooks into `settings.json`, remove those lines too; until you do they
point at nothing and silently do nothing.

## Related projects

- **[claude-setup-template](https://github.com/sabilmakbar/claude-setup-template)**: one
  manifest for a whole Claude Code setup. You declare the kits, CLI tools, plugins, and
  hooks a machine should have, and its `setup.sh` converges the machine onto it. Its
  example manifest installs this kit and takes care of the `settings.json` hook wiring
  above, so start there if you are setting up a machine rather than adding one piece.
- **[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit)**: the sibling
  kit. It keeps the preferences you teach Claude across sessions and machines, where this
  kit looks after the sessions themselves.

MIT licensed, see [LICENSE](LICENSE).
