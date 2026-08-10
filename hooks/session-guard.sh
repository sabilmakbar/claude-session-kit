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

# --- pickup side: a BRAND-NEW session meets a pending handoff -------------------
#
# The one step that cannot be automated is opening the fresh tab (no receipted way
# to drive the VS Code UI — same discipline as never touching state.vscdb). This
# removes every step after it: the new session's first message surfaces the pending
# handoff and the agent claims it, the user's own message serving as confirmation.
# Scoped hard so it cannot nag: only sessions with almost no history, only handoffs
# from the last 48h, only while unclaimed, and mentioned exactly once per session.
if [ ! -r "$M" ]; then
    lines=0
    tp=$(cs_transcript_path "$sid") && lines=$(wc -l <"$tp" | tr -d ' ')
    [ "$lines" -lt "${CS_PICKUP_MAX_HISTORY:-20}" ] || exit 0
    [ ! -e "$HANDOFFS/$sid.pickup-seen" ] || exit 0
    [ ! -e "$HANDOFFS/$sid.claimed" ] || exit 0

    pending=""
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        [ "$(basename "$m" .handed)" = "$sid" ] && continue
        [ "$(jq -r '.to // empty' "$m" 2>/dev/null)" = "" ] && pending="$m"
    done < <(find "$HANDOFFS" -maxdepth 1 -name '*.handed' -mmin -"${CS_PICKUP_WINDOW_MIN:-2880}" 2>/dev/null | sort)
    [ -n "$pending" ] || exit 0

    OLD=$(basename "$pending" .handed)
    topic=$(jq -r '.topic // empty' "$pending" 2>/dev/null)
    folder=$(jq -r '.folder // empty' "$pending" 2>/dev/null)
    from=$(cs_resolve_name "$OLD" 2>/dev/null)

    mkdir -p "$HANDOFFS" 2>/dev/null && : >"$HANDOFFS/$sid.pickup-seen" 2>/dev/null || exit 0
    printf 'A pending same-machine handoff is waiting to be claimed: topic%s, split from session "%s". If the user'\''s message is about continuing that work (or they say to claim it), claim it NOW — run: bash %s/handoff/claim.sh %s — it links the sessions and prints the handoff note as this session'\''s seed context; treat the user'\''s message itself as the confirmation, do not ask again. If their message is about something unrelated, mention the pending handoff in one sentence and answer their actual question; do not bring it up again.\n' \
        "${topic:+ \"$topic\"}" "${from:-$OLD}" "$ROOT" "'$folder'"
    exit 0
fi

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

# Unclaimed past the pickup window: the split has gone stale, and the message must
# say so — the mechanisms (manual claim, re-split, release) all exist, but a user
# reading "not claimed yet" forever has no way to know them.
if [ -z "$to" ] && [ -n "$(find "$M" -mmin +"${CS_PICKUP_WINDOW_MIN:-2880}" 2>/dev/null)" ]; then
    printf 'This session split off a topic%s on %s, but it was NEVER CLAIMED and the automatic pickup window has passed — the split has gone stale. Tell the user, and offer the three exits: (1) claim it manually from any fresh session: bash %s/handoff/claim.sh %s (claiming never expires, only the automatic nudge did); (2) re-split via the handoff skill — a fresh note re-arms automatic pickup, and is the right move if the old note no longer matches reality; (3) release, if the work belongs back here: bash %s/handoff/release.sh. The folder and its note are kept whichever way this goes.\n' \
        "${topic:+ (\"$topic\")}" "${date:-an earlier date}" "$ROOT" "'$folder'" "$ROOT"
    exit 0
fi

printf 'This session split off a topic%s on %s — it now lives in %s (note: %s/HANDOFF.md). If the user is continuing that work, point them to the new session instead of doing it here; questions about what happened BEFORE the split are fine to answer normally. If the work belongs back here, release the guard: bash %s/handoff/release.sh\n' \
    "${topic:+ (\"$topic\")}" "${date:-an earlier date}" "$dest" "$folder" "$ROOT"
exit 0
