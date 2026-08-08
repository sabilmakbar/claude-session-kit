---
name: session-note
description: Write or update the current session's working note — what was decided, what is done, what comes next — so the session can resume from its own state after a restart. Use when the user asks to save session state, update the session note, or at a natural milestone (a feature finished, a decision settled, before stepping away). Current session only.
---

# Session note

You summarise the session's working state into one short note; the kit stores it and
hands it back automatically on the first message after the session is reopened. The
user should never have to reconstruct "where were we?" by scrolling.

## When to write one

- The user asks: "save the state", "update the note", "note this down".
- A milestone lands: a feature is finished and verified, a contested decision is
  settled, a long task is about to pause.
- You are about to do something risky and the current state is worth pinning first.

Do not write one after every message — the note is a checkpoint, not a log.

## What goes in

Exactly three sections. Short bullets, front-load what matters.

- `## Decided` — conclusions that should not be relitigated, with a word of *why*.
  ("current-session-only rename — see decision record" not just "scoped rename".)
- `## Done` — finished AND verified work only. Nothing aspirational; if tests did
  not pass, it is not done.
- `## Next` — the immediate open thread, in actionable form. The first bullet should
  be the thing to pick up first.

Keep the whole note under ~30 lines. What must outlive the session (architecture,
durable decisions) belongs in a design doc, not here. Personal working state that
never ships (backlogs, wip lists) has its own rule and stays out of git either way.

## How to write it

```bash
. notes/note.sh
note_write <<'EOF'
## Decided
- ...

## Done
- ...

## Next
- ...
EOF
```

Quote the heredoc delimiter (`<<'EOF'`) so nothing in the note gets expanded by the
shell. Writing **replaces** the previous note — that is correct; the transcript keeps
every old version, so never append or accumulate.

There is no session-id parameter. This writes the note of the session you are in,
and only that one — you cannot summarise a conversation you cannot see.

## After writing

Confirm to the user in one line what was pinned. Do not paste the whole note back —
they just lived it.

The note surfaces automatically on the first message after the session is next
reopened, stamped with how old it is. If, on resume, the note contradicts what the
conversation shows, trust the conversation, say so briefly, and write a corrected
note.
