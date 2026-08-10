# Design: session handoff (between machines, and between sessions)

> **This is a decision record, not a user guide.** It is dense on purpose: it
> exists so that future changes know what they would be overturning. For how the
> kit behaves day to day, read [FLOWS.md](FLOWS.md). For setup, the README.

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
   backlog + a held diff: state that belongs to no repo. The WIP note turned out to be
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
offers a three-way fork: *rename* (work evolved), *split* (topic changed), or *wrong
session* (the user opened the wrong tab and asked something unrelated). Only **split**
reaches this doc. The wrong-session case produces no bundle at all: nothing has evolved
and nothing needs carrying over, so the remedy is an early warning, not a handoff.
Wiring: detector pings → user picks → `/handoff` drafts the note, for split only.

### Same-machine splits do not produce a bundle

Designed 2026-08-05. A same-machine split writes a **plain folder**, read once by the
fresh session, and no tarball is involved.

Ask what the bundle format actually buys: checksums, collision detection, a source
hostname. Every one of those exists because files crossed a gap between machines. On one
machine nothing crosses a gap (the old transcript never moves and stays resumable), so
the packaging is ceremony around a file that stays put.

That splits the feature along a real seam rather than an arbitrary one:

| | Carrier | Why |
|---|---|---|
| Cross-machine | `session-handoff-<date>.tar.gz` + manifest | files move; integrity and collisions matter |
| Same-machine | a folder holding the note | nothing moves; only the context transfers |

**Archive the folder, do not delete it.** The note is the most valuable artefact in a
handoff (lesson 2 above), and it is the only written record of *why* the split happened.
Deleting it buys a few kilobytes and cannot be undone; moving it out of the way gets the
same tidiness while keeping the evidence. Whatever performs the move must run **after**
the session that wrote it has finished; a session tidying up its own working files
mid-flight is how you lose them.

### Verifying the handoff: the note declares its own assertions

The tempting design (have a verifier quiz the fresh session and compare against the
original) fails whichever ground truth you pick:

- **Against the note**: the note is in the new session's context, so it passes always.
  That is a receipt, not verification.
- **Against the original transcript**: the note is *deliberately* lossy, so the verifier
  flags the new session for not knowing things that were never meant to transfer.

The sharpest failure is **retracted knowledge**. A good note records only the endpoints;
the transcript holds the endpoints *and* everything abandoned on the way. Worse, a
discarded approach is usually discussed at length and then dropped in one sentence, so it
is the *more* strongly represented of the two. A verifier grading against the transcript
would mark the fresh session wrong for giving the correct answer. (This design session is
the example: a sidecar was adopted and dropped, the tab was called unreachable and then
proved reachable, the renamer was scoped three different ways.)

So invert it: **the original session writes the note and, alongside it, the specific
claims a reader must be able to restate.** The verifier checks those and nothing else. No
fuzzy comparison against a whole transcript, so no false failures from abandoned
branches; and not trivially passable, because assertions can target things the note
states once and briefly. The session that did the work is also far better placed than any
grader to know which three facts are load-bearing.

**Point it at the note, not at the new session, and run it early.** On one machine the
original session is still sitting there, resumable, so a failed check does not mean
"keep the folder", it means "the note is inadequate and you can fix it right now". That
signal is only available in the same-machine case, precisely because nothing was torn
down. Used as a deletion gate it is a lot of machinery for a question whose safe default
is "keep the file"; used as a note-quality check it runs while the fix is still cheap.

### After a split, the old session becomes a record, not a workspace

A split that leaves the old session still working the same topic is not a split; it is a
fork, and you end up with two divergent contexts on one piece of work.

But two different things can be asked of the old session, and only one should be guarded:

- **Continuing the handed-over work**: redirect. That is what moved.
- **Recalling what happened before the split**: answer normally. The old session is the
  only place the *argument* survives; the note carries the conclusion.

A guard that blocked both would destroy the reason to keep the old session at all.

**Soft guard, not refusal.** Deciding "is this question about the handed-over topic" is
the same unproven content-matching as drift detection. A false positive on an injected
hint costs a sentence of noise; a false positive on a hard refusal blocks legitimate work
and leaves the user arguing with a hook. Same uncertain signal, very different blast
radius.

Mechanism: a `UserPromptSubmit` / `SessionStart` hook injecting `additionalContext`, the
same pattern the memory kit uses (both events confirmed present in the extension's
settings schema).

**This is where a kit-owned state file is justified**: the opposite of the naming
decision, for a specific reason. The name sidecar was dropped because Claude Code already
stores names and reads them, so ours would have been a second source of truth. "This
session handed topic X to session Y on this date" is something Claude Code has no concept
of and no store for: nothing to duplicate, nothing to conflict with. It must also survive
restarts, which rules out the pid-file.

Two requirements, or it becomes a trap:

- **A release.** One obvious step to remove the guard, for when the work belongs back in
  the original session after all. A guard you cannot turn off turns a stale marker into a
  permanently half-crippled session.
- **A destination.** The redirect must name where the work went, which means the split
  records the link in both directions when it happens rather than reconstructing it later.

Same-machine only. Across machines the original session is usually not present to guard.

**The link is recorded pending, then completed by a claim** (built 2026-08-09). The
design above says the split records the link in both directions "when it happens",
but at split time the destination session does not exist yet, so there is no id to
record. Resolution: `split.sh` writes the old session's marker with `to: null` and a
`from` file inside the folder; the fresh session's first act is `claim.sh <folder>`,
which fills in both directions with real ids. Until a claim happens the guard still
works, it just says "a fresh session that has not claimed it yet" instead of naming
one. The claim step is also where the note's self-declared assertions get checked:
by the claiming agent, semantically, while the old session is still alive to fix an
inadequate note. One active handoff per session: a second split overwrites the first;
modelling multiple simultaneous outbound topics was considered and skipped.

## Interoperability (verified 2026-08-09)

Format cousins exist: Codex CLI keeps JSONL session transcripts under
`~/.codex/sessions/`, Gemini CLI keeps JSON checkpoints under `~/.gemini/tmp/`, and
the SKILL.md format this kit's skills use is an open standard adopted across those
tools. Two consequences, neither of which changes scope:

- **Keep the seam, build no adapters.** Everything Claude-Code-specific already lives
  behind `core/`; a `~/.codex` adapter could plug in there someday. Until a concrete
  target exists, handoff reads and writes Claude Code sessions only.
- **The note is the portable layer.** `HANDOFF.md` is plain markdown any agent can
  ingest; the transcripts are the Claude-native payload. Keep that separation: never
  let the note's usefulness depend on the transcripts beside it.

## Proposed format: one bundle, one manifest

```
session-handoff-<date>.tar.gz
├── manifest.json      # the part tonight was missing
├── sessions/<session-id>.jsonl   # original UUID filenames, no rename dance
├── notes/HANDOFF.md   # freeform WIP/backlog note (template provided, never generated)
└── files/…            # optional loose artifacts (diffs, patches)
```

`manifest.json` per session: id, **title**, source machine, source cwd, time range,
line count, sha256. Plus: bundle date, source hostname, kit version.

### Checksums are guarded twice (added 2026-08-10)

The original helper fell back from `sha256sum` to `shasum` and could not report
absence: on a machine with neither tool it emitted blank digests, and a similarly
bare importer would verify blank against blank and accept a damaged bundle. Two
guards close this, and both are needed:

- **Presence**: export and import refuse up front when neither tool exists.
- **Value**: every computed digest must be 64 hex characters or the script stops.
  This also catches a tool that exists but fails mid-run, which the presence check
  cannot see.

One trap is load-bearing: the digest must be computed in a plain assignment
(`sha=$(_ho_sha256 f)`), never inline in another command's arguments. In argument
position bash discards the substitution's exit status even under `set -e`, so a
failing helper would be silently ignored; that is precisely how the original bug
survived. Tests pin all of it: a missing tool (empty PATH), a misbehaving tool (a
stub that prints nothing), and the error messages, so a different failure cannot
pass them for the wrong reason.

## Proposed pieces

1. **`handoff/export.sh <session-ref>… [files…]`**: resolve refs via `core/` (title
   substring or id), validate each transcript (valid JSON tail), write manifest,
   bundle. Refuses to run if a ref is ambiguous.
2. **`handoff/import.sh <bundle>`**: verify checksums; refuse on session-id collision
   with a *different* file (byte-identical = skip silently); install under the current
   machine's project dir; append each session's manifest `title` as a `custom-title`
   line in its transcript (DESIGN-naming.md) so the name survives the move and appears
   in the target machine's session picker; print the HANDOFF.md note.
3. **Skill `/handoff`**, an interactive wrapper: pick sessions, draft the HANDOFF.md from
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
  `custom-title` itself: an imported session shows its real name in the normal session
  picker, not only in this kit's tooling. Imported sessions are also the safe case for
  writing it: no process is attached, so there is no concurrent writer to interleave
  with. The VS Code *tab* picks it up too, the next time that session is opened;
  verified 2026-08-05, see DESIGN-naming.md.

  **Import is also the right place to normalise titles**, which a live session is not. A
  running session's auto-titler re-emits `ai-title` after every turn, so anything written
  there competes with a process that writes more often than we do. No such race exists
  around an imported transcript with no process attached. If a bundle carries a malformed
  or missing title, import is where it gets fixed.

  Import is likewise the concrete caller that brings back the other-session write path
  deferred in DESIGN-naming.md's decision record: it knows exactly which sessions it just
  installed and can assert against its own manifest: an independent source, unlike a
  caller that satisfies a check from the same lookup it just performed.
