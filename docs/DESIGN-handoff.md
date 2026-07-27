# Design: session handoff between machines

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
   machine's project dir; write each session's title to the durable name sidecar
   (DESIGN-naming.md) so it survives the move; print the HANDOFF.md note.
3. **Skill `/handoff`** — interactive wrapper: pick sessions, draft the HANDOFF.md from
   the current session's state, run export, tell the user where the bundle is.

## Non-goals

- No transport. The bundle is a file; the user moves it (scp, Downloads, whatever).
- No merging of sessions. Import installs them as-is, separate. (A merge tool was
  considered and rejected during the prototype: auto-compaction makes a merged
  transcript lossy anyway, and synthetic parent-chains are fragile.)
- No cwd rewriting. Imported sessions keep their original `cwd` fields; resume
  continues in the target machine's directory, and that mismatch is accepted.

## Open questions (answer before building)

- Where import places sessions: current project dir (what the prototype did — they
  show in the picker where you work) vs. recreating the source's encoded-cwd dir
  (truer, but they land in a project dir that may not exist on the target). Prototype
  experience says current project dir; revisit if it pollutes pickers.
- Whether import should also carry pending non-repo state automatically (e.g. the
  feedback tracker at `~/.local/share/claude-feedback/`) or leave that to the memory
  kit's own sync story. Leaning: leave it out; one kit per concern.
