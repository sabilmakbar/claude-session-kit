# Changelog

Notable changes, newest first, in the spirit of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**How entries are written, from 0.2.0 onwards.** Each notable change gets one line under a
category, naming the pull request that delivered it so the reasoning is one click away. Routine
work is folded into a summary line rather than enumerated, because a changelog that lists
everything is a `git log` with extra steps. The date on a version is the date it was released.

0.1.0 below carries no pull request links, on purpose. Most of what it contains arrived as direct
commits before this repo required pull requests, so anchoring the minority that did have one would
make those changes look like the substance of the release when they are not.

**What a version means here.** The kit is installed by cloning and upgraded by re-running
`install.sh`, so there is nothing to pin in a package manager. A version names a state of `main`
that was tagged, and the tag is what you check out to go back to it. Versions move independently
from claude-memory-kit: the two share conventions, neither depends on the other, and a bump in one
says nothing about the other.

## Unreleased

### Added

- A pull that leaves the deployed tree behind now says so, at the moment the gap opens.
  `git pull`, a branch switch and `git pull --rebase` compare the files `install.sh` deploys
  against the deployed commit and name the differing files and the command to fix them. The
  check runs in the checkout rather than in the deployed tree, because the deployed tree has
  no `.git` and records no path back to its source, while the checkout knows where the
  installer deploys. It compares content rather than version labels: every commit moves
  `git describe`, so a label comparison would fire through all of normal development, and a
  pull touching only docs or the test suite is silent. Wired through the `core.hooksPath` the
  commit guardrail already uses, so the hooks arrive with the pull that brings them.

### Tested

- The drift check across both halves: the reporting cases each paired with a control that
  must stay silent, and the three wrappers driven by real git operations, including a pull
  between two local clones, so a dead wrapper file cannot pass. The watched path list is
  checked against what the installer actually deploys into a sandbox, so a file added to the
  installer and not to the list fails the suite instead of going unwatched.

## 0.3.1

### Added

- `install.sh` names the action for the state the machine is in, rather than reporting a
  single "installed or not". Four states need four different commands: nothing installed,
  marketplace added but plugin missing, installed and matching this checkout, or installed at
  an older version, which is offered `/plugin update` with the version it is on. That last one
  was silent before: the hooks and libraries came up to date while the skills stayed behind.
  `--dry-run` reports the state too, since reading it changes nothing.
- The plugin declares a SessionStart hook that reports a missing kit tree. Installing only the
  plugin is the one state `install.sh` cannot report, because it only speaks while it runs, and
  the hook fires from the plugin cache exactly when the plugin is present. It depends on nothing
  it reports on: no `jq`, no kit file.
- `install.sh` reports when this checkout is behind its tracking branch, from refs already
  fetched, so no network call is added. The plugin lives in its own clone, so a stale checkout
  and a stale plugin are separate facts and get separate lines.

### Tested

- Integration coverage for the installer end to end: a checkout behind its tracking branch is
  reported, a current one says nothing, uninstall prints the plugin removal order with the
  plugin before the marketplace, and uninstall leaves the plugin cache alone because the kit
  does not own it. Filesystem and git only, so it runs on CI.
- `tests/integration-plugin.sh` covers the rest, which needs the real `claude` CLI: that
  `marketplace add` and `plugin install` do not run each other, that a path source is not
  cloned, that the cache is keyed by the manifest version, that add and update are no-ops when
  satisfied, that nothing removes the cache, and that removing the marketplace first leaves
  the plugin unresolvable. It skips itself with exit 0 when the binary is absent, and is wired
  into CI so it starts running if a runner ever ships the CLI.

### Documented

- `docs/INTERNALS.md` records the plugin surface: how a marketplace is stored depends on its
  source, a remote one cloned into `plugins/marketplaces` and independent of your checkout
  while a path is referenced in place, the cache is keyed by the version in plugin.json, nothing runs at install and
  hooks are the only execution surface, removing a marketplace disables its plugin and orphans
  the cache, `plugin install` cannot pin a version or ref, and `marketplace add` and
  `plugin install` are a lookup rather than a chain: neither runs the other, and refreshing
  has two separate rungs in `marketplace update` and `plugin update`.

- Uninstall documents its required order. Taking the marketplace out before the plugin makes
  `plugin uninstall` fail, because it resolves the plugin through the registry, and the cache is
  then unremovable through the CLI. `install.sh --uninstall` prints the order, and the README
  states that neither command removes the plugin's cache directory.

- `docs/DEPENDENCIES.md` names the `claude` CLI as an install-time requirement for the half
  that carries the skills. It was listed only as a runtime dependency, or not at all.
- `docs/FLOWS.md` no longer says the shape gates run before "the tree, the skills and the
  config" are on disk. The skills have not been part of that since they moved to the plugin.
- The documented update command is `claude plugin update`, not `/plugin update`. The slash form
  is not available in every host — the VS Code extension does not provide it — so an
  instruction offering only that form named a command the reader could not run. The slash form
  stays as a parenthetical, and the docs say where the binary lives when it is not on `PATH`.
  Which hosts do provide the slash command was not established, and the docs say that rather
  than implying otherwise. VS Code offers two other routes, both read from the extension
  manifest: the command palette entry "Claude Code: Install Plugin", and a URI handler at
  `vscode://anthropic.claude-code/install-plugin?plugin=&marketplace=`. Recorded in INTERNALS.

### Fixed

- A skill now names the fix when the kit half is missing. Installing only the plugin left the
  skills present and failing on first use with a bare "no such file or directory" that never
  mentioned `install.sh`. This is the one state the installer cannot report, because it only
  speaks while it runs, so the skill has to. Each skill that depends on the libraries they source says
  what a missing path means and which command fixes it.

## 0.3.0

### Changed

- Skills now ship as a Claude Code plugin and are invoked with the `session-kit` namespace
  (`/session-kit:rename-session`), so they cannot be shadowed by a skill of the same name from
  another kit or from your own `~/.claude/skills`. `install.sh` no longer writes that folder; a
  re-run retires copies an older version left there, and reports rather than deletes anything it
  does not recognise as its own. Both install steps are now required: the plugin carries the
  skills, `install.sh` still carries the hooks and the libraries those skills source.
- `install.sh` now reports whether the plugin half is present, instead of printing the plugin
  commands unconditionally. A half-install is the failure mode the split introduced: skills
  registered with no libraries under them fail on first use, and the run is the cheapest place
  to name that (#31).

## 0.2.0

Released on 2026-08-18.

A hardening release. Nothing in the interface changed: the same three skills, the same four
hooks, the same install command. What changed is how the kit behaves when something is wrong,
which is where 0.1.0 was weakest.

### Fixed

- **The wrong-session check failed in both halves it was made of** ([#21]). Routing could not
  reach a well-named session, because it matched only the resolved title while the rename skill
  requires a title to name the arc of the work rather than the topic asked about. It now falls
  back to the session's own directory and conversation when the title misses. Separately, the
  check reached the agent once per opening and never again that sitting, which is not when
  off-topic messages arrive; a one-line version now comes with every message. It still offers
  three routes and never refuses, and that decision is now recorded rather than assumed.

### Added

- **The kit can name its own release** ([#19]). The failure report and smoke output carry the
  installed version, so a pasted report says which build it came from instead of leaving the
  reader to guess.
- **A test that fails when the installer's file list falls behind the repo** ([#22]). The list
  is maintained by hand in two places, so a forgotten file used to install silently incomplete.
  The expectation is derived from the repo rather than restated, and the test also asserts what
  must *not* ship.

### Changed

- **Skills name their libraries by absolute path in the repo itself** ([#26]). The installer
  used to rewrite relative paths at copy time, so the checked-in file and the installed file
  differed by design. They are now byte-identical, pinned by a test. This is what a future
  plugin release needs, since a plugin is cloned verbatim with no install step to run.
- **The handoff skill says where to draft a note** ([#17]), which stops working copies of
  handoff notes accumulating in whatever directory the session happened to be in.

### Documentation

- **Every doc and inline comment reconciled against the code** ([#24]). Six real drifts, three
  of them introduced by [#21] in the same week. The user-facing guide was still describing the
  bug [#21] had just fixed.
- **The install section says two things and means two** ([#23]). It promised two safety
  properties then listed seven, in one sentence of 58 words, most of it duplicating a reference
  doc that already explained it properly.
- **A convention for which dates belong in a header and which stay in prose** ([#18]), settling
  a judgement call that had sat open for four days because it read as a style nit.
- **Issue forms and a pull request template** ([#28]). The bug form asks for
  `tests/smoke.sh --report` first, not the plain run: the report is built to be published and
  the terminal output deliberately is not. The kit has said that since 0.1.0 without ever saying
  where to send it. Nothing about the installed kit changes.
- **One duplicated wiring string removed** ([#25]). `settings.snippet.json` owns that command,
  and a second copy in a comment is a drift risk rather than a convenience.

### Compatibility

No migration. Re-run `install.sh`; it is the upgrade path. Existing installs keep working
unchanged, and the skill paths are rewritten in place by the re-install.

One behaviour change worth knowing: an install to a custom `CLAUDE_SESSION_KIT_PREFIX` now
writes skills that name `~/.claude/session-kit` regardless of the prefix. That variable exists
for the test harness, which never sources a skill.

[#17]: https://github.com/sabilmakbar/claude-session-kit/pull/17
[#18]: https://github.com/sabilmakbar/claude-session-kit/pull/18
[#19]: https://github.com/sabilmakbar/claude-session-kit/pull/19
[#21]: https://github.com/sabilmakbar/claude-session-kit/pull/21
[#22]: https://github.com/sabilmakbar/claude-session-kit/pull/22
[#23]: https://github.com/sabilmakbar/claude-session-kit/pull/23
[#24]: https://github.com/sabilmakbar/claude-session-kit/pull/24
[#25]: https://github.com/sabilmakbar/claude-session-kit/pull/25
[#26]: https://github.com/sabilmakbar/claude-session-kit/pull/26
[#28]: https://github.com/sabilmakbar/claude-session-kit/pull/28

## 0.1.0

Released on 2026-08-12.

First tagged release, so there is nothing to compare against: what follows describes what 0.1.0
contains rather than what changed. It is the point at which the interface is considered settled
enough to name.

### Added

- **Three skills.** `/rename-session` writes a real title for the current session, `/session-note`
  saves a "decided / done / next" note that greets you when you reopen it, and `/handoff` moves
  sessions between machines or splits an overgrown one.
- **Four optional hooks**, all silent unless they have something to say: a note handed back on
  reopen, a reminder of where a split-off topic went, drift detection when a session outgrows its
  title, and a re-test after Claude Code updates. If anything inside them fails they do nothing.
- **A read-only view of your sessions.** `cs_list` and `cs_find` resolve a session by name fragment
  or id prefix. Neither writes.
- **Cross-machine handoff.** Export writes a checksum-verified bundle; import verifies everything
  before writing anything, so a bundle that fails a check leaves the machine untouched. Importing
  the same bundle twice does nothing.
- **Same-machine split**, which writes a plain folder rather than a bundle because nothing crosses
  a machine gap, with claim and release steps.
- **Hook wiring at install time**, added to `~/.claude/settings.json` and removed again by
  `--uninstall`. The installer refuses a file it cannot merge into before deploying anything.
- **Tunable knobs in a config file**, seeded at install with every default shown, and preserved
  across upgrades.
- **A record of every Claude Code version the kit has passed against** on a machine, not only the
  newest, so reopening an older session is not treated as news.
- **A once-a-day notice when the kit itself has stopped working**, because silence is its healthy
  state and a broken kit would otherwise look identical to a working one.
- **Two test suites.** A fixture suite that gates every install, and a real-data suite that checks
  the kit against your own `~/.claude` and skips where you have no data.

### Documentation

A plain-language `HOW-IT-WORKS.md`, a diagram-led `FLOWS.md`, three decision records with numbered
decisions, and a separate `INTERNALS.md` recording what was observed about Claude Code rather than
what this kit decided. Plus `TROUBLESHOOTING.md` by symptom, `DEPENDENCIES.md`, `CONTRIBUTING.md`
and a LICENSE.

### Known limitations

- **Claude Code's internals are undocumented.** Everything the kit reads from them is in
  [docs/INTERNALS.md](docs/INTERNALS.md), each entry carrying the date, version and method behind
  it. Four of the fifteen cannot be checked by a script, because they need a live VS Code session.
- **The fixture suite cannot detect drift.** Fixtures encode what we believe the format to be, so
  they pass forever against a stale belief. Only the real-data suite closes that, and it needs your
  machine.
- **A tab already open cannot be retitled in place.** A rename is live immediately in the session
  picker and reaches the tab the next time that session is opened.
- **Built and verified on Claude Code 2.1.x**, with the real-data suite also passing over
  transcripts written by 20 different 2.1.x versions. Anything older is untested.

### Compatibility

Bash and zsh, macOS and Linux. Needs `jq`; moving sessions between machines also needs `shasum` or
`sha256sum`.
