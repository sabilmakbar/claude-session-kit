#!/usr/bin/env bash
# handoff/release.sh — remove a split's guard: the work belongs here again.
#
#   handoff/release.sh [<session-id>]        (defaults to the current session)
#
# The design requires this to exist and be one obvious step: a guard that cannot be
# turned off turns a stale marker into a permanently half-crippled session. Releasing
# removes the old session's marker (so the guard hook goes quiet) and the paired
# claim marker, if the claim happened. The handoff FOLDER is never touched — it is
# the written record of why the split happened, and records are kept, not tidied.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
. "$ROOT/core/sessions.sh"

ID="${1:-$(cs_current_id)}"
ID=$(printf '%s' "$ID" | tr -cd 'A-Za-z0-9-')
[ -n "$ID" ] || { echo "release: no session id (pass one, or run inside a session)" >&2; exit 2; }

HANDOFFS="$(_cs_home)/.claude/session-handoffs"
MARKER="$HANDOFFS/$ID.handed"
[ -r "$MARKER" ] || { echo "release: ${ID:0:8} has no active handoff — nothing to release" >&2; exit 1; }

TO=$(jq -r '.to // empty' "$MARKER" 2>/dev/null)
# TO names a file to delete, so it must be a session id and nothing else. Checked
# before anything is removed: a marker carrying a path is not one claim.sh wrote.
case "$TO" in
    *[!A-Za-z0-9-]*)
        echo "release: ${ID:0:8}'s marker links to '$TO', which is not a session id — refusing" >&2
        echo "  nothing was removed; inspect $MARKER by hand" >&2
        exit 1 ;;
esac
rm -f "$MARKER" "$HANDOFFS/$ID.guard-seen"
[ -z "$TO" ] || rm -f "$HANDOFFS/$TO.claimed"

echo "release: guard removed from ${ID:0:8}${TO:+ (link to ${TO:0:8} cleared)}"
echo "the handoff folder is untouched — it stays as the record of the split"
