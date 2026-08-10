---
name: handoff
description: Hand work off cleanly — either bundle sessions for another machine, or split an overgrown session into a fresh one on the same machine. Use when the user wants to move work to another computer, export/import sessions, split a session that drifted into a second topic, or continue work from a handoff bundle or folder.
---

# Handoff

Two different endings share one skill because they share the hard part: writing a
note good enough that the receiving side needs nothing else.

## 0. Name the mode — first line, always

Decide from what the user said; ask only if genuinely unclear:

- Another machine involved ("my laptop", "export this", "take this home") →
  **cross-machine**: the result is a bundle file the user carries.
- Same machine, session overgrown or two-topics ("split this", "this drifted") →
  **split**: the result is a folder plus a fresh session; nothing moves.

State the chosen mode as the first line of your reply — "This is a split, so the old
session stays put and gets a guard" — so a wrong inference costs one correcting
sentence, not the whole flow. Never silently guess.

## 1. Draft the note (both modes — this is the actual work)

The note is the most valuable artifact in any handoff. Write it from the
conversation; never generate it mechanically. Sections:

- `## Context` — what this work is, one paragraph.
- `## Decided` — conclusions that must not be relitigated, each with its one-line
  why. Include decisions that were REVERSED and why, or the new session will
  relitigate them from scratch.
- `## Open threads` — what is unfinished and its exact current state ("tests written,
  2 failing on zsh" beats "tests in progress").
- `## Next` — the first thing to pick up, in actionable form.
- `## Assertions` — 3–5 specific claims the reader must be able to restate after
  reading ONLY this note. Pick load-bearing facts stated once and briefly — those are
  what get lost. This is the note's quality bar, checked at claim time.

Write it to a temp file, show the user, adjust, then hand the file to the script.

## 2a. Cross-machine ending

```bash
handoff/export.sh -n <note.md> "<session ref or id>" [more refs...] [-- <loose files>]
```

Ambiguous refs refuse with candidates — pick with the user, never guess. Tell the
user where the bundle is and that they move it themselves (scp, drive, anything).
On the other machine: `handoff/import.sh <bundle>` — it verifies checksums before
touching anything and prints this note at the end.

## 2b. Split ending

```bash
handoff/split.sh -n <note.md> -t "<short topic label>"
```

This writes the folder and puts a pending guard on the CURRENT session. Then tell
the user, exactly:

1. Open a **fresh** session for the split-off topic.
2. Type anything — their first message surfaces the pending handoff automatically
   (the session-guard hook watches for unclaimed handoffs), and that session's
   agent claims it and receives the note as seed context. Manual fallback if the
   hook is not wired there: run `handoff/claim.sh <folder>` in the fresh session.

**Claiming side (if you are the fresh session):** after `claim.sh` prints the note,
check each `## Assertions` entry — can you restate it from the note alone? If any
fails, say so NOW: the old session is still alive and can fix the note this minute.
That check is the whole reason assertions exist; a failure discovered weeks later
is unfixable.

**Afterwards, in the old session:** a reminder will surface once per reopening that
the topic moved. Questions about what happened before the split — answer normally;
the old transcript is the only place the full argument survives. If the user decides
the work belongs back here after all: `handoff/release.sh` removes the guard in one
step. The folder is never deleted either way — it is the record of why the split
happened.

## What neither mode does

No transport (the user moves bundles), no merging of diverged sessions, no deleting
of old sessions or folders. When something refuses — a checksum, a collision, an
ambiguous ref — the refusal message says exactly why; relay it, do not work around
it.
