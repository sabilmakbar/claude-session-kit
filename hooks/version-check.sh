#!/usr/bin/env bash
# hooks/version-check.sh — SessionStart hook. Re-verifies the kit after Claude Code
# updates, so nobody has to remember to.
#
# Wire it up with:
#   "$HOME/.claude/session-kit/hooks/version-check.sh" 2>/dev/null || true
#
# Cost in the normal case is one directory scan and one file read, then it exits.
# The expensive path only happens when the version actually moved, which is roughly
# monthly, and even then the work is backgrounded so session start never waits.
#
# It reports nothing, on purpose. On success smoke.sh records the version and the
# in-session warning stops. On failure it records nothing, so the warning keeps
# appearing every time you use the kit. The missing write is the report — a hook
# that printed its own failures would either be ignored or would spam a session
# the user is trying to start.
#
# Everything here is /usr/bin: bash, find, jq. Hooks run with a minimal PATH, which
# is why hooks depending on node fail with "command not found" while this does not.

set -u

ROOT="${CLAUDE_SESSION_KIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"

# Every failure below exits 0. A hook must never break session start, and a kit that
# is not installed properly is not the user's problem at this moment.
[ -n "${ROOT:-}" ] || exit 0
[ -r "$ROOT/core/sessions.sh" ] || exit 0
[ -r "$ROOT/tests/smoke.sh" ]   || exit 0
command -v jq >/dev/null 2>&1   || exit 0

. "$ROOT/core/sessions.sh" 2>/dev/null || exit 0

# Empty means no Claude Code process has registered yet — including, sometimes, the
# session currently starting, since the pid-file may not be written at hook time.
# Skipping is correct: the next session start catches it.
running=$(cs_running_version 2>/dev/null) || exit 0
[ -n "$running" ] || exit 0

# Membership, not equality against the newest: a machine with several sessions open
# on different versions flips between them, and equality re-ran the suite on every
# flip for versions it had already cleared.
cs_version_verified "$running" && exit 0

# One attempt per version per day — borrowed back from claude-memory-kit, which
# adopted this hook's design and fixed its flaw: a persistently failing suite used
# to re-run on every session start, and the answer does not change by re-asking.
# smoke.sh already leaves the redacted failure report as the receipt. Stamp BEFORE
# spawning, so a crashing suite cannot re-trigger itself either.
mark="$running $(date +%F)"
stamp="$(_cs_state_dir)/.smoke-attempt"
[ -r "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$mark" ] && exit 0
{ mkdir -p "$(_cs_state_dir)" && printf '%s\n' "$mark" >"$stamp"; } 2>/dev/null || exit 0

( bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1 & ) 2>/dev/null
exit 0
