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

The docs go shortest first. New here? [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) tells the
whole story in plain words, and it is the only one you need in order to use the kit.
[FLOWS.md](docs/FLOWS.md) is the next step down: diagrams of what runs when, with the
specifics the plain-language version leaves out. The `docs/DESIGN-*.md` files are
decision records, for anyone changing the kit rather than running it: every rule in the
code with the reason it exists. Underneath those,
[INTERNALS.md](docs/INTERNALS.md) is about Claude Code rather than about this kit: what was
observed about undocumented behaviour the kit leans on, each entry dated, versioned, and
written so you can re-run the check yourself.

If something is broken rather than unclear, go straight to
[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

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
them fails, they do nothing. They cannot break a session.

There is one exception to the quiet, and it exists because of the quiet: if the kit
itself stops working, you get a single line saying so and what to do about it, once a
day until it is fixed. Otherwise a broken kit and a healthy one would look exactly the
same, since both say nothing.

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
prefix, and if neither matches, by what the session actually contains, so a session whose
title describes the whole arc of the work is still findable by a specific thing you did in
it. Both only read; nothing here writes.

The titles are made up. Yours are your own work, so treat `cs_list` output the way you would
treat a list of your branch names.

## Install

**Read this first: the installer edits `~/.claude/settings.json`.** That file is your global
Claude Code config, shared with every other tool you have installed. The kit writes to it
because registering a hook is the only way to make the reminders arrive on their own.

Two gates run before anything is written, and neither is good intentions.

The test suite runs first. If it fails, nothing is installed. Then your `settings.json` is
checked: if it cannot be parsed, or the part the kit merges into is not the shape it expects,
the run stops and names the key to fix. Nothing is deployed and your file is untouched.

Past those, the merge only ever adds, and a run that fails later puts the previous contents
back. `--dry-run` shows you the plan without doing any of it.

The exact content added is in [settings.snippet.json](settings.snippet.json).
[docs/FLOWS.md](docs/FLOWS.md#writing-settingsjson-at-install-time) has the whole sequence as a
diagram, and spells out what the installer leaves alone: another tool's hooks, events this kit
does not wire, and every setting that is not a hook.

```bash
git clone --branch v0.3.1 https://github.com/sabilmakbar/claude-session-kit.git ~/claude-session-kit
~/claude-session-kit/install.sh     # --dry-run to preview, --uninstall to remove
```

Then add the skills, which ship as a Claude Code plugin:

```bash
claude plugin marketplace add sabilmakbar/claude-session-kit@v0.3.1
claude plugin install session-kit@session-kit
```

**Why the tag appears twice.** Both halves carry a version, and both default to tracking the
default branch rather than a release. Leave the tag off and you get whatever `main` held that
day, filed under the version number `main` declared, which is the next release's number rather
than one that shipped. Pinning both halves to the same tag is what makes the version this kit
reports mean something.

To move to a newer release, repeat those commands with the new tag, then
`claude plugin update session-kit@session-kit`. Pin forward, not back: a pin below a version
already in the plugin cache has no effect, because the newest cached version is the one that
loads, and `install.sh` names the blocking directory when it sees that state.

Two forms pin the plugin half: `owner/repo@v0.3.1` as above, or
`https://github.com/sabilmakbar/claude-session-kit.git#v0.3.1`. Writing `@v0.3.1` on the URL
form does not work, and fails with a git error that names a repository nobody asked for.

Tracking `main` instead is a reasonable choice if you want unreleased work. `install.sh` says
so when it sees it, rather than calling your install stale.

Editing `extraKnownMarketplaces` in `settings.json` by hand is not an install path. Claude Code
reads that key when a session starts, so `claude plugin install` reports the plugin missing
until then. Use `claude plugin marketplace add`.

Re-running `install.sh` from an untagged checkout leaves any pin in place, so the skills stay
on the pinned tag while the hooks and libraries move ahead of it.

**Both steps are needed, and neither works alone.** The plugin gives you the skills, namespaced
`/session-kit:rename-session` and so on, so they cannot collide with a skill of the same name from
somewhere else. `install.sh` gives you the hooks and the libraries those skills source: install
only the plugin and the skills appear but fail on first use, because the library they source is
not there yet. Order does not matter.

If an older version of this kit installed the skills into `~/.claude/skills`, a re-run of
`install.sh` retires those copies, because a bare copy shadows the namespaced one. It only removes
a copy it recognises as its own; anything written by another tool is reported and left alone.

After the suite passes, the installer checks that the copy it just installed loads. Re-running
it is safe.

To confirm it works, run the same listing against the installed copy:

```bash
. ~/.claude/session-kit/core/sessions.sh && cs_list
```

You should get the three columns shown above. If nothing prints, or the name column comes
back empty, the usual cause is a missing `jq` (see
[docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)). The three skills are available in any new
session; `/session-kit:rename-session` is the quickest one to try.

The hooks start working in your next session. Wiring them is the **last** thing the installer
does, after everything else is installed and checked, so a run that breaks earlier never
reaches `settings.json` at all.

`settings.json.session-kit.bak` holds the version from just before the last real change, so
you can undo that change yourself at any time.

It is a one-step undo, not a permanent copy of your pre-kit config. An ordinary re-install
changes nothing, so it leaves the backup alone. When the kit's own set of hooks does change,
the next install backs up the file as it stood that day, our hooks included.

To get your config as it would be without this kit, do not reach for that file. Run
`./install.sh --uninstall`, which takes out our four hooks and leaves everything else
exactly as it is, including hooks you added after installing.

To drop a single hook afterwards, delete its line from `settings.json`; to remove all four,
run `./install.sh --uninstall`.

## Upgrading

Two halves, matching the two halves of the install. Re-run the installer for the hooks
and the libraries:

```bash
git -C ~/claude-session-kit pull && ~/claude-session-kit/install.sh
```

Then update the plugin for the skills:

```bash
claude plugin update session-kit@session-kit      # restart to apply
```

`/plugin update session-kit@session-kit` may do the same thing where your host provides that
slash command. An interactive CLI session does provide it, confirmed on 2.1.246. The VS Code
extension does not, and neither does `claude -p`, so the CLI form above is the one that works
in every host. If `claude` is not on your `PATH` it ships inside the extension:

```bash
~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude plugin update session-kit@session-kit
```

Use `~/.vscode-server/extensions/...` on a remote or WSL host.

In VS Code there are two other routes, both verified in the extension manifest rather than
guessed: the command palette entry **Claude Code: Install Plugin**, and a URI handler, which
accepts `vscode://anthropic.claude-code/install-plugin?plugin=<name>&marketplace=<owner/repo>`.
Neither is a chat slash command.

You do not have to remember which half is behind. The installer reads the plugin's
installed version and says which of the four cases you are in: not installed at all,
marketplace added but plugin missing, installed and matching this checkout, or installed
at an older version with the update command to run. `--dry-run` reports it too.

You do not have to remember to re-run it either. A pull only updates the checkout, and the
deployed tree at `~/.claude/session-kit` stays on whatever the last install put there, which
used to go unnoticed until something behaved like the old version. From a development
checkout the kit now says so at the moment the gap opens: `git pull`, a branch switch and
`git pull --rebase` each check whether the files the installer deploys have changed since the
deployed commit, and print the differing files and `bash install.sh` if they have. It compares
content rather than version labels, so a pull that only touched docs or the test suite stays
quiet. Nothing to enable: the hooks live in `guardrail/`, which `install.sh` already points
`core.hooksPath` at, so they arrive with the pull that brings them.

It runs the test suite first and refuses to install if anything fails, so a tree the tests
reject never reaches `~/.claude/session-kit`. Only kit code is replaced: your notes, handoff
folders, transcripts, and your edited `config` are left as they are. In `settings.json` it
adds only what is missing, so nothing is duplicated and no other tool's hook is touched.
One thing to know: if you deleted one of the four hooks, re-running the installer puts it
back, because "install" means "wire my hooks". Use `--uninstall` if you want them gone.

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

`0 failed` is the answer you want, and the last line tells you which Claude Code versions
the kit has passed against on this machine. A skip is fine; it means a check had no
data to run against.

Every passing run adds that version to the record, so once you have been through a few
updates the line grows into a span, `verified against Claude Code 2.1.222 to 2.1.231
(6 versions)`. The count is there because the ends were tested and the middle was not.
The kit only speaks up on a version that is not in the record, so keeping several
sessions open on different versions costs you nothing.

If something fails, [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) works through it by
symptom. To report it, paste the report rather than your terminal:

```bash
bash ~/.claude/session-kit/tests/smoke.sh --report
```

That report is built to be published. It carries versions, check names, and the first eight
characters of a session id, never a title or a path. The terminal output is deliberately not
redacted, because seeing the offending title is what makes a failure debuggable on your own
machine.

## Good to know

- Works with bash and zsh. The full test suite runs under both, on macOS and Linux.
- The kit reads Claude Code's own files but only ever appends to them. It never
  rewrites a transcript and never touches VS Code's database.
- Your notes live in their own folder. Uninstalling the kit never deletes them.
- The timing knobs (when drift checks start, how often they repeat, the handoff
  pickup window) live in `~/.claude/session-kit/config`, seeded at install with
  every default shown. To change one, uncomment its line and edit the number;
  upgrades never overwrite your edits. If you work from a checkout without
  installing, copy `config.example` to that path yourself.
- Claude Code's internals are undocumented and can change. The kit degrades safely
  when they do: the hooks go quiet instead of erroring, any command you run yourself
  warns that internals may have moved and names the check to run, and if the
  background re-test comes back failing you get told in your next session rather than
  having to go looking.
- Built and verified on Claude Code 2.1.x, with the real-data suite also passing
  over transcripts written by 20 different 2.1.x versions. Anything older is
  untested. That is only a starting point though: once the kit has run its check on
  your machine it keeps its own list of the versions that passed there, and the
  warning goes by your list.

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
No. The installer wires all four, but each works alone, so delete the lines you do not
want from `settings.json`. Re-running the installer puts them back, so use
`./install.sh --uninstall` if you want them gone for good. The skills work with no hooks
at all; you just lose the automatic reminders. They do still need `install.sh`, for the
libraries they source.

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

Removes the installed libraries and the knobs config (it configures nothing once
the kit is gone), along with any bare skill copy an older version of the kit left
in `~/.claude/skills`. The skills themselves come from the plugin, so remove that
separately, and **order matters**:

```bash
claude plugin uninstall session-kit@session-kit    # first
claude plugin marketplace remove session-kit       # only after
```

Reversed, the uninstall fails: it resolves the plugin through the marketplace and cannot find it
once that entry is gone. Neither command removes the plugin's cache directory under
`~/.claude/plugins/cache/session-kit/`, and `claude plugin prune` does not either, since it only
handles auto-installed dependencies. Delete it by hand if you want the disk space back. It leaves your notes
(`~/.claude/session-notes/`), your handoff folders (`~/.claude/session-handoffs/`),
and every transcript exactly where they are. The kit never owned those. It also
takes its four hooks back out of `settings.json`, backing the file up first, so
nothing is left firing at a path that no longer exists. Hooks it did not put
there are not touched.

## Working on the kit

```bash
bash tests/run.sh          # the fixture suite, runs on any machine, gates every install
bash tests/smoke.sh        # the real-data suite, checks the kit against your ~/.claude
```

`run.sh` is the gate. `smoke.sh` passes or skips depending on the machine it runs on, which
is the point, so it is never a required check. The design records under `docs/` say why
every rule exists; read them before changing one.

## Related projects

- **[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit)**: the sibling
  kit. It keeps the preferences you teach Claude across sessions and machines, where this
  kit looks after the sessions themselves.

Released versions and what changed in each: [CHANGELOG.md](CHANGELOG.md).

MIT licensed, see [LICENSE](LICENSE).
