# Design: session handoff (between machines, and between sessions)

## The problem

Moving work between machines is manual today. The 2026-07-26 Linux→Mac move (the
prototype for this design) took: hand-picking transcript files, tar-ing them with a
hand-written WIP note, renaming files back to `<session-id>.jsonl` on the target,
checking for collisions, and installing them under the right project dir. Two lessons
from that run:

1. **Titles die in transit.** Descriptive names lived only in the export filenames;
   the import had to rename files to raw UUIDs (required for resume), so the titles
   survived only in a hand-written table inside the WIP note.
2. **A handoff is more than transcripts.** The useful bundle was transcripts + a WIP
   backlog + a held diff — state that belongs to no repo. The WIP note turned out to be
   the most valuable file in the bundle.

## Second use case: same-machine session split (drift guardrail)

A handoff is also the right move when a session's context has expanded way past its
topic, drifted to something else entirely, or started absorbing unrelated questions.
Instead of renaming the session (right only when the same work evolved), the fix is to
**split**: auto-draft a HANDOFF.md from the current session's state (open threads,
decisions made, artifacts touched), export it, and start a fresh session seeded with it.
The old session keeps its honest title; the new topic gets a lean context instead of
inheriting an overgrown one. Same-machine splits are handoff-lite: no transcripts in the
bundle, just the note (the old transcript stays put and resumable).

The naming feature's drift detector (DESIGN-naming.md) is the trigger: on drift it
offers a three-way fork — *rename* (work evolved), *split* (topic changed), or *wrong
session* (the user opened the wrong tab and asked something unrelated). Only **split**
reaches this doc. The wrong-session case produces no bundle at all: nothing has evolved
and nothing needs carrying over, so the remedy is an early warning, not a handoff.
Wiring: detector pings → user picks → `/handoff` drafts the note, for split only.

## Proposed format: one bundle, one manifest

```
session-handoff-<date>.tar.gz
├── manifest.json      # the part tonight was missing
├── sessions/<session-id>.jsonl   # original UUID filenames — no rename dance
├── notes/HANDOFF.md   # freeform WIP/backlog note (template provided, never generated)
└── files/…            # optional loose artifacts (diffs, patches)
```

`manifest.json` per session: id, **title**, source machine, source cwd, time range,
line count, sha256. Plus: bundle date, source hostname, kit version.

## Proposed pieces

1. **`handoff/export.sh <session-ref>… [files…]`** — resolve refs via `core/` (title
   substring or id), validate each transcript (valid JSON tail), write manifest,
   bundle. Refuses to run if a ref is ambiguous.
2. **`handoff/import.sh <bundle>`** — verify checksums; refuse on session-id collision
   with a *different* file (byte-identical = skip silently); install under the current
   machine's project dir; append each session's manifest `title` as a `custom-title`
   line in its transcript (DESIGN-naming.md) so the name survives the move and appears
   in the target machine's session picker; print the HANDOFF.md note.
3. **Skill `/handoff`** — interactive wrapper: pick sessions, draft the HANDOFF.md from
   the current session's state, run export, tell the user where the bundle is.

## Non-goals

- No transport. The bundle is a file; the user moves it (scp, Downloads, whatever).
- No merging of sessions. Import installs them as-is, separate. (A merge tool was
  considered and rejected during the prototype: auto-compaction makes a merged
  transcript lossy anyway, and synthetic parent-chains are fragile.)
- No cwd rewriting. Imported sessions keep their original `cwd` fields; resume
  continues in the target machine's directory, and that mismatch is accepted.

## Resolved questions (2026-08-04)

- **Where import places sessions: the current project dir.** Confirming the prototype's
  behaviour and the stated leaning. The alternative (recreating the source's encoded-cwd
  dir) is truer to the origin but lands sessions in a project dir that may not exist on
  the target, where nothing surfaces them. Revisit only if it pollutes pickers in
  practice.
- **Import does not carry pending non-repo state.** Confirming the leaning: one kit per
  concern. The feedback tracker at `~/.local/share/claude-feedback/` stays the memory
  kit's problem, and this kit does not reach into it.
- **Titles survive the move as `custom-title` transcript entries.** DESIGN-naming.md
  resolved the durable name to the transcript's own `custom-title` line rather than a
  kit-owned sidecar, which settles lesson 1 above: import appends each manifest `title`
  to the installed transcript, so descriptive names no longer live only in export
  filenames or a hand-written table.

  This is strictly better than the sidecar it replaces, because Claude Code reads
  `custom-title` itself — an imported session shows its real name in the normal session
  picker, not only in this kit's tooling. Imported sessions are also the safe case for
  writing it: no process is attached, so there is no concurrent writer to interleave
  with. Whether the VS Code *tab* picks the name up on open is untested (see the open
  item in DESIGN-naming.md); the picker entry does not depend on that answer.
