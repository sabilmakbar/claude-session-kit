#!/usr/bin/env bash
# hooks/session-note.sh — UserPromptSubmit hook: hand the session its own note back,
# once per opened session. Decisions and evidence: docs/DESIGN-notes.md.
#
# UserPromptSubmit rather than SessionStart, and plain stdout rather than JSON — both
# on receipts, not preference: the memory kit's delta-ping hook has delivered
# .session_id and plain-text context this way across dozens of real prompts, while
# SessionStart delivering a session id is unproven. Plain text also cannot become
# invalid JSON, so a note full of quotes cannot be silently discarded.
#
# Every failure path exits 0 and prints nothing. Breaking prompt submission is
# strictly worse than skipping a note.

set -u

ROOT="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
[ -r "${ROOT:-}/notes/note.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$ROOT/notes/note.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
[ -n "$sid" ] || exit 0

[ -r "$(_nn_dir)/$sid.md" ] || exit 0

# Once per opened session: the pid-file names the CLI process currently running this
# session, the .seen marker names the process the note was last shown to (or that
# wrote it). Same process → already delivered → silent. No live pid yet (registration
# lag on the very first prompt) → skip now, the next prompt catches it.
pid=$(_nn_live_pid "$sid") || exit 0
seen=""
[ -r "$(_nn_dir)/$sid.seen" ] && seen=$(head -1 "$(_nn_dir)/$sid.seen" 2>/dev/null | tr -cd '0-9')
[ "$pid" = "$seen" ] && exit 0

out=$(note_render "$sid" 2>/dev/null)
[ -n "$out" ] || exit 0

# Mark BEFORE printing: if the write fails, stay silent rather than risk repeating
# the note on every prompt of this session.
printf '%s\n' "$pid" >"$(_nn_dir)/$sid.seen" 2>/dev/null || exit 0

printf '%s\n(If this note no longer matches the conversation, say so briefly and update it with the session-note skill.)\n' "$out"
exit 0
