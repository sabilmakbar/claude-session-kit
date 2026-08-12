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

Nothing yet.

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
