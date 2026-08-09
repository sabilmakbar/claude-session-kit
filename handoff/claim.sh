#!/usr/bin/env bash
# handoff/claim.sh — complete a same-machine split from inside the FRESH session.
#
#   handoff/claim.sh <handoff-folder>
#
# The split recorded the link as pending because this session's id did not exist yet.
# Claiming completes it in both directions: the old session's marker gains the real
# destination (so its guard can name where the work went), and this session records
# where it came from. Then the note is printed — it is this session's seed context.
#
# The note's own '## Assertions' section is the quality check: after reading, the
# claiming agent must be able to restate each one FROM THE NOTE. That check is
# semantic, so it belongs to the agent (the handoff skill instructs it); this script
# checks structure only. Run it early — the old session is still alive, so an
# inadequate note can be fixed right now instead of discovered weeks later.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
. "$ROOT/core/sessions.sh"

[ $# -eq 1 ] || { echo "usage: claim.sh <handoff-folder>" >&2; exit 2; }
DIR="$1"
[ -d "$DIR" ] || { echo "claim: no such folder $DIR" >&2; exit 1; }
[ -r "$DIR/HANDOFF.md" ] || { echo "claim: $DIR has no HANDOFF.md" >&2; exit 1; }
[ -r "$DIR/from" ] || { echo "claim: $DIR has no 'from' file — not written by split.sh" >&2; exit 1; }
cs_have_deps || { echo "claim: jq not found" >&2; exit 1; }

NEW=$(cs_current_id)
[ -n "$NEW" ] || { echo "claim: no current session (CLAUDE_CODE_SESSION_ID unset)" >&2; exit 1; }

OLD=$(head -1 "$DIR/from" | tr -cd 'A-Za-z0-9-')
[ -n "$OLD" ] || { echo "claim: 'from' file is empty" >&2; exit 1; }
[ "$OLD" != "$NEW" ] || { echo "claim: this IS the session that split — claim from the fresh one" >&2; exit 1; }

HANDOFFS="$(_cs_home)/.claude/session-handoffs"
MARKER="$HANDOFFS/$OLD.handed"

# Complete the old side, if its marker still exists (it may have been released).
if [ -r "$MARKER" ]; then
    jq --arg to "$NEW" '.to = $to' "$MARKER" >"$MARKER.tmp" && mv "$MARKER.tmp" "$MARKER"
fi

mkdir -p "$HANDOFFS"
jq -n --arg from "$OLD" --arg dir "$DIR" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{from:$from, folder:$dir, date:$date}' >"$HANDOFFS/$NEW.claimed"

echo "claim: linked ${OLD:0:8} -> ${NEW:0:8}"
echo
echo "--- HANDOFF note (this session's seed context) ---"
cat "$DIR/HANDOFF.md"
