# Design: session identity & naming

## The problem

One session has three identities, stored in three places that never talk to each other:

| Layer | Example | Where it lives | Who writes it |
|---|---|---|---|
| Display title (what the user sees) | "Review memories and feedbacks" | the transcript, as `ai-title` / `custom-title` lines; VS Code's `state.vscdb` only caches the rendered tab | `ai-title` by Claude Code from the opening message; `custom-title` by `/rename` **or by this kit** |
| CLI registration name | `documents-2d` | `~/.claude/sessions/<pid>.json` (`name`, `nameSource`) | Claude Code CLI at session start; wiped back to derived on restart |
| Transcript identity | `0d15803a-…` | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | Claude Code, one file per session |

The three are joined by the session UUID: the transcript filename *is* the id, and
the pid-file carries it in a `sessionId` field. Identity was never actually ambiguous —
only the human-readable label was.

Verified on Claude Code 2.1.222 (macOS, VS Code extension). Earlier rows in this
document cite 2.1.220 and 2.1.221; the internals below held across all three. Notes:

- The pid-file is per **process**, keyed by pid, and only exists for sessions that ran
  on this machine. Imported transcripts have no registration at all.
- **Derived names are not unique.** Two concurrent sessions (`99f81837`, `280dbe52`)
  both held the name `documents-7c` at the same time. Any resolve-by-name path must
  therefore handle ambiguity explicitly rather than assuming one hit — this is the
  live justification for the export tool refusing ambiguous refs (DESIGN-handoff.md).
- `nameSource` is **absent** on explicitly-named sessions and set to `derived` on
  auto-named ones (verified 2026-08-04 across 8 live pid-files: 7 × `documents-XX` +
  `derived`, 1 × `session-kit-project-structure` with no `nameSource`). Absence is
  therefore the "a human named this" marker, not a missing field to default in.
- ~~Transcripts carry no title/summary entries~~ — **wrong, corrected 2026-08-05.**
  Transcripts *do* carry title entries, as their own line types keyed by `sessionId`:
  `{"type":"ai-title","aiTitle":…}` (generated from the opening message) and
  `{"type":"custom-title","customTitle":…}` (appended by the built-in `/rename`). The
  CLI binary ships a compiled regex, `"customTitle":"([^"]+)"`, to scrape it straight
  out of the raw JSONL, alongside a title record of
  `firstPrompt`/`agentName`/`customTitle`/`aiTitle`/`summary`. **The display title is
  therefore file-backed and addressable**, not locked inside VS Code's sqlite.
- The **`ai-title`** is set from the opening message and never revised — verified as 18
  byte-identical lines in a 75-turn session that had long since moved on. So any session
  that outgrows its first question carries a stale title ("drift"). The title as a whole
  *is* revisable, via `custom-title`; it is the automatic one that never moves. The
  visible tab also does not refresh in place — it re-reads on close-and-reopen.

## Existing behavior rule

The memory `feedback_session_identifiers` (miner P-009) already tells Claude to refer
to sessions by title, flag drift, and suggest renames. What is missing is tooling:
detection is manual and renaming is buried in the UI.

## Proposed pieces

1. ~~**`core/sessions.sh`**~~ — **built.** Resolves a session from any identifier (title
   substring, short id, full UUID) and lists sessions with their best-known name. Reads
   two layers, transcript and pid-file; `state.vscdb` is deliberately never touched (see
   the resolved questions below), so "all three layers" — as an earlier draft put it —
   was never the goal. Read-only; every write lives in `naming/`.
2. ~~**Drift detector**~~ — **built 2026-08-09**, and the original sketch did not
   survive the design. The keyword heuristic ("does any title word appear in the
   last N user messages?") was dropped untried, and no headless scorer replaced it:
   both answer a semantic question mechanically, and a mechanism that guesses wrong
   trains the user to ignore it. The component that already holds the whole
   conversation — the in-session agent — judges drift for free.

   So `hooks/session-drift.sh` never judges; it decides WHEN to ask, and its payload
   tells the agent to judge silently and speak only if something is off. A wasted
   check costs one silent thought, which is what makes the one remaining mechanical
   choice (the cadence) low-stakes. Two gates, one marker per session: a new process
   on a session with ≥20 entries of history gets the wrong-session check on its
   FIRST message (the latency requirement below, met by construction); every ~200
   entries after that, the rename-or-split self-check. A session with no real title
   gets a naming nudge instead of a drift question against a meaningless name.

   The sketch as originally proposed, kept for the record — compare stored title
   against recent content (cheap heuristic first: title words in the last N user
   messages), with a headless-Claude scorer later if the heuristic proved too dumb.
   On drift the ping offers a **three-way** fork:

   - **rename** — same work, evolved topic. Title is stale; the session is fine.
   - **split** — deliberately moved to a new topic. Handoff note into a fresh session,
     per DESIGN-handoff.md's same-machine use case.
   - **wrong session** — the user opened the wrong tab and asked something unrelated to
     everything before it. Neither of the above: nothing needs renaming and nothing
     needs carrying over, the question just landed in the wrong place.

   The third case is a different problem wearing the same clothes, and it changes the
   detector's requirements. Its signature is a *sudden* discontinuity after a long
   coherent stretch, not the gradual slide the first two produce. Its cost is polluting
   an otherwise clean session's context, so it is the only case where the ping has to
   fire on the **first** unrelated message rather than after N — a warning that arrives
   at turn 20 has already lost what it was protecting. And its remedy is prevention
   ("this looks unrelated to this session — did you mean a different one?"), not repair.

   Note the detector cannot lean on `ai-title` freshness as a signal, because that value
   never changes: it is pinned to the opening message and merely re-asserted (verified:
   18 identical `ai-title` lines in a 75-turn session that had long since moved on). The
   title going stale is guaranteed, so staleness alone carries no information — the
   comparison must be title-versus-recent-content.
3. **Renamer** — it really renames; suggesting is only half the job. (Revised
   2026-08-05: an earlier draft scoped this to a suggester, on the reasoning that the
   built-in `/rename` cannot be shadowed. That conflated two separate things — we cannot
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
   guarantee is strongest for a write small enough to land in one go — it weakens as
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
   only the last hour — a real example: a long session covering a machine setup, a
   release, a sync redesign and two new repos got renamed `session-kit-project-structure`
   after its most recent thread, which is no more accurate than the opening-message title
   it replaced. The suggester's job is the span of work, not the newest part of it.

   **Front-load the words that matter.** An earlier draft here claimed the tab shows
   "roughly the first 25–30 characters". Withdrawn — there is no such number. VS Code's
   default `workbench.editor.tabSizing` is `fit`, so tabs shrink as more are opened; the
   visible width is a function of window width and tab count, and a title legible with
   three tabs open is a stub with twelve. Treat the visible budget as small and unknown.

   The rule that survives is the ordering one: "Memory & session toolkits: Mac setup,
   sync redesign" still reads correctly at any truncation point, while a title whose
   distinguishing words sit at the end degrades to nothing useful. The full string
   survives in the session list and in search regardless.

   Identifiers keep their real spelling inside that sentence. `relo-calculator` and
   `claude-session-kit` are proper nouns; the no-slug rule governs the sentence around
   them, never the names themselves. Claude Code's own auto-titles already do this —
   "Check relo-calculator deployment readiness" — and that is the model.

   Suggested titles should be **sentence-style, matching the `ai-title` register**
   ("Recreate codebase with anonymized data"), not kebab-case slugs
   ("detector-heuristic-testing"). `/rename` accepts free text — it imposes no slug
   format, and at least one existing session holds a sentence-style custom title — so
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
| 4 | Write other sessions, defer the current one again | `/rename` is the *complete* operation for the current session | The completeness expires. A process restart regenerates the pid-file name as `documents-NN` **regardless of who wrote it** — and was observed erasing a `/rename`-set name the same day. |
| 5 | **Current session only, written directly** *(current)* | Both routes converge on a generic registry name, so `/rename`'s advantage lasts one process lifetime while the paste it costs is permanent. The other-session path had no live consumer. | — |

### Evidence behind position 5

- One session ran under **three** processes in a day: `26094` → `45158` → `58005`, each
  writing a fresh `documents-NN` with `nameSource: derived`.
- The `26094` → `45158` restart erased `detector-heuristic-testing`, a name set by
  `/rename` itself. **The built-in's pid-file write is no more durable than ours.**
- The tab reads `custom-title` from the transcript, verified with the pid-file
  deliberately left stale, so the visible name never depended on that layer.

### Why the scope narrowed to one session

Renaming dead and imported sessions is a real requirement — it is how titles survive a
handoff — but **import does not exist yet** (backlog item 3), so the capability had no
caller. A guard was considered: require the caller to state the target session's current
name, and refuse on mismatch. It was rejected as a guarantee that cannot hold, because a
caller can satisfy it from the same lookup it just performed:

```bash
name=$(cs_resolve_name "$id"); rename_apply "$id" "$title" "$name"   # always passes
```

That reads like a safety property while being defeatable in one line, which is worse
than having none. So `rename_apply` takes **no session id at all** — there is no
parameter to aim wrongly — and the capability returns with handoff, when import can
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
  back toward position 2 — this time for a correct reason.

## Resolved questions (investigated 2026-08-04, extension v2.1.221)

- **Is the VS Code title writable safely?** **Yes for the CLI, no for us.** The
  extension's `contributes.commands` lists 23 commands and none of them renames a tab
  or session, so there is no palette entry and nothing invocable from outside. But
  `extension.js` handles an inbound RPC message, `request.type === "rename_tab"`, whose
  handler does `this.panelTab.title = request.title` (and swaps the tab icon between
  `claude-logo{,-pending,-done}.svg`). So the title is a **runtime property of the live
  webview panel**, set by the running CLI over its existing extension channel, through
  the sanctioned VS Code API.

  Two consequences. First, **`state.vscdb` is settled as the wrong target**: it only
  persists the editor memento *after* the fact, so an offline write is both an
  unsupported write to a file VS Code holds open and pointless for any live session,
  whose panel would overwrite it. Do not write it. Second, the scope is **CLI-side
  naming only** — which, as the entries below establish, still reaches the tab, because
  the tab reads the transcript. An earlier draft ended this line with "leaving the tab
  alone" and promised a statusline; both are withdrawn. The tab is reachable, and no
  statusline is built or planned.

- **Does the built-in `/rename` update the tab? No — verified by experiment.** The CLI
  ships `/rename` (alias `/name`, "Rename the current conversation"), and its handler
  writes `{name, nameSource: undefined, updatedAt}` to the pid-file. Running
  `/rename session-kit-naming-investigation` in a live VS Code session changed all three
  pid-file fields as predicted (`documents-07`/`derived`/`null` →
  `session-kit-naming-investigation`/absent/`1785864940698`) **and left the VS Code tab
  title unchanged.**

  So the tab title is not the session `name` — they are separate values with separate
  storage. But **"the tab is unreachable" was wrong** (claimed and retracted
  2026-08-05): `/rename` *does* append a `custom-title` entry to the transcript, and the
  CLI scrapes titles back out of that file. What did not happen is a **live refresh** of
  an already-open tab.

  That reading was confirmed by the entry below: the panel resolves its title when it
  opens and nothing pushes an update afterward, so a rename lands in the file while the
  visible tab keeps the title it was born with.

  One trap it exposed, which survives into the implementation: `ai-title` lines appear
  *after* `custom-title` lines in the same transcript, so "last title entry wins" and
  "customTitle beats aiTitle" are different rules producing different names. `core/`
  selects by entry type for exactly this reason, and `tests/run.sh` pins it.

  **Resolved 2026-08-05: the tab reads `custom-title`, and updates on reopen.** Observed
  flow — run the built-in `/rename`, close the tab, reopen the session, and the tab shows
  the new name. The live tab never changes; closing and reopening is the refresh.

  The deduction that this comes from `custom-title` and not the pid-file: reopening
  starts a *new process*, and a new process writes a fresh pid-file with a **derived**
  name (verified separately — a restart turned `detector-heuristic-testing` into
  `documents-41`/`derived`). If the tab read the pid-file it would show `documents-41`.
  It shows the custom name, so the transcript entry is the source. This also
  independently confirms the precedence order above, which places `custom-title` over a
  derived pid-file name.

  Consequence: **the tab is reachable for any session the kit renames**, not only via
  `/rename`. Appending `custom-title` to a dead or imported session gives it a correct
  tab title the next time it is opened — the imported-session case in DESIGN-handoff.md
  gets real titles, not merely picker entries. The only thing still not possible is
  retitling a tab that is currently open, in place.

- **Where does a durable name live?** **The transcript's `custom-title` entry — not a
  sidecar of our own.** (Reversed 2026-08-05; the sidecar answer recorded earlier the
  same day was wrong.)

  The pid-file is not merely ephemeral, it is *actively destructive of names*. Observed
  live: a session's process restarted mid-conversation (pid 26094 → 45158) and its
  explicit name `detector-heuristic-testing` was replaced by a freshly derived
  `documents-41` with `nameSource: derived`. The pid-file count also fell from 10 to 3
  over one day, so Claude Code prunes them. **An explicit name does not survive a
  process restart at the pid layer.** The transcript's `custom-title` line for that same
  session was untouched.

  A kit-owned sidecar would survive too, so durability alone does not choose between
  them. What chooses is **who reads it**: `custom-title` is consumed by Claude Code
  itself (it ships a compiled regex to scrape it), so a name written there appears in
  the session picker and the CLI's own listings. A sidecar is visible only to this kit.
  A name nobody but us can see is worth much less, and maintaining both would mean two
  sources of truth to reconcile.

  So: **no sidecar.** One store, the one that already exists.

  Precedence for a resolved display name, highest first:

  1. transcript last **`custom-title`** — the durable store; survives restarts and
     import, and is the only explicit record for a dead or imported session
  2. pid-file `name` with `nameSource` absent — explicit, but ephemeral
  3. transcript last **`ai-title`**
  4. `firstPrompt` / first user message
  5. pid-file `name` with `nameSource` of `derived` or `auto` — `documents-41`, which
     tells you nothing and collides across concurrent sessions
  6. short id

  **`custom-title` outranks even an explicit pid-file name** (corrected 2026-08-05; an
  earlier draft had the pid-file first). The old ordering assumed the two always agree,
  because `/rename` writes both at once. That assumption broke once the kit could write
  `custom-title` on its own: the transcript entry is then the *newer* value, and ranking
  the pid-file above it would let a stale name shadow a rename the tab is already
  displaying.

  A derived pid-file name is demoted below both transcript titles and the first prompt
  for the obvious reason: `documents-41` is less useful than "Brush up on SQL skills",
  and derived names are not unique anyway.

  **Precedence is by entry type, never by file order.** Verified 2026-08-05: the AI
  titler re-emits an `ai-title` line immediately after every `custom-title` line (lines
  275/276, 295/296, 307/308 of one transcript, an exact repeating pair), so in any
  active session the last title line is almost always an `ai-title`. A resolver that
  tails the file for "the most recent title" therefore **discards the user's rename
  every time** — and would pass a casual test, because the clobbering `ai-title` only
  lands once another message is sent. Select by type first, then take the last of that
  type.

- **Cross-version fragility** — unchanged, and now with a worked example: all pid-files
  report `2.1.220` while the installed extension is already `2.1.221`, because running
  processes predate the update. Version skew between layers is the normal state, not an
  anomaly, so accessors must tolerate it rather than assert a single version. Every
  accessor belongs in `core/` with a version check and a fail-quiet path, so a Claude
  Code update degrades the kit to "no data" rather than breakage.

### Evidence

| Claim | How it was checked |
|---|---|
| No rename command exists | `jq '.contributes.commands[]' package.json` on the v2.1.221 extension — 23 commands, none rename |
| Title set at runtime by CLI | `rename_tab` handler in `extension.js` assigns `panelTab.title` |
| `nameSource` absent when named | 8 live pid-files in `~/.claude/sessions/` compared |
| pid-file is ephemeral | keyed by pid; contains `procStart`/`startedAt` for the live process only |

Not verified: the internal layout of `state.vscdb` (reading it was blocked by a
permission guard, and the resolution above makes it moot — we never write or read it).
