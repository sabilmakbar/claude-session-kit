# Claude Session Kit

[![tests](https://github.com/sabilmakbar/claude-session-kit/actions/workflows/tests.yml/badge.svg)](https://github.com/sabilmakbar/claude-session-kit/actions/workflows/tests.yml)

Claude Code keeps every conversation as a session, and sessions pile up. Tabs named
"documents-41" that could be anything. A session you reopen after a week that
remembers nothing about where you left off. Half-finished work stranded on the
other laptop. This kit fixes those: it gives sessions real names, leaves you a note
for next time, and moves or splits sessions cleanly. It is plain bash plus `jq`, no
server, no telemetry, nothing to build.

## What you get

Three skills to use inside any session:

| Skill | What it does |
|---|---|
| `/session-kit:rename-session` | Writes a proper title for the current session. Shows up in the tab and the session picker. |
| `/session-kit:session-note` | Saves a short "decided / done / next" note. It greets you when you reopen the session. |
| `/session-kit:handoff` | Moves sessions to another machine, or splits an overgrown session into a fresh one. |

And four optional background hooks:

- **session-note** hands a reopened session its own note back.
- **session-guard** reminds a session where a split-off topic went.
- **session-drift** notices when a session no longer matches its title, or when a
  message landed in the wrong tab.
- **version-check** re-tests the kit after Claude Code updates.

The hooks stay quiet unless they have something useful to say. If anything inside
them fails, they do nothing. They cannot break a session. The one exception exists
because of the quiet: if the kit itself stops working, you get a single line saying
so, once a day until it is fixed, because otherwise a broken kit and a healthy one
would look exactly the same.

Reading order for the rest of the docs: [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) is the
plain-language story and the only one you need to use the kit. [FLOWS.md](docs/FLOWS.md)
has the diagrams, the `docs/DESIGN-*.md` records hold every rule with its reason, and
[INTERNALS.md](docs/INTERNALS.md) records what was observed about Claude Code itself.
Something broken rather than unclear: [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## What it looks like

`cs_list` is the kit's view of your sessions:

```
$ cs_list
7c1e0a4b-...   live   Rewrite the billing importer, split by tenant
b93f5d21-...   live   documents-41
0af6e8c3-...   dead   Investigate flaky checkout tests on CI
```

Three tab-separated columns: the session id, whether a process is still running for it, and
the best name the kit can find. `documents-41` is what an unnamed session looks like, and is
what `/session-kit:rename-session` fixes. `cs_find "billing importer"` finds one by name fragment or id
prefix, and if neither matches, by what the session actually contains. Both only read;
nothing here writes.

The titles are made up. Yours are your own work, so treat `cs_list` output the way you would
treat a list of your branch names.

## Getting started

**The installer edits `~/.claude/settings.json`**, your global Claude Code config, because
registering a hook is the only way to make the reminders arrive on their own. The test
suite runs first and refuses to install if anything fails, the merge into your file only
ever adds, and `--dry-run` shows the plan before anything happens. The exact content added
is in [settings.snippet.json](settings.snippet.json), and
[docs/FLOWS.md](docs/FLOWS.md#writing-settingsjson-at-install-time) has the sequence as a
diagram.

You need `jq`. Moving sessions between machines also needs `shasum` or `sha256sum`.
Details in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

```bash
git clone --branch v0.4.1 https://github.com/sabilmakbar/claude-session-kit.git ~/claude-session-kit
~/claude-session-kit/install.sh     # --dry-run to preview, --uninstall to remove
```

Then add the skills, which ship as a Claude Code plugin:

```bash
claude plugin marketplace add sabilmakbar/claude-session-kit@v0.4.1
claude plugin install session-kit@session-kit
```

**Both steps are needed.** The plugin brings the skills, `/session-kit:rename-session` and
so on. `install.sh` brings the hooks and the libraries those skills source. Order does not
matter. The tag appears twice on purpose: without it, both halves track the default branch
instead of a release ([docs/DESIGN-install.md](docs/DESIGN-install.md), D1).

The timing knobs (when drift checks start, how often they repeat, the handoff pickup
window) live in `~/.claude/session-kit/config`, seeded at install with every default
shown, and upgrades never overwrite your edits.

### Check it worked

```bash
. ~/.claude/session-kit/core/sessions.sh && cs_list
```

You should get the three columns shown above. If nothing prints, the usual cause is a
missing `jq`. The hooks start working in your next session; wiring them is the last thing
the installer does, so a run that breaks earlier never reaches `settings.json` at all.
`settings.json.session-kit.bak` is a one-step undo of the last real change to your
settings.

For a deeper check any time, or after a Claude Code update,
`bash ~/.claude/session-kit/tests/smoke.sh` tests the installed kit against your real
`~/.claude`, read-only. `0 failed` is the answer you want, and the last line records which
Claude Code versions the kit has passed against on this machine. To report a failure, add
`--report`: that output is built to be published, carrying versions and check names but
never a title or a path.

### Upgrading

`<kit>` below is your clone of this repo, wherever you put it. The install commands above
used `~/claude-session-kit`, but any path works.

```bash
git -C <kit> fetch --tags
git -C <kit> checkout <new tag>   # plain `git pull` cannot move a clone pinned to a tag
<kit>/install.sh
```

Then the skills half:

```bash
claude plugin marketplace add sabilmakbar/claude-session-kit@<new tag>   # moves the pin
claude plugin update session-kit@session-kit                             # restart to apply
```

The updater's "restart to apply" message covers the skills only. The hooks and the
libraries they source move with `install.sh`, never with `claude plugin update`. Run the
installer first: it says which state each half is in and names any command still needed.
Skip a half and the kit reports the split once a day rather than leaving you to notice.
Pin forward, not back. If `claude` is not on your `PATH`, see
[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

Only kit code is replaced: your notes, handoff folders, transcripts, and your edited
`config` are left as they are. If you deleted one of the four hooks, re-running the
installer puts it back, because "install" means "wire my hooks". Use `--uninstall` if you
want them gone.

## How it stays safe

- The kit reads Claude Code's own files but only ever appends to them. It never rewrites
  a transcript and never touches VS Code's database.
- Your notes live in their own folder. Uninstalling the kit never deletes them.
- Claude Code's internals are undocumented and can change. The kit degrades safely when
  they do: the hooks go quiet instead of erroring, commands warn that internals may have
  moved and name the check to run, and a failing background re-test is reported in your
  next session rather than waiting to be found.
- Works with bash and zsh; the full suite runs under both, on macOS and Linux.
- A weekly workflow probes every published Claude Code build for the names this kit
  reads; `tests/versions-checked.tsv` is the ledger, always current on `main`. On your
  machine the kit keeps its own list of versions that passed there, and warns only about
  a version that is not on it.

## FAQ and troubleshooting

[FAQ.md](docs/FAQ.md) answers the questions that come up before anything is wrong: the
tab title, renaming other sessions, the built-in `/rename`, which hooks you need.
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) works by symptom when something is wrong.

## Uninstall

```bash
./install.sh --uninstall
```

Removes the installed libraries and the knobs config, along with any bare skill copy an
older version of the kit left in `~/.claude/skills`, and takes its four hooks back out of
`settings.json`, backing the file up first. Hooks it did not put there are not touched.
It leaves your notes (`~/.claude/session-notes/`), your handoff folders
(`~/.claude/session-handoffs/`), and every transcript exactly where they are. The kit
never owned those.

The skills come from the plugin, so remove that separately, and **order matters**:

```bash
claude plugin uninstall session-kit@session-kit    # first
claude plugin marketplace remove session-kit       # only after
```

Reversed, the uninstall fails: it resolves the plugin through the marketplace and cannot
find it once that entry is gone. Neither command removes the plugin's cache under
`~/.claude/plugins/cache/session-kit/`; delete it by hand if you want the disk space back.

## Working on the kit

`bash tests/run.sh` is the gate: `install.sh` runs it first and refuses to deploy a tree
it rejects. [CONTRIBUTING.md](CONTRIBUTING.md) is the way in, including the development
loop for skills. The design records under `docs/` say why every rule exists; read the one
covering what you are changing before you change it.

## Related projects

- **[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit)**: the sibling
  kit. It keeps the preferences you teach Claude across sessions and machines, where this
  kit looks after the sessions themselves.

Released versions and what changed in each: [CHANGELOG.md](CHANGELOG.md).

MIT licensed, see [LICENSE](LICENSE).
