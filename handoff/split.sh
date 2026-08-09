#!/usr/bin/env bash
# handoff/split.sh — same-machine session split: hand a topic to a fresh session.
#
#   handoff/split.sh -n <note.md> [-t "<topic>"]     (run inside the OLD session)
#
# Writes a plain FOLDER, not a bundle (DESIGN-handoff.md: nothing crosses a machine
# gap, so checksums and tarballs would be ceremony). The folder holds the note and a
# `from` file naming this session; the old transcript never moves and stays resumable.
#
# The new session does not exist yet, so the link is recorded as PENDING here and
# completed by handoff/claim.sh from inside the fresh session. Until the guard is
# released (handoff/release.sh), hooks/session-guard.sh reminds this session that the
# topic moved.
#
# Current session only, same argument as note_write: the note summarises a
# conversation only its own session can see.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
. "$ROOT/core/sessions.sh"

usage() { echo "usage: split.sh -n <note.md> [-t \"<topic>\"]" >&2; exit 2; }

NOTE=""; TOPIC=""
while getopts 'n:t:' opt; do
    case "$opt" in
        n) NOTE="$OPTARG" ;;
        t) TOPIC="$OPTARG" ;;
        *) usage ;;
    esac
done
[ -n "$NOTE" ] || usage
[ -r "$NOTE" ] || { echo "split: cannot read note $NOTE" >&2; exit 1; }
grep -q '[^[:space:]]' "$NOTE" || { echo "split: the note is empty" >&2; exit 1; }
cs_have_deps || { echo "split: jq not found" >&2; exit 1; }
cs_version_guard

ID=$(cs_current_id)
[ -n "$ID" ] || { echo "split: no current session (CLAUDE_CODE_SESSION_ID unset)" >&2; exit 1; }

# The note carries its own quality bar: assertions the reader must be able to
# restate. Their absence is a warning, not a refusal — the note is still a note.
grep -qi '^## *assertions' "$NOTE" || {
    echo "split: note has no '## Assertions' section — the claim step cannot check it" >&2; }

HANDOFFS="$(_cs_home)/.claude/session-handoffs"
STAMP=$(date +%Y%m%d-%H%M%S)
DIR="$HANDOFFS/$STAMP-split"
mkdir -p "$DIR"
cp "$NOTE" "$DIR/HANDOFF.md"
printf '%s\n' "$ID" >"$DIR/from"

# One active handoff per session: a second split overwrites the first, and the guard
# always points at the latest. Multiple simultaneous outbound topics is a state this
# kit does not model.
jq -n --arg dir "$DIR" --arg topic "$TOPIC" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{folder:$dir, topic:$topic, date:$date, to:null}' >"$HANDOFFS/$ID.handed"

echo "split: folder written — $DIR"
echo "next: open a FRESH session and have it run:"
echo "  bash '$ROOT/handoff/claim.sh' '$DIR'"
