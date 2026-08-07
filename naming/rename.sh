#!/usr/bin/env bash
# naming/rename.sh — set the current session's title.
#
# Current session only: no session-id parameter, so it cannot be aimed elsewhere.
# Widening this needs the decision record "Who renames the current session" in
# docs/DESIGN-naming.md first — the rule has already reversed several times and every
# refuted reason is there. Other-session rename returns with handoff import.
#
# Writes one appended JSONL line: {"type":"custom-title","customTitle":…,"sessionId":…}
# Undo is another append, since resolution takes the LAST custom-title. Never rewrite
# a transcript, and never touch the pid-file (live coordination state, single-writer).
#
# Source it; do not execute it. The shebang is a dialect hint, not enforcement — a
# sourced file runs under the caller's shell. bash and zsh both work; keep it that way.

# Finding core/ is the one thing that genuinely differs between shells: bash sets
# BASH_SOURCE, zsh sets $0 when sourcing, others set neither. So verify the result and
# name an escape hatch rather than guess further shells — the case worth catching is a
# shell that parses fine but resolves the path wrong, which is how the zsh bug hid.
_nr_root="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
if [ ! -r "$_nr_root/core/sessions.sh" ]; then
    echo "rename.sh: cannot find core/sessions.sh (looked in '${_nr_root:-unresolved}')" >&2
    echo "  This shell may not expose the sourced file's path." >&2
    echo "  Set CLAUDE_SESSION_KIT_ROOT to the kit root, or source from bash or zsh." >&2
    return 1 2>/dev/null || exit 1
fi
# shellcheck source=../core/sessions.sh
. "$_nr_root/core/sessions.sh"

# Not a style limit — it keeps the append atomic. O_APPEND makes the kernel serialise
# the offset update, which is what lets the kit append to a transcript another process
# is also writing; that guarantee is strongest for a write small enough to land in one
# go. 200 keeps every line we emit ~300 bytes worst case. /rename itself accepts far
# longer pasted text (a 553-char entry exists in a real transcript); we do not.
RENAME_MAX_TITLE=200

# rename_check_title <title> -> non-zero with a reason on stderr if unusable.
#
# Whitespace-only is rejected for the same reason empty is: resolution drops entries
# that collapse to nothing, so writing one appends a line that changes no name. The
# rename would report success and do nothing.
#
# Length is measured in BYTES, not characters. The cap protects the atomicity of the
# append, which is a byte-level property, and `${#t}` counts characters or bytes
# depending on the locale — so the same title could be accepted on one machine and
# rejected on another.
rename_check_title() {
    local t="$1" bytes=0
    [ -n "$t" ] || { echo "rename: empty title" >&2; return 1; }
    case "$t" in *[![:space:]]*) ;; *) echo "rename: title is only whitespace" >&2; return 1;; esac
    case "$t" in *$'\n'*) echo "rename: title must be a single line" >&2; return 1;; esac
    bytes=$(printf '%s' "$t" | wc -c | tr -d ' ')
    [ "$bytes" -le "$RENAME_MAX_TITLE" ] || {
        echo "rename: title is $bytes bytes, limit is $RENAME_MAX_TITLE" >&2; return 1; }
    return 0
}

# rename_current_title -> the title a rename would replace. Empty if never renamed.
rename_current_title() {
    local id="" tr=""
    id=$(cs_current_id); [ -n "$id" ] || return 1
    tr=$(cs_transcript_path "$id") || return 1
    cs_custom_title "$tr"
}

# rename_apply <title> -> set the current session's title.
#
# Transcript only. /rename also updates the pid-file name, but that value is
# regenerated as `documents-NN` at every process start regardless of who wrote it, so
# its advantage lasts one process lifetime. Full reasoning in the decision record.
rename_apply() {
    local title="$1" id="" tr="" line=""
    rename_check_title "$title" || return 1
    cs_have_deps || { echo "rename: jq not found" >&2; return 1; }
    cs_version_guard

    id=$(cs_current_id)
    [ -n "$id" ] || { echo "rename: no current session (CLAUDE_CODE_SESSION_ID unset)" >&2; return 1; }
    tr=$(cs_transcript_path "$id") || { echo "rename: no transcript for $id" >&2; return 1; }

    line=$(jq -cn --arg t "$title" --arg id "$id" \
        '{type:"custom-title",customTitle:$t,sessionId:$id}') || {
        echo "rename: could not encode title" >&2; return 1; }

    printf '%s\n' "$line" >>"$tr" || { echo "rename: append failed" >&2; return 1; }
    return 0
}
