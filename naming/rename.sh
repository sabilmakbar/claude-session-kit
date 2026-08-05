#!/usr/bin/env bash
# naming/rename.sh — set the current session's title.
#
# Scope is deliberately one session: the one you are in. There is no session-id
# parameter, so no caller can point this at the wrong transcript. See the decision
# record "Who renames the current session" in docs/DESIGN-naming.md before widening
# it — the rule has changed four times and every reason is written down there.
#
# Renaming *other* sessions (dead, or imported from another machine) is a real
# requirement, but its only consumer is handoff import, which does not exist yet.
# It returns with that feature, when there is a concrete caller to design the
# safety check around — import can assert against its own manifest, which is an
# independent source. A check a caller can satisfy from the same lookup it just
# performed is a speed bump wearing a guarantee's clothes, so it is not worth
# shipping ahead of a real user.
#
# The write is a single appended JSONL line, the same one /rename appends:
#   {"type":"custom-title","customTitle":"...","sessionId":"..."}
#
# Undo is another append, never a rewrite: resolution takes the LAST custom-title,
# so restoring a previous name means appending it again. We never rewrite a file
# Claude Code owns, and never touch the pid-file — that is live coordination state
# for the concurrentSessions registry, safe only because exactly one process writes
# it, through an in-memory queue nothing external can join.
#
# Source it; do not execute it.

# Finding core/ from here is the one thing that genuinely differs between shells:
# bash sets BASH_SOURCE, zsh sets $0 when sourcing, and others set neither. Guessing
# further shells is a losing game, so verify the result instead and name an escape
# hatch. This kit is bash/zsh only — every other shell fails to parse it outright
# (dash: "Syntax error: redirection unexpected"), which is a fine, loud failure. The
# case worth guarding is a shell that parses fine but resolves the path wrong, which
# is exactly how the zsh bug hid: silently, behind a nonsense path.
_nr_root="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
if [ ! -r "$_nr_root/core/sessions.sh" ]; then
    echo "rename.sh: cannot find core/sessions.sh (looked in '${_nr_root:-unresolved}')" >&2
    echo "  This shell may not expose the sourced file's path." >&2
    echo "  Set CLAUDE_SESSION_KIT_ROOT to the kit root, or source from bash or zsh." >&2
    return 1 2>/dev/null || exit 1
fi
# shellcheck source=../core/sessions.sh
. "$_nr_root/core/sessions.sh"

# Not an arbitrary sanity limit — it is what keeps the append atomic.
#
# Concurrent appends are safe because O_APPEND makes the kernel serialise the
# offset update, so two writers cannot overwrite each other. That guarantee is
# strongest for a write small enough to land in one go; it gets shakier as
# writes grow. Capping the title keeps every line we emit comfortably small
# (~300 bytes worst case), which is what lets the kit append to a transcript
# another process is also writing.
#
# /rename itself accepts pasted free text well past this — a 553-character,
# 7-line entry exists in a real transcript. We deliberately do not.
RENAME_MAX_TITLE=200

# rename_check_title <title> -> non-zero with a reason on stderr if unusable.
rename_check_title() {
    local t="$1"
    [ -n "$t" ] || { echo "rename: empty title" >&2; return 1; }
    case "$t" in *$'\n'*) echo "rename: title must be a single line" >&2; return 1;; esac
    [ "${#t}" -le "$RENAME_MAX_TITLE" ] || {
        echo "rename: title longer than $RENAME_MAX_TITLE characters" >&2; return 1; }
    return 0
}

# rename_current_title -> the title a rename would replace. Empty if never renamed.
rename_current_title() {
    local id tr
    id=$(cs_current_id); [ -n "$id" ] || return 1
    tr=$(cs_transcript_path "$id") || return 1
    cs_custom_title "$tr"
}

# rename_apply <title> -> set the current session's title.
#
# No session-id parameter by design: this cannot be aimed at another transcript.
#
# Writes the transcript only. /rename additionally updates the pid-file name, but
# that value is regenerated as `documents-NN` at every process start regardless of
# who wrote it, so its advantage lasts one process lifetime while the paste it
# costs is permanent. Full reasoning in the decision record.
rename_apply() {
    local title="$1" id tr line
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

# rename_command <title> -> the /rename line, for a user who also wants the
# pid-file layer updated. Not part of the normal flow; rename_apply is complete.
rename_command() { printf '/rename %s' "$1"; }
