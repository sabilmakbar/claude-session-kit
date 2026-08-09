#!/usr/bin/env bash
# hooks/session-guard.sh — UserPromptSubmit hook: after a split, remind the OLD
# session (once per opening) that the topic moved. Soft guard, never a refusal:
# deciding whether a question is "about the handed-over topic" is unproven content
# matching, and a wrong hint costs one sentence where a wrong refusal blocks real
# work (DESIGN-handoff.md). Recall questions about what happened before the split
# are explicitly fine — the old transcript is the only place the argument survives.
#
# Same delivery as session-note.sh, for the same receipts: UserPromptSubmit stdin
# carries .session_id, plain stdout reaches the model, and a pid marker keeps it to
# once per opened session. Every failure path exits 0 and prints nothing.

set -u

ROOT="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
[ -r "${ROOT:-}/core/sessions.sh" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$ROOT/core/sessions.sh" 2>/dev/null || exit 0

input=$(cat 2>/dev/null) || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
[ -n "$sid" ] || exit 0

HANDOFFS="$(_cs_home)/.claude/session-handoffs"
M="$HANDOFFS/$sid.handed"
[ -r "$M" ] || exit 0

pf=$(cs_pid_file "$sid") || exit 0
pid=$(jq -r '.pid // empty' "$pf" 2>/dev/null)
{ [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } || exit 0
seen=""
[ -r "$HANDOFFS/$sid.guard-seen" ] && seen=$(head -1 "$HANDOFFS/$sid.guard-seen" 2>/dev/null | tr -cd '0-9')
[ "$pid" = "$seen" ] && exit 0

topic=$(jq -r '.topic // empty' "$M" 2>/dev/null)
to=$(jq -r '.to // empty' "$M" 2>/dev/null)
date=$(jq -r '.date // empty' "$M" 2>/dev/null)
folder=$(jq -r '.folder // empty' "$M" 2>/dev/null)

dest="a fresh session that has not claimed it yet"
[ -z "$to" ] || dest="session ${to:0:8}"

printf '%s\n' "$pid" >"$HANDOFFS/$sid.guard-seen" 2>/dev/null || exit 0

printf 'This session split off a topic%s on %s — it now lives in %s (note: %s/HANDOFF.md). If the user is continuing that work, point them to the new session instead of doing it here; questions about what happened BEFORE the split are fine to answer normally. If the work belongs back here, release the guard: bash %s/handoff/release.sh\n' \
    "${topic:+ (\"$topic\")}" "${date:-an earlier date}" "$dest" "$folder" "$ROOT"
exit 0
