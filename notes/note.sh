#!/usr/bin/env bash
# notes/note.sh — per-session working note: decided / done / next.
#
# The agent writes it (session-note skill); hooks/session-note.sh surfaces it once
# when the session is reopened. Decisions and reasons: docs/DESIGN-notes.md.
#
# Write side is current-session only — no session-id parameter, same argument as
# rename_apply. Notes are stored OUTSIDE the installed-code tree so uninstall can
# never delete them. Every render carries the note's age; a stale note presented as
# current is worse than no note.
#
# Source it; do not execute it. bash and zsh both work; keep it that way.

_nn_root="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
if [ ! -r "$_nn_root/core/sessions.sh" ]; then
    echo "note.sh: cannot find core/sessions.sh (looked in '${_nn_root:-unresolved}')" >&2
    echo "  Set CLAUDE_SESSION_KIT_ROOT to the kit root, or source from bash or zsh." >&2
    return 1 2>/dev/null || exit 1
fi
# shellcheck source=../core/sessions.sh
. "$_nn_root/core/sessions.sh"

# Data directory — deliberately NOT under session-kit/, which uninstall removes.
_nn_dir() { printf '%s/.claude/session-notes' "$(_cs_home)"; }

# _nn_safe <id> -> the id unchanged, or non-zero. The id becomes a filename, so
# anything outside [A-Za-z0-9-] (slashes, dots) could escape the notes directory.
_nn_safe() {
    local id="$1" clean=""
    clean=$(printf '%s' "$id" | tr -cd 'A-Za-z0-9-')
    [ -n "$clean" ] && [ "$clean" = "$id" ] && [ "${#clean}" -le 64 ] || return 1
    printf '%s' "$clean"
}

_nn_transcript_lines() {  # <id> -> entry count of the transcript, or non-zero
    local tr=""
    tr=$(cs_transcript_path "$1") || return 1
    wc -l <"$tr" | tr -d ' '
}

_nn_live_pid() {  # <id> -> pid of the live CLI process running this session
    local pf="" pid=""
    pf=$(cs_pid_file "$1") || return 1
    pid=$(jq -r '.pid // empty' "$pf" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    printf '%s' "$pid"
}

# note_write  (body on stdin) -> write the current session's note, replacing any
# previous one. History is not kept here — the transcript already records every
# version. The first line stores the transcript size at write time; that is what
# makes note_age possible.
note_write() {
    local id="" dir="" tmp="" lines="" pid=""
    cs_have_deps || { echo "note: jq not found" >&2; return 1; }
    id=$(cs_current_id)
    id=$(_nn_safe "$id") || { echo "note: no current session (CLAUDE_CODE_SESSION_ID unset)" >&2; return 1; }
    dir=$(_nn_dir)
    mkdir -p "$dir" 2>/dev/null || { echo "note: cannot create $dir" >&2; return 1; }

    lines=$(_nn_transcript_lines "$id") || lines=""
    tmp="$dir/.$id.tmp.$$"
    { printf '<!-- lines=%s -->\n' "${lines:-?}"; cat; } >"$tmp" || { rm -f "$tmp"; return 1; }

    # An empty note would surface as noise at every future resume.
    sed 1d "$tmp" | grep -q '[^[:space:]]' || {
        rm -f "$tmp"; echo "note: empty body — nothing written" >&2; return 1; }

    mv "$tmp" "$dir/$id.md" || { rm -f "$tmp"; return 1; }

    # The writing process already has the note in its context; only FUTURE processes
    # should have it surfaced. Stamp the seen-marker with the writer's own pid.
    if pid=$(_nn_live_pid "$id"); then
        printf '%s\n' "$pid" >"$dir/$id.seen" 2>/dev/null
    fi
    return 0
}

# note_read <id> -> the note body. Strips the metadata line only if it is one.
note_read() {
    local id="" f=""
    id=$(_nn_safe "$1") || return 1
    f="$(_nn_dir)/$id.md"
    [ -r "$f" ] || return 1
    sed '1{/^<!-- lines=/d;}' "$f"
}

# note_age <id> -> transcript entries added since the note was written; "?" when it
# cannot tell (no transcript, hand-edited header, transcript shrank).
note_age() {
    local id="" f="" stored="" now=""
    id=$(_nn_safe "$1") || return 1
    f="$(_nn_dir)/$id.md"
    [ -r "$f" ] || return 1
    stored=$(head -1 "$f" | sed -n 's/^<!-- lines=\([0-9][0-9]*\) -->$/\1/p')
    now=$(_nn_transcript_lines "$id") || now=""
    if [ -z "$stored" ] || [ -z "$now" ] || [ "$now" -lt "$stored" ]; then
        printf '?'; return 0
    fi
    printf '%s' $((now - stored))
}

# note_render <id> -> the display text a resuming session receives. The age line is
# not decoration — presenting a stale note as current is the feature's one way to do
# harm, so every render carries it.
note_render() {
    local id="" body="" age=""
    id=$(_nn_safe "$1") || return 1
    body=$(note_read "$id") || return 1
    age=$(note_age "$id")
    case "$age" in
        '?') printf 'Session note (age unknown — verify against the conversation before trusting it):\n%s\n' "$body";;
        *)   printf 'Session note (written %s transcript entries ago — verify anything that may have changed since):\n%s\n' "$age" "$body";;
    esac
}
