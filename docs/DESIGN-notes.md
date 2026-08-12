# Design: session notes

> **This is a decision record, not a user guide.** It is dense on purpose: it
> exists so that future changes know what they would be overturning. For how the
> kit behaves day to day, read [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    First built:       2026-08-08
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        (none)

Assumes the observed behaviour in [INTERNALS.md](INTERNALS.md), chiefly the three-identity
model (O1) and the append-only transcript. Read that first if this is your entry point; the
decisions those observations forced live in [DESIGN-naming.md](DESIGN-naming.md).

A per-session working note: what was decided, what is done, what comes next. The
agent writes it near milestones; when the session is later reopened, a hook hands the
note back so the conversation resumes with its own state instead of a cold start.

Each decision below carries its reason, so a change knows what it is overturning.

## Decisions

### 1. The agent writes the note; the kit only stores and surfaces it

bash + jq cannot summarise a conversation; only the model can say what was agreed.
Any attempt to generate the note mechanically (last N messages, keyword scraping)
produces confident nonsense. Same split as `/rename-session`: the skill decides the
content, the shell function performs the write.

### 2. Write side is current-session only

`note_write` takes no session-id parameter, so it cannot be aimed at another
session's note. Same argument as the rename-scope decision record in
DESIGN-naming.md: the writer summarises the conversation it can actually see.
Reading any session's note takes an id and is harmless.

### 3. Surfaced on `UserPromptSubmit`, not `SessionStart` (on receipts)

`UserPromptSubmit` is the only one of the two observed delivering `.session_id` on
stdin. On the machine this was designed on, a hook reading it that way resolved the
right session across 24 consecutive sessions, with per-session marker files as the
receipts. No `SessionStart` hook on that machine reads stdin at all, so whether that
event carries a session id is a guess with nothing behind it. Build on the event with
evidence.

The evidence is one machine, so it proves the event works rather than that the other
one does not. If a `SessionStart` hook is ever seen resolving a session id, this
decision is worth reopening.

Cost: the note arrives on the first *message* after reopening, not at tab-open.
Acceptable; arguably better, since it lands exactly when work resumes.

### 4. Plain text on stdout, not JSON

For `UserPromptSubmit`, plain stdout on exit 0 is appended to the model's context,
proven by the memory-delta pings visibly arriving in the design conversation itself.
Plain text also removes a real failure mode: notes are multi-line prose full of
quotes, and gluing prose into a JSON template with printf produces invalid JSON that
the harness would discard silently. No JSON, no escaping, no silent drop. If a
future hook must emit JSON (SessionStart's `additionalContext`, PreToolUse
decisions), build it with `jq -n --arg`, never printf interpolation.

### 5. Shown once per opened session, gated by process id

`UserPromptSubmit` fires on every message; ungated, the note would repeat every
turn. The pid-file (`~/.claude/sessions/<pid>.json`) names the CLI process currently
running the session, and a `.seen` marker records the process the note was last
shown to. Same process → silent. New process (restart, resume) → shown once, marker
advances. `note_write` also stamps the marker with the writer's own process, so a
note never echoes back into the session that just wrote it.

### 6. Staleness is measured and always shown

A note claiming "next: write the exporter" after the exporter shipped is worse than
no note: it asserts something false, with confidence, to a reader with no context
yet. Every note records the transcript line count at write time; every render says
how many entries have been added since ("written N transcript entries ago") or "age
unknown" when it cannot tell. The reader discounts accordingly. A render that
presented a stale note as current would defeat the feature.

### 7. Notes live outside the installed-code directory

Data: `~/.claude/session-notes/<session-id>.md` (+ `.seen` marker).
Code: `~/.claude/session-kit/…` like the rest of the kit.

They must be separate trees because `install.sh --uninstall` removes the code tree
wholesale. Notes are user content; an uninstall or reinstall must never delete them.
(`.verified` may live in the code tree. An uninstall takes it along, and the next
smoke run re-records whatever is running, so the kit is never left unverified. What
an uninstall does lose is the other versions it had already cleared, costing one
background run apiece if you go back to them. Notes are not regenerable at all, which
is the difference that matters here.)

### 8. Three sections, overwrite semantics

`## Decided / ## Done / ## Next` and nothing else. A wider schema (owners, priorities,
test matrices) is more to keep current, and unmaintained fields go stale fastest;
staleness is this feature's one real risk (see 6). The note is working state, not a
log: writing replaces the previous note. History lives in the transcript, which
records every version anyway. Anything that must outlive the session belongs in a
design doc or the project backlog, not here.

## Failure posture

The hook exits 0 and prints nothing on every failure path: missing note, missing
pid, unreadable stdin, sanitised-away session id. Breaking prompt submission is
strictly worse than skipping a note. The session id is stripped to `[A-Za-z0-9-]`
before use as a filename, so a hostile `session_id` cannot escape the notes
directory.
