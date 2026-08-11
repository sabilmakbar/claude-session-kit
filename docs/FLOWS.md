# How the kit behaves

Diagrams of what runs when, plus the specifics
[HOW-IT-WORKS.md](HOW-IT-WORKS.md) deliberately leaves out. The reasons behind each
choice live in the design docs: [DESIGN-naming.md](DESIGN-naming.md),
[DESIGN-handoff.md](DESIGN-handoff.md), [DESIGN-notes.md](DESIGN-notes.md).

One rule keeps this file from growing into a second copy of the plain-language
version: a sentence that also belongs in HOW-IT-WORKS goes there, not here. What
lives here is the diagrams, and the detail a reader has to have asked for.

## What runs on every message

Three hooks look at each message you send. Each speaks at most once per opened
session, and usually not at all.

```mermaid
flowchart TD
    A["message sent"] --> B{"session note exists,<br/>not yet shown to this process?"}
    B -- yes --> B1["inject the note, age-stamped:<br/>'written N entries ago'"]
    B -- no --> C
    B1 --> C{"this session split<br/>a topic off earlier?"}
    C -- "yes, claimed" --> C1["remind once per opening:<br/>topic lives in session X"]
    C -- "yes, stale (unclaimed > 48h)" --> C2["name the three exits:<br/>claim manually / re-split / release"]
    C -- no --> D{"brand-new session<br/>+ a pending handoff exists?"}
    D -- yes --> D1["surface it: claim now if the<br/>user's message continues that work"]
    D -- no --> E{"drift gates<br/>(next diagram)"}
```

## The drift gates

```mermaid
flowchart TD
    M["message arrives"] --> P{"new process for<br/>this session?"}
    P -- yes --> H{"≥ 20 entries<br/>of history?"}
    H -- yes --> W["wrong-session check, FIRST message:<br/>if clearly unrelated work, stop.<br/>no preliminary tool calls, route via cs_find<br/>+ set the standing watch for this sitting"]
    H -- no --> Q["silent (nothing established<br/>to be wrong about)"]
    P -- no --> C{"≥ 200 entries since<br/>last check?"}
    C -- yes --> T{"session has a<br/>real title?"}
    T -- yes --> D["silent self-check:<br/>still matches → say nothing<br/>evolved → offer rename<br/>second topic → offer split"]
    T -- no --> U["naming nudge:<br/>offer to title it"]
    C -- no --> S["silent"]
```

The numbers (20 entries of history, a check every 200 entries) are deliberately
low-stakes. A check that finds nothing costs one silent thought, not an
interruption. All four knobs (these two, the 48-hour pickup window, and how new a
session must be to get offered pending handoffs) live in
`~/.claude/session-kit/config`, seeded at install with every default shown
commented out. The format is KEY=value, whole numbers only; the file is read,
never executed; a malformed value quietly falls back to its default; and an
environment variable with the same name overrides the file.

## Splitting a session on the same machine

Nothing is bundled or copied, because nothing leaves the machine. The split moves
through these states:

```mermaid
stateDiagram-v2
    [*] --> Pending: split.sh writes folder + note, arms the guard
    Pending --> Claimed: claim.sh (auto-offered 48h, manual forever)
    Pending --> Stale: 48h pass unclaimed
    Stale --> Claimed: manual claim.sh
    Stale --> Pending: re-split re-arms the window
    Pending --> Released: release.sh
    Stale --> Released: release.sh
    Claimed --> Released: release.sh, work returns
    Released --> [*]
```

Who hears what, in each state:

| State | The old session (once per opening) | Fresh sessions (first message, once) |
|---|---|---|
| Pending | "topic moved; not claimed yet" | "a handoff is pending; claim it if this session is for it" |
| Stale | "never claimed, window passed" + the three exits | nothing (the window gates the nudge, never the claim) |
| Claimed | "topic lives in session X" | nothing |
| Released | nothing | nothing |

## Moving sessions to another machine

```mermaid
flowchart LR
    subgraph A["machine A"]
        E["export.sh: resolve refs<br/>(ambiguity refuses),<br/>validate transcripts"] --> B1["bundle: sessions + note<br/>+ files + sha256 manifest"]
    end
    B1 -- "you carry it<br/>(scp, drive, anything)" --> I
    subgraph B["machine B"]
        I["import.sh phase 1:<br/>verify EVERYTHING,<br/>write NOTHING"] --> OK{"all checks<br/>pass?"}
        OK -- no --> R["refuse whole bundle;<br/>machine untouched"]
        OK -- yes --> W["install sessions,<br/>append titles,<br/>print the note"]
    end
```

Importing the same bundle twice is safe and does nothing.

## Session notes

```mermaid
flowchart LR
    W["agent writes the note<br/>at a milestone<br/>(/session-note)"] --> S["stored per session,<br/>outside the code tree;<br/>uninstall never touches it"]
    S --> R["on reopen, first message:<br/>injected once, age-stamped"]
    R --> J{"agent: does the note<br/>still match reality?"}
    J -- yes --> U["use it as seed context"]
    J -- no --> F["say so briefly,<br/>write a corrected note"]
```

Writing a note replaces the previous one. The transcript keeps every old version
anyway, so nothing is lost by overwriting.

## Version safety

A session-start hook compares the running Claude Code version with the last one the
kit was verified against on this machine. On a match it exits in about ten
milliseconds. On a new version it runs the real-data suite in the background, at
most once per day, and a pass clears the warning by itself.
