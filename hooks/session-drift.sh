#!/usr/bin/env bash
# hooks/session-drift.sh — UserPromptSubmit hook: get the drift question asked at the
# right moments. It never judges drift itself.
#
# Whether a conversation still matches its title is a semantic question, and every
# mechanical heuristic for it (the original sketch tried keyword overlap) is a guess
# that trains the user to ignore alarms. The agent already holds the whole
# conversation in context and judges it for free — so this hook only decides WHEN to
# ask, and the payload tells the agent to stay silent unless something is actually
# off. A wasted check costs one silent thought, not an interruption.
#
# Two gates, one marker file ("<pid> <lines>"):
#
#   A. New process on a session with real history → wrong-session check on the FIRST
#      message, which is the only moment it helps: the mistake is caught before the
#      context is polluted. Suppressed for near-empty sessions, where there is no
#      established topic to be wrong about.
#   B. ~CS_DRIFT_EVERY transcript entries since the last check (default 200) →
#      rename-or-split self-check. Gradual drift accumulates with volume, so the
#      cadence is volume, not time.
#
# Same proven plumbing as the other hooks: session id from stdin, plain stdout,
# every failure path exits 0 and prints nothing.

set -u

ROOT="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
[ -r "${ROOT:-}/core/sessions.sh" ] || exit 0
. "$ROOT/core/sessions.sh" 2>/dev/null || exit 0

# Before the jq guard, because a missing jq is one of the faults this reports and
# every line below needs jq. Throttled in core, so the three prompt hooks report a
# fault once between them rather than once each.
cs_notice_degraded

command -v jq >/dev/null 2>&1 || exit 0

EVERY="${CS_DRIFT_EVERY:-$(cs_conf CS_DRIFT_EVERY 200)}"
MIN_HISTORY="${CS_DRIFT_MIN_HISTORY:-$(cs_conf CS_DRIFT_MIN_HISTORY 20)}"

input=$(cat 2>/dev/null) || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9-')
[ -n "$sid" ] || exit 0

tr_path=$(cs_transcript_path "$sid") || exit 0
lines=$(wc -l <"$tr_path" | tr -d ' ')

pf=$(cs_pid_file "$sid") || exit 0
pid=$(jq -r '.pid // empty' "$pf" 2>/dev/null)
{ [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } || exit 0

DRIFT="$(_cs_state_dir)/drift"
seen_pid=""; seen_lines=0
if [ -r "$DRIFT/$sid" ]; then
    read -r seen_pid seen_lines <"$DRIFT/$sid" 2>/dev/null || true
    seen_pid=$(printf '%s' "$seen_pid" | tr -cd '0-9')
    seen_lines=$(printf '%s' "$seen_lines" | tr -cd '0-9'); : "${seen_lines:=0}"
fi

mark() { mkdir -p "$DRIFT" 2>/dev/null && printf '%s %s\n' "$pid" "$lines" >"$DRIFT/$sid" 2>/dev/null; }

name=$(cs_resolve_name "$sid" 2>/dev/null)
[ -n "$name" ] || exit 0

if [ "$pid" != "$seen_pid" ]; then
    # Gate A: first message to a newly opened process. Mark BEFORE printing so a
    # failure cannot repeat the check on every prompt.
    mark || exit 0
    [ "$lines" -ge "$MIN_HISTORY" ] || exit 0
    printf 'Wrong-session check (first message after reopening): this session is about "%s" (%s entries of history). If the user'\''s message clearly belongs to different work, STOP before answering: run NO tool calls toward that question — no locating, no scanning, nothing preliminary; even a directory listing pollutes this session. The only permitted lookup is routing: `. %s/core/sessions.sh && cs_find "<topic words>"` to find an existing session for it. Then offer, in order: (1) the existing session, by title, if cs_find found one; (2) a fresh session, offering to carry the question over via the handoff skill; (3) doing it here — only if the user explicitly says so after seeing 1 and 2. If the message fits this session, answer normally and do not mention this check. This is the full briefing, delivered once; a one-line version of it now arrives on every message, so nothing here depends on you remembering it.\n' \
        "$name" "$lines" "$ROOT"
    exit 0
fi

if [ $((lines - seen_lines)) -ge "$EVERY" ]; then
    # Gate B: enough has happened since the last look.
    mark || exit 0
    case "$name" in
        "${sid:0:8}")
            printf 'Naming check: this session has no real title (only its id, %s entries in). If the work has taken a clear shape, offer to name it via the rename-session skill; otherwise say nothing.\n' "$lines" ;;
        *)
            printf 'Drift check (runs every ~%s entries — judge silently, mention it ONLY if something is off): this session is titled "%s". If the recent conversation still matches, say nothing. If it is the same work evolved past that title, offer the rename-session skill. If a distinct second topic has grown here, offer to split it into a fresh session via the handoff skill.\n' \
                "$EVERY" "$name" ;;
    esac
    exit 0
fi

# Gate C: the standing wrong-session check, on EVERY message.
#
# Gate A used to carry this duty in a closing sentence asking the agent to keep watch
# for the rest of the sitting. That failed in the way asking anyone to remember fails
# (issue #20): the off-topic message arrived several turns in, by which time the one
# delivery had been pushed down by the work in between, and the session absorbed a
# repository inspection, a read of the global settings file, and an edit to a handoff
# note owned by a different session.
#
# Off-topic messages do not preferentially arrive first, so a check that only fires on
# the first message is not aimed at the problem. This one is present whenever a message
# is, which is the only cadence that matches when the fault can occur. It is kept to one
# short line precisely because it repeats, and it stays a hint: it never refuses, and it
# still ends at the user's choice (D7 in DESIGN-naming.md).
[ "$lines" -ge "$MIN_HISTORY" ] || exit 0
printf 'Session check (every message; judge silently, say nothing when the message fits): this session is "%s". If this message belongs to different work, do not begin it here, not even a lookup. Route first with `. %s/core/sessions.sh && cs_find "<topic words>"`, then offer, in order: (1) the session it found, by title; (2) a fresh session, carrying the question over via the handoff skill; (3) doing it here, only if the user says so after seeing 1 and 2.\n' \
    "$name" "$ROOT"
exit 0
