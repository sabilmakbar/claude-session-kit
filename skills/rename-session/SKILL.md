---
name: rename-session
description: Propose one brief, descriptive sentence-style title for the current Claude Code session by reading its transcript, then apply it directly. Use when the user asks to rename this session, suggest a session name, or says the session title has gone stale or no longer matches what the work became. Renames the current session only.
---

# Rename a session

You read the transcript, decide one title, and apply it the only way that works for
that session. The user should not have to invent a name or know which storage layer
is involved.

## 1. Read the arc

```bash
. core/sessions.sh
tr=$(cs_transcript_path "$CLAUDE_CODE_SESSION_ID")
cs_resolve_name "$CLAUDE_CODE_SESSION_ID"      # the name it has now
```

For the current session you already have the conversation in context — use it, and
read the transcript only to recover earlier parts that have been compacted away.

## 2. Write one title

**Name the arc, not either endpoint.** This is the whole job, and both ends are
traps. The existing `ai-title` is pinned to the opening message and never updates,
so it describes only where the session started. Naming it after the last hour is the
same mistake reversed — a session covering a machine setup, a release, a sync
redesign and two new repos is not "session-kit-project-structure" just because that
came up most recently. Cover the span of work.

Then:

- **Sentence-style, not a slug.** This is the rule most often broken — earlier
  versions of this skill broke it — so check the output against it before presenting
  anything.

  - Capitalise the first word. Use spaces between words.
  - Never slugify the title itself: if the whole thing is joined by `-` or `_`, it
    is an identifier, not a title.
  - A colon is the natural separator for scope and detail: `Scope: what happened`.
  - **Keep real names exactly as they are spelled.** Repos, packages, commands and
    files are proper nouns — `relo-calculator`, `claude-session-kit`, `jq`, `macOS`
    — and must never be "de-slugified" into prose. The rule is about the sentence
    around them, not about the names themselves.

  | Write this | Not this |
  |---|---|
  | `Check relo-calculator deployment readiness` | `check-relo-calculator-deploy` |
  | `Memory & session toolkits: Mac setup, sync redesign` | `memory-session-toolkit-buildout` |
  | `Session naming: title storage internals` | `session-kit-naming-investigation` |
  | `Recreate codebase with anonymized data` | `recreate_codebase_anon` |

  The first row is a real auto-generated title from this machine, and it is the
  model to follow: a sentence, with the repo name left intact inside it. `/rename`
  accepts free text and imposes no format, so the slug habit comes from us, not the
  tool.
- **Front-load what distinguishes it.** Tabs shrink as more are opened, so the
  visible width is small and unpredictable — never assume a character budget. Put the
  words that tell sessions apart first, so the title still reads at any truncation
  point. The full string survives in the session list and in search.
- **One title.** Offer alternatives only if the user asks or the arc genuinely
  splits in two.
- Keep it under 200 characters and on a single line.

## 3. Apply it

Apply it directly. No paste, no follow-up step:

```bash
. naming/rename.sh
rename_apply "<title>"
```

There is no session-id parameter. **This renames the session you are in, and only
that one** — the scope is structural, not a check. Renaming other sessions comes
back with handoff import; see the decision record in `docs/DESIGN-naming.md`.

Then tell the user the tab updates when they close and reopen the session, not
immediately. That is expected — the tab reads its title when the panel opens — and
is not a sign anything failed. The name is live right away in the session picker
and in `cs_list`.

**Do not offer `/rename` as a follow-up.** The rename is complete. `/rename` also
writes the pid-file name, but that value is regenerated as `documents-NN` at every
process restart no matter who wrote it — it erased a `/rename`-set name within
hours on the machine this was designed on. Mentioning it turns a finished job into
a chore. Say it only if the user asks what `/rename` does differently.

If a user asks you to rename a *different* session, say plainly that the kit does
not do that yet and why — it is waiting on handoff import, not an oversight.

## Undo

Restoring a previous name is another append, never an edit:

```bash
. naming/rename.sh
rename_current_title            # what it is now — capture this BEFORE renaming
rename_apply "<old title>"      # append the old value back
```

Neither takes a session id. `rename_apply` reads its title from `$1`, so passing an
id first would append the **UUID** as the title — it is a valid single-line string
under 200 characters, so every check passes and nothing complains.

Never rewrite or hand-edit a transcript to remove a title.
