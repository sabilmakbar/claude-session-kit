# Design: session identity & naming

> **This is a decision record, not a user guide.** It is dense on purpose: it
> exists so that future changes know what they would be overturning. For how the
> kit behaves day to day, read [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-12
    Verified against:  Claude Code 2.1.222
    Supersedes:        (none)

Read this one first if you are reading more than one. It sets the three-identity model and
the append-only rule that the other records assume rather than restate.

## The problem

One session has three identities, in three places that never talk to each other: the
display title, the CLI registration name, and the transcript id. They are joined by the
session UUID, so identity was never ambiguous. Only the human-readable label was.

The layers themselves, their storage, and how each behaves are recorded in
[INTERNALS.md](INTERNALS.md): O1 for the three layers, O5 to O8 for the pid-file. This
record assumes those rather than restating them.

Three of those observations are what make the label a problem rather than a detail:

- The automatic title never moves after the opening message (O3), so any session that
  outgrows its first question carries a stale name.
- Derived names collide (O6), so resolving a session by name has to handle ambiguity
  explicitly instead of assuming one hit.
- An explicit name does not survive a process restart at the pid layer (O8), so the
  obvious place to store a name is the wrong one.
## Existing behavior rule

The memory `feedback_session_identifiers` (miner P-009) already tells Claude to refer
to sessions by title, flag drift, and suggest renames. What is missing is tooling:
detection is manual and renaming is buried in the UI.

## The three pieces, and what each one settled

1. ~~**`core/sessions.sh`**~~: **built.** Resolves a session from any identifier (title
   substring, short id, full UUID) and lists sessions with their best-known name. Reads
   two layers, transcript and pid-file; `state.vscdb` is deliberately never touched (see
   the decision below, resting on O10), so "all three layers" (as an earlier draft put it)
   was never the goal. Read-only; every write lives in `naming/`.
2. ~~**Drift detector**~~: **built 2026-08-09**, and the original sketch did not
   survive the design. The keyword heuristic ("does any title word appear in the
   last N user messages?") was dropped untried, and no headless scorer replaced it:
   both answer a semantic question mechanically, and a mechanism that guesses wrong
   trains the user to ignore it. The component that already holds the whole
   conversation (the in-session agent) judges drift for free.

   So `hooks/session-drift.sh` never judges; it decides WHEN to ask, and its payload
   tells the agent to judge silently and speak only if something is off. A wasted
   check costs one silent thought, which is what makes the one remaining mechanical
   choice (the cadence) low-stakes. Two gates, one marker per session: a new process
   on a session with ≥20 entries of history gets the wrong-session check on its
   FIRST message (the latency requirement below, met by construction); every ~200
   entries after that, the rename-or-split self-check. A session with no real title
   gets a naming nudge instead of a drift question against a meaningless name.

   The sketch as originally proposed, kept for the record: compare stored title
   against recent content (cheap heuristic first: title words in the last N user
   messages), with a headless-Claude scorer later if the heuristic proved too dumb.
   On drift the ping offers a **three-way** fork:

   - **rename**: same work, evolved topic. Title is stale; the session is fine.
   - **split**: deliberately moved to a new topic. Handoff note into a fresh session,
     per DESIGN-handoff.md's same-machine use case.
   - **wrong session**: the user opened the wrong tab and asked something unrelated to
     everything before it. Neither of the above: nothing needs renaming and nothing
     needs carrying over, the question just landed in the wrong place.

   The third case is a different problem wearing the same clothes, and it changes the
   detector's requirements. Its signature is a *sudden* discontinuity after a long
   coherent stretch, not the gradual slide the first two produce. Its cost is polluting
   an otherwise clean session's context, so it is the only case where the ping has to
   fire on the **first** unrelated message rather than after N; a warning that arrives
   at turn 20 has already lost what it was protecting. And its remedy is prevention
   ("this looks unrelated to this session; did you mean a different one?"), not repair.

   Note the detector cannot lean on `ai-title` freshness as a signal, because that value
   never changes: it is pinned to the opening message and merely re-asserted (verified:
   18 identical `ai-title` lines in a 75-turn session that had long since moved on). The
   title going stale is guaranteed, so staleness alone carries no information; the
   comparison must be title-versus-recent-content.
3. **Renamer**: it really renames; suggesting is only half the job. (Revised
   2026-08-05: an earlier draft scoped this to a suggester, on the reasoning that the
   built-in `/rename` cannot be shadowed. That conflated two separate things: we cannot
   own the *command name*, but nothing stops us performing the *act*, since the write
   `/rename` makes is a single appended JSONL line we can reproduce exactly.)

   **Scope: the current session only, written directly. See the decision record below.**

   **Revert by appending, never by rewriting.** Since precedence takes the last
   `custom-title`, undoing a rename means appending the previous value. The transcript
   stays append-only and we never rewrite a file Claude Code owns.

   Risk to guard, per the `core/` convention: the line format is undocumented, so write
   it only behind a version check and fail quiet on mismatch.

   **The title length cap is a safety property, not a style rule.** Concurrent appends
   are safe because `O_APPEND` makes the kernel serialise the offset update, and that
   guarantee is strongest for a write small enough to land in one go; it weakens as
   writes grow. Capping titles at 200 characters keeps every emitted line around 300
   bytes, which is what licenses appending to a transcript another process is also
   writing. `/rename` itself accepts multi-kilobyte pasted text (one such entry exists
   in a real transcript); the kit deliberately does not, and `rename_check_title`
   enforces it.

   The other gap the built-in leaves is that it takes a name you have to invent
   yourself, so this piece proposes one from the transcript regardless of which session
   is being renamed.

   **Name the arc, not either endpoint.** `ai-title` fails by capturing only the session's
   *first* topic. A hastily chosen rename fails the same way at the other end, capturing
   only the last hour. A real example: a long session covering a machine setup, a
   release, a sync redesign and two new repos got renamed `session-kit-project-structure`
   after its most recent thread, which is no more accurate than the opening-message title
   it replaced. The suggester's job is the span of work, not the newest part of it.

   **Front-load the words that matter.** An earlier draft here claimed the tab shows
   "roughly the first 25–30 characters". Withdrawn: there is no such number. VS Code's
   default `workbench.editor.tabSizing` is `fit`, so tabs shrink as more are opened; the
   visible width is a function of window width and tab count, and a title legible with
   three tabs open is a stub with twelve. Treat the visible budget as small and unknown.

   The rule that survives is the ordering one: "Memory & session toolkits: Mac setup,
   sync redesign" still reads correctly at any truncation point, while a title whose
   distinguishing words sit at the end degrades to nothing useful. The full string
   survives in the session list and in search regardless.

   Identifiers keep their real spelling inside that sentence. `relo-calculator` and
   `claude-session-kit` are proper nouns; the no-slug rule governs the sentence around
   them, never the names themselves. Claude Code's own auto-titles already do this
   ("Check relo-calculator deployment readiness"), and that is the model.

   Suggested titles should be **sentence-style, matching the `ai-title` register**
   ("Recreate codebase with anonymized data"), not kebab-case slugs
   ("detector-heuristic-testing"). `/rename` accepts free text: it imposes no slug
   format, and at least one existing session holds a sentence-style custom title, so
   the slug habit is ours, not the tool's. Sentence-style is what renders in tabs and
   pickers, which is the only place these names are read.

## Decision record: who renames the current session

This rule changed **five times on 2026-08-05**. Each position was reasonable given what
was known at the time, and each failed for a specific, findable reason. The table exists
so a sixth change has to argue against these rather than rediscover them.

| # | Position | Reason given | Why it failed |
|---|---|---|---|
| 1 | Suggest only, never write | a skill cannot shadow the built-in `/rename` | Conflated the command **namespace** with the **capability**. We cannot own the name `/rename`; nothing stopped us performing the same write. |
| 2 | Write other sessions, defer the current one | the current session's process is appending concurrently, so we would interleave | False. `lsof` shows no persistent handle on a transcript, and `O_APPEND` makes the kernel serialise the offset update, so concurrent appenders cannot overwrite each other. |
| 3 | Write every session, current included | appending is safe, and it was proven end to end | Incomplete rather than wrong. `/rename` also updates the process's **in-memory** name and its pid-file entry; a file write reaches neither. |
| 4 | Write other sessions, defer the current one again | `/rename` is the *complete* operation for the current session | The completeness expires. A process restart regenerates the pid-file name as `documents-NN` **regardless of who wrote it**, and was observed erasing a `/rename`-set name the same day. |
| 5 | **Current session only, written directly** *(current)* | Both routes converge on a generic registry name, so `/rename`'s advantage lasts one process lifetime while the paste it costs is permanent. The other-session path had no live consumer. | (none yet) |

### Evidence behind position 5

- One session ran under **three** processes in a day: `26094` → `45158` → `58005`, each
  writing a fresh `documents-NN` with `nameSource: derived`. That `nameSource` is the
  human-named marker is O7; that a restart destroys the name is O8.
- The `26094` → `45158` restart erased `detector-heuristic-testing`, a name set by
  `/rename` itself. **The built-in's pid-file write is no more durable than ours.**
- The tab reads `custom-title` from the transcript, verified with the pid-file
  deliberately left stale, so the visible name never depended on that layer.

### Why the scope narrowed to one session

Renaming dead and imported sessions is a real requirement, since it is how titles survive
a handoff. When this was decided there was no import, so the capability had no caller and
narrowing cost nothing. `handoff/import.sh` exists now and titles the sessions it installs,
which is the one sanctioned exception recorded below.
A guard was considered: require the caller to state the target session's current
name, and refuse on mismatch. It was rejected as a guarantee that cannot hold, because a
caller can satisfy it from the same lookup it just performed:

```bash
name=$(cs_resolve_name "$id"); rename_apply "$id" "$title" "$name"   # always passes
```

That reads like a safety property while being defeatable in one line, which is worse
than having none. So `rename_apply` takes **no session id at all** (there is no
parameter to aim wrongly), and the capability returns with handoff, when import can
assert against its own manifest, which is a genuinely independent source.

### What would reopen this

- **Claude Code seeding the pid-file `name` from `custom-title` at startup.** That would
  make the registry name durable, restoring position 4's argument in full.
- **A surface that displays the registry name** turning out to matter in practice. The
  peer-visibility purpose is inferred from field names (`tempo`, `needs`, `tmux`,
  `peerProtocol`) and the `concurrentSessions` heartbeat; no UI for it was ever found.
- **Handoff import landing**, which is the concrete caller the other-session write path
  was always for.
- Evidence that appending to a live transcript is unsafe after all, which would push
  back toward position 2, this time for a correct reason.

## Decisions the internals forced

These follow from [INTERNALS.md](INTERNALS.md) rather than from preference. Each names the
observation it rests on, so when an observation moves, the decision resting on it is the
thing to re-examine.

**No sidecar. The durable store is the transcript's `custom-title` entry.** Rests on O8 and
O12. A kit-owned sidecar would survive a process restart too, so durability alone does not
choose between them. What chooses is **who reads it**: `custom-title` is consumed by Claude
Code itself, so a name written there shows up in the session picker and the CLI's own
listings. A sidecar is visible only to this kit. A name nobody but us can see is worth much
less, and keeping both would mean two sources of truth to reconcile. So: one store, the one
that already exists. (Reversed 2026-08-05; the sidecar answer recorded earlier that day was
wrong.)

**Never write `state.vscdb`.** Rests on O10. It caches the rendered tab after the fact, so
writing it is both unsupported, against a file VS Code holds open, and pointless for a live
session whose panel would overwrite it. The scope is CLI-side naming only, which still
reaches the tab, because the tab reads the transcript (O12). An earlier draft promised a
statusline instead; withdrawn, and none is built or planned.

**Select by entry type, then take the last of that type. Never by file order.** Rests on O4
and O13. This is the one decision here that a casual test would not catch, because the
clobbering `ai-title` only lands once another message is sent, so `tests/run.sh` pins it
deliberately rather than incidentally.

**Every accessor lives in `core/` behind a version check, with a fail-quiet path.** Rests
on O14. Version skew between layers is normal, not an anomaly, so an accessor that asserts
one version is wrong on a machine with long-running sessions. A Claude Code update should
degrade the kit to "no data" rather than to breakage.

**Renaming reaches dead and imported sessions, not just live ones.** Rests on O12.
Appending `custom-title` gives a session a correct tab title the next time it opens, so the
imported-session case in [DESIGN-handoff.md](DESIGN-handoff.md) gets real titles rather
than picker entries alone. The one thing still impossible is retitling a tab that is open,
in place.
