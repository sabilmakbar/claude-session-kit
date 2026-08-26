# Troubleshooting

Symptom, then check, then fix. If you are not sure anything is wrong, run the doctor first:
`bash ~/.claude/session-kit/tests/smoke.sh`. The README explains what its output means.

This file covers faults. Questions about behaviour that is working as intended live in the
[FAQ](FAQ.md), and one of them is listed at the bottom because it looks like a fault.

## Nothing happens: no note, no reminders, no drift check

**Check.** The installer wires the four hooks, so the usual cause is an install that did
not finish, or a session that was already open when it ran:

```bash
jq '.hooks | tostring | test("session-kit")' ~/.claude/settings.json
```

`false` means nothing is wired.

**Fix.** Re-run `./install.sh`, then start a new session. Hooks are read at session start,
so an already-open session will not pick them up.

The three skills work with no hooks at all. If `/session-kit:rename-session` works but you never get a
note or a reminder, this is the reason.

## A session said "claude-session-kit: ..." out of nowhere

Not a bug. The hooks say nothing on a normal day, so the kit tells you when it has
stopped working, once a day per fault, until it is fixed. There are three of these.

**`jq is missing, so the kit is doing nothing at all`.** Every part of the kit parses
JSON, so without `jq` all four hooks exit immediately and the skills refuse. Install it
(`brew install jq`, or your package manager) and everything resumes on the next prompt.
No re-install is needed. This can only happen after a working install, because
`install.sh` refuses to run without `jq` in the first place.

**`its last self-check failed`.** The kit re-tested itself after a Claude Code update
and something it depends on had moved. Read what:

```bash
bash ~/.claude/session-kit/tests/smoke.sh --report
```

Then follow the next section, which is about exactly this. The line stops on its own
once the suite passes again.

**`the skills are at X while the hooks and libraries are at Y`.** The kit installs in two
halves that version on their own: `install.sh` deploys the hooks and libraries, and
`claude plugin install` caches the skills. Updating one and not the other leaves them on
different releases, which works but is not what you asked for. The line names the half that
is behind and the single command that brings it up, either
`claude plugin update session-kit@session-kit` or re-running `install.sh` from your
checkout. It says nothing while your checkout sits between releases, because a development
tree has no release number for the plugin to match.

## A skill is missing, or fails the moment it runs

**Quickest check.** Re-run `install.sh`. It reads the plugin's installed version and says
which of four cases you are in: not installed, marketplace added but plugin missing,
installed and current, or installed behind this checkout with the update command to run.
`--dry-run` reports the same without touching anything.

**On updating.** The installer prints `claude plugin update` rather than `/plugin update`,
because the slash command is not available in every host. The VS Code extension does not have
it, and which hosts do is unconfirmed. If `claude` is not on your `PATH`, the binary ships inside the extension at
`~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`, or
`~/.vscode-server/...` on a remote host.

**Check.** The skills come from the plugin, the libraries they source come from `install.sh`,
and neither half works alone. Run `claude plugin list` and look for `session-kit@session-kit`,
then check that `~/.claude/session-kit/core/sessions.sh` exists.

**Fix.** Whichever half is missing:

```bash
claude plugin marketplace add sabilmakbar/claude-session-kit
claude plugin install session-kit@session-kit    # skills
~/claude-session-kit/install.sh                  # hooks and libraries
```

A skill that appears in the list and then fails on its first command is the second half
missing: each one sources a library under `~/.claude/session-kit/`, which only the installer
puts there. Plugins load at session start, so start a new session after installing.

**If you see each skill twice,** once bare and once as `session-kit:`, an older version of this
kit left a copy in `~/.claude/skills`. Re-run `install.sh`: it retires copies it recognises as
its own, and names any it will not touch.

## The installer refuses because of `settings.json`

Three different refusals, all of them before anything is written, and all of them
leaving the file exactly as it was.

| Message contains | Cause | Fix |
|---|---|---|
| `is not a valid JSON object` | the file does not parse at all | fix or move it, then re-run |
| `not a shape we can merge into` | it parses, but `hooks` is not an object, or an event we wire is not an array of groups | correct that key by hand, then re-run |
| `the settings.json merge could not run` | something inside `hooks` is malformed deeper than the check looks | same, and the message names the file |

Nothing is repaired for you on purpose. A wrongly shaped `hooks` holds something this
installer did not write, and rewriting it would be guessing at another tool's config.

Odd corners it does **not** refuse over: an event this kit never touches can be any
shape at all, a malformed group inside an event we do wire is left alone, and
unrelated top-level keys are never read. Those all install normally.

## The doctor reports a failure after a Claude Code update

Expected, and it is what the check exists for. The kit reads undocumented internals, so an
update can move something.

**Check.** Read the failing check name. `smoke.sh` names what it expected and what it got.

**Fix.** There is usually nothing to fix locally: the kit degrades to a worse name or goes
quiet rather than doing damage. Report it with the redacted report, not your terminal:

```bash
bash ~/.claude/session-kit/tests/smoke.sh --report
```

That report carries versions, check names, and the first eight characters of a session id.
Your terminal output is deliberately not redacted, because seeing the offending title is
what makes a failure debuggable locally. Do not paste that.

The warning repeats until the suite passes again. It clears itself once it does.

## `export` or `import` refuses

Every refusal is deliberate: the kit stops rather than writing something it cannot verify.
Match your message.

| Message contains | Cause | Fix |
|---|---|---|
| `sha256sum or shasum is required` | no checksum tool on this machine | install either one; both are stock on macOS and Linux |
| `is ambiguous` | your reference matched more than one session | rerun with one of the listed ids |
| `no session matches` | the reference matched nothing | `cs_find <text>` to find the right one |
| `has N unparseable lines` | the transcript is damaged | nothing to fix in the kit; that session cannot be bundled |
| `checksum mismatch` | the bundle was edited or damaged in transit | re-export and re-transfer |
| `already exists here with diverged content` | that session exists on this machine and has different content | nothing is overwritten by design; rename or remove the local copy first if you want the bundled one |
| `refused` plus `nothing was installed` | some earlier check failed | scroll up; the real reason is above this line |

Importing the same bundle twice is safe and does nothing, so a retry after fixing the cause
is free.

## A split will not claim

**Check.** Claim runs from the **fresh** session, not the one that split. `claim: this IS the
session that split` means you ran it in the wrong place.

**Fix.** Open a new session and type anything; the pending handoff surfaces on the first
message. Manual claiming never expires, so a missed 48-hour window costs you the nudge, not
the handoff.

`claim: $DIR has no 'from' file` means the folder was not written by `split.sh`.

## The installer says the plugin is "ahead of" the newest release

Not a fault. The skills came from a source that is not a release: an unpinned marketplace
serves the default branch, and a local path serves a working tree. On a development checkout
this is the expected state. To make the number meaningful, pin the marketplace to a tag; the
README's install shows the form, and D1 in [DESIGN-install.md](DESIGN-install.md) holds the
reasoning.

## The installer says a pin "has no effect"

The marketplace pin names a version below one already in the plugin cache, and the newest
cached version is the one that loads. Nothing removes cache directories automatically, so the
pin stays dead until you act. Remove the directory the installer names, then
`claude plugin install session-kit@session-kit`, or pin forward to a release at or above the
cached version. Background: O22 and O27 in [INTERNALS.md](INTERNALS.md).

## I edited a skill, but the running copy never changes

`claude plugin update` compares version labels and never content, so an edit under an
unchanged version silently stays out of the loaded copy, even from a marketplace that points
at your working tree. The loop that works is in CONTRIBUTING.md: `claude plugin uninstall`,
then `claude plugin install`, then a new session. Measured as O28 in
[INTERNALS.md](INTERNALS.md).

## Not a fault

**The tab title did not change after a rename.** Nothing is broken. See the [FAQ](FAQ.md).
