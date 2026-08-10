# How the kit behaves — flows and lifecycles

This is the behaviour reference: what runs when, and what state moves where. The
*reasons* live in the design docs — [DESIGN-naming.md](DESIGN-naming.md),
[DESIGN-handoff.md](DESIGN-handoff.md), [DESIGN-notes.md](DESIGN-notes.md) — each
decision recorded with what it overturned. Nothing here duplicates those; when a
box below seems arbitrary, the why is in a design doc.

One rule governs everything on this page: **hooks decide WHEN, the agent judges
WHAT.** Every semantic call — does this match the title, is this the wrong tab, is
the note stale — is made by the in-session agent, which already holds the whole
conversation. The hooks only schedule the questions, and every hook exits 0 and
prints nothing on every failure path: breaking a user's prompt is never worth a
feature.

## What runs on every message

Three `UserPromptSubmit` hooks, each gated so it speaks rarely and at most once per
opened session. (A fourth hook, `version-check`, runs at `SessionStart` — see the
last section.)

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
    H -- yes --> W["wrong-session check, FIRST message:<br/>if clearly unrelated work, stop —<br/>no preliminary tool calls, route via cs_find<br/>+ set the standing watch for this sitting"]
    H -- no --> Q["silent (nothing established<br/>to be wrong about)"]
    P -- no --> C{"≥ 200 entries since<br/>last check?"}
    C -- yes --> T{"session has a<br/>real title?"}
    T -- yes --> D["silent self-check:<br/>still matches → say nothing<br/>evolved → offer rename<br/>second topic → offer split"]
    T -- no --> U["naming nudge:<br/>offer to title it"]
    C -- no --> S["silent"]
```

The agent receiving these instructions stays silent while the session is healthy —
a wasted check costs one silent thought, never an interruption. That is what makes
the cadence numbers (20, 200, both env-tunable) low-stakes choices.

## Same-machine split — the lifecycle

A split writes a plain folder (no bundle: nothing crosses a machine gap) and moves
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

What each side hears, per state:

| State | The old session (once per opening) | Fresh sessions (first message, once) |
|---|---|---|
| Pending | "topic moved; not claimed yet" | "a handoff is pending — claim it if this session is for it" |
| Stale | "never claimed, window passed" + the three exits | nothing (the window gates the nudge, never the claim) |
| Claimed | "topic lives in session X" | nothing |
| Released | nothing | nothing |

Constants: the folder and its note are **never deleted** by any transition — they
are the record of why the split happened. History questions to the old session are
never guarded; the old transcript is the only place the full argument survives.

## Cross-machine handoff

```mermaid
flowchart LR
    subgraph A["machine A"]
        E["export.sh: resolve refs<br/>(ambiguity refuses),<br/>validate transcripts"] --> B1["bundle: sessions + note<br/>+ files + sha256 manifest"]
    end
    B1 -- "you carry it<br/>(scp, drive, anything)" --> I
    subgraph B["machine B"]
        I["import.sh phase 1:<br/>verify EVERYTHING,<br/>write NOTHING"] --> OK{"all checks<br/>pass?"}
        OK -- no --> R["refuse whole bundle —<br/>machine untouched"]
        OK -- yes --> W["install sessions,<br/>append titles,<br/>print the note"]
    end
```

Import is atomic by construction: a tampered file or a diverged session refuses the
entire bundle, including its healthy sessions. Re-importing the same bundle is a
clean no-op (prefix comparison — the installed copy may have grown a title line or
new turns). Titles travel inside the manifest and are appended as `custom-title`
entries, so imported sessions show their real names in the target's session picker.

## Session notes

```mermaid
flowchart LR
    W["agent writes the note<br/>at a milestone<br/>(/session-note)"] --> S["stored per session,<br/>outside the code tree —<br/>uninstall never touches it"]
    S --> R["on reopen, first message:<br/>injected once, age-stamped"]
    R --> J{"agent: does the note<br/>still match reality?"}
    J -- yes --> U["use it as seed context"]
    J -- no --> F["say so briefly,<br/>write a corrected note"]
```

Writing replaces the previous note (the transcript keeps every old version). The
age stamp is the safety mechanism: a stale note presented as current is the one way
this feature can do harm, so every render carries "written N entries ago".

## Version safety

At `SessionStart`, `version-check.sh` compares the running Claude Code version with
the last version the kit was verified against on this machine. Unchanged → exit in
~10ms. Changed → run the real-data suite (`tests/smoke.sh`) in the background: pass
→ record the new version, warning gone; fail → record nothing, so the warning keeps
appearing (and a redacted, shareable failure report is written) until a human looks.
The failure mode of the automation is falling back to the manual process, loudly —
nothing silent.
