# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed
> about undocumented behaviour the kit depends on. The decisions those observations drove
> live in the `DESIGN-*.md` records, which cite these by number. For how the kit behaves,
> read [FLOWS.md](FLOWS.md).

    Observed against:  Claude Code 2.1.220, 2.1.221, 2.1.222
    Platform:          macOS, VS Code extension
    Last re-verified:  2026-08-12
    Needs to re-run:   jq, a live VS Code session, read access to the extension bundle

Nothing here is promised by Claude Code. Every entry is an observation with a date, a
version, the surface it was read from, and how it was checked, so it can be re-run rather
than believed. **Roughly half of these reversed on first contact**, which is what
reverse-engineering undocumented software looks like; the ones marked `Supersedes` are the
ones that moved, and a decision resting on those deserves more scepticism than one resting
on an entry checked across three versions.

## The surfaces

| Surface | Path | Written by | Lifetime |
|---|---|---|---|
| Transcript | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | Claude Code, append-only | permanent |
| pid-file | `~/.claude/sessions/<pid>.json` | Claude Code CLI at session start | one process; pruned |
| Extension bundle | the VS Code extension's `package.json` and `extension.js` | Anthropic, per release | per release |
| CLI binary | ships a compiled regex that scrapes titles | Anthropic, per release | per release |
| `state.vscdb` | VS Code's own store | VS Code | never read or written by this kit |

## The three identities

### O1. One session has three identities, joined by the session UUID

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    all three, compared side by side
    How:        read a live session's transcript, pid-file, and rendered tab together
    Needs:      jq

| Layer | Example | Where it lives | Who writes it |
|---|---|---|---|
| Display title | "Review memories and feedbacks" | the transcript, as `ai-title` / `custom-title` lines | `ai-title` by Claude Code from the opening message; `custom-title` by `/rename` or by this kit |
| CLI registration name | `documents-2d` | `~/.claude/sessions/<pid>.json` (`name`, `nameSource`) | Claude Code CLI at session start; wiped back to derived on restart |
| Transcript identity | `0d15803a-…` | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | Claude Code, one file per session |

The transcript filename *is* the id, and the pid-file carries it in a `sessionId` field.
Identity was never ambiguous; only the human-readable label was.

## The transcript

### O2. Transcripts carry title entries as their own line types

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    transcript, and the CLI binary
    How:        read raw JSONL; found the CLI's compiled regex "customTitle":"([^"]+)"
    Needs:      jq
    Supersedes: "transcripts carry no title/summary entries", wrong, corrected the same day

`{"type":"ai-title","aiTitle":…}` from the opening message, and
`{"type":"custom-title","customTitle":…}` appended by the built-in `/rename`. The CLI
scrapes `customTitle` straight out of the raw JSONL, alongside a title record of
`firstPrompt` / `agentName` / `customTitle` / `aiTitle` / `summary`. **The display title is
file-backed and addressable**, not locked inside VS Code's sqlite.

### O3. `ai-title` is set from the opening message and never revised

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    transcript
    How:        18 byte-identical ai-title lines in one 75-turn session
    Needs:      jq

So any session that outgrows its first question carries a stale title. The title as a
whole is revisable via `custom-title`; it is the automatic one that never moves.

### O4. `ai-title` is re-emitted immediately after every `custom-title`

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    transcript
    How:        exact repeating pairs at lines 275/276, 295/296, 307/308 of one transcript
    Needs:      jq

In any active session the last title line is almost always an `ai-title`. **A resolver
that tails the file for "the most recent title" discards the user's rename every time**,
and would pass a casual test, because the clobbering `ai-title` only lands once another
message is sent.

This is the sharpest trap in this file. See the naming record for what the kit does about
it.

## The pid-file

### O5. The pid-file is per process, and only for sessions that ran on this machine

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    pid-file
    How:        keyed by pid; carries procStart / startedAt for the live process only
    Needs:      jq

Imported transcripts have no registration at all.

### O6. Derived names are not unique

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    pid-file
    How:        two concurrent sessions (99f81837, 280dbe52) both held documents-7c
    Needs:      jq

Any resolve-by-name path must handle ambiguity explicitly rather than assume one hit.

### O7. `nameSource` is absent on explicitly-named sessions

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    pid-file
    How:        8 live pid-files compared: 7 × documents-XX with derived, 1 named with no nameSource
    Needs:      jq

Absence is the "a human named this" marker, not a missing field to default in.

### O8. An explicit name does not survive a process restart at the pid layer

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    pid-file, against the transcript
    How:        observed live: pid 26094 to 45158 turned detector-heuristic-testing into
                documents-41 with nameSource derived; the transcript's custom-title for the
                same session was untouched. pid-file count also fell from 10 to 3 in a day
    Needs:      jq

The pid layer is not merely ephemeral, it is **actively destructive of names**, and Claude
Code prunes pid-files.

## The tab

### O9. The tab title is a runtime property of the live webview panel

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    extension bundle
    How:        jq '.contributes.commands[]' package.json: 23 commands, none renames.
                extension.js handles request.type === "rename_tab", whose handler does
                this.panelTab.title = request.title and swaps the tab icon
    Needs:      jq, read access to the extension bundle

Set by the running CLI over its existing extension channel, through the sanctioned VS Code
API. There is no palette entry and nothing invocable from outside.

### O10. `state.vscdb` only caches the rendered tab, after the fact

    Observed:   2026-08-04 · 2.1.221 · macOS, VS Code extension
    Surface:    inferred from O9; the file itself was never read
    How:        deduction from the runtime-property finding
    Needs:      nothing

An offline write would be both an unsupported write to a file VS Code holds open, and
pointless for any live session, whose panel would overwrite it.

### O11. The built-in `/rename` writes both layers, and does not refresh a live tab

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    pid-file and transcript
    How:        live experiment. Ran /rename in a live VS Code session; all three pid-file
                fields changed as predicted (documents-07 / derived / null to a real name /
                absent / a timestamp) and the tab title did not change
    Needs:      a live VS Code session, jq
    Supersedes: "the tab is unreachable", claimed and retracted 2026-08-05

The tab title is not the session `name`; they are separate values with separate storage.
What does not happen is a **live refresh** of an already-open tab.

### O12. The tab reads `custom-title`, and refreshes on reopen

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    transcript, against the pid-file
    How:        live experiment. Ran /rename, closed the tab, reopened the session, and the
                tab showed the new name
    Needs:      a live VS Code session

The deduction that this comes from `custom-title` and not the pid-file: reopening starts a
new process, which writes a fresh pid-file with a **derived** name, verified separately
when a restart turned `detector-heuristic-testing` into `documents-41`. A tab reading the
pid-file would show `documents-41`. It shows the custom name, so the transcript entry is
the source.

Consequence: **the tab is reachable for any session given a `custom-title`**, not only via
`/rename`. Appending one to a dead or imported session gives it a correct tab title the
next time it opens. The only thing still impossible is retitling a tab that is currently
open, in place.

## Resolving a display name

### O13. Precedence for a resolved display name, highest first

    Observed:   2026-08-05 · 2.1.221 · macOS, VS Code extension
    Surface:    transcript and pid-file
    How:        derived from O2, O7, O8 and O12, then confirmed by the reopen experiment
    Needs:      jq
    Supersedes: an earlier ordering that put the pid-file first, corrected 2026-08-05

1. transcript last **`custom-title`**: durable; survives restarts and import, and the only
   explicit record for a dead or imported session
2. pid-file `name` with `nameSource` absent: explicit, but ephemeral
3. transcript last **`ai-title`**
4. `firstPrompt` / first user message
5. pid-file `name` with `nameSource` of `derived` or `auto`: `documents-41`, which tells
   you nothing and collides across concurrent sessions
6. short id

The earlier ordering assumed the two always agree, because `/rename` writes both at once.
That broke once `custom-title` could be written on its own: the transcript entry is then
the *newer* value, and ranking the pid-file above it would let a stale name shadow a
rename the tab is already displaying.

**Precedence is by entry type, never by file order**, because of O4. Select by type first,
then take the last of that type.

## Version behaviour

### O14. Version skew between layers is the normal state

    Observed:   2026-08-04 · 2.1.220 and 2.1.221 together · macOS, VS Code extension
    Surface:    pid-file and extension bundle
    How:        all pid-files reported 2.1.220 while the installed extension was already
                2.1.221, because running processes predate the update
    Needs:      jq

Not an anomaly. Accessors must tolerate skew rather than assert a single version.

## Evidence summary

| Claim | How it was checked |
|---|---|
| No rename command exists | `jq '.contributes.commands[]' package.json` on the 2.1.221 extension: 23 commands, none rename |
| Title set at runtime by CLI | `rename_tab` handler in `extension.js` assigns `panelTab.title` |
| `nameSource` absent when named | 8 live pid-files in `~/.claude/sessions/` compared |
| pid-file is ephemeral | keyed by pid; contains `procStart` / `startedAt` for the live process only |
| Titles are file-backed | the CLI ships a compiled regex, `"customTitle":"([^"]+)"` |

## Not verified

The internal layout of `state.vscdb`. Reading it was blocked by a permission guard, and
O10 makes it moot: the kit never reads or writes it.
