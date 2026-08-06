#!/usr/bin/env bash
# tests/run.sh — self-contained suite. No network, no real ~/.claude, no fixtures
# outside this file. Each case builds a throwaway $HOME and points the kit at it
# via CLAUDE_SESSION_KIT_HOME.
#
# Run: bash tests/run.sh  /  zsh tests/run.sh
# Name the shell — ./tests/run.sh pins it to bash and never exercises zsh, a blind
# spot that has already shipped two bugs.

set -uo pipefail

# Same bash/zsh difference the library guards against. Hard-coding bash here would
# mean the suite could only ever run under bash, which is precisely the blind spot
# that let a zsh bug and a bash-5 bug both ship green.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }
isnt() { [ "$2" != "$3" ] && ok "$1" || bad "$1" "not $2" "$3"; }

# --- fixture helpers --------------------------------------------------------

new_home() {
    FAKE=$(mktemp -d); export CLAUDE_SESSION_KIT_HOME="$FAKE"
    PROJ="$FAKE/.claude/projects/-fake-cwd"; PIDS="$FAKE/.claude/sessions"
    mkdir -p "$PROJ" "$PIDS"
    unset CLAUDE_CODE_SESSION_ID
}
drop_home() { [ -n "${FAKE:-}" ] && rm -rf "$FAKE"; }

# transcript <id> — start an empty transcript
transcript() { : >"$PROJ/$1.jsonl"; printf '%s' "$PROJ/$1.jsonl"; }
add_line()   { printf '%s\n' "$2" >>"$PROJ/$1.jsonl"; }
add_custom() { add_line "$1" "$(jq -cn --arg t "$2" --arg i "$1" '{type:"custom-title",customTitle:$t,sessionId:$i}')"; }
add_ai()     { add_line "$1" "$(jq -cn --arg t "$2" --arg i "$1" '{type:"ai-title",aiTitle:$t,sessionId:$i}')"; }
add_user()   { add_line "$1" "$(jq -cn --arg t "$2" '{type:"user",message:{content:$t}}')"; }

# pidfile <pid> <id> <name> [nameSource]
pidfile() {
    # Match CS_VERIFIED_VERSION so the version guard stays quiet; a mismatch here is
    # noise, and the guard's own behaviour is not what these cases are testing.
    jq -n --arg p "$1" --arg i "$2" --arg n "$3" --arg s "${4:-}" --arg v "$CS_VERIFIED_VERSION" \
        '{pid:($p|tonumber),sessionId:$i,name:$n,version:$v}
         + (if $s=="" then {} else {nameSource:$s} end)' >"$PIDS/$1.json"
}

. "$ROOT/core/sessions.sh"
. "$ROOT/naming/rename.sh"

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

# --- precedence -------------------------------------------------------------

echo "name precedence"

new_home
ID=aaaaaaaa-0000-0000-0000-000000000001; transcript "$ID" >/dev/null
add_user "$ID" "first thing I asked"
add_ai "$ID" "Opening topic"
add_custom "$ID" "The real subject"
# The AI titler re-emits AFTER a rename. A resolver that took the last title line
# would return "Opening topic" and silently discard the user's rename.
add_ai "$ID" "Opening topic"
is "custom-title beats a LATER ai-title" "The real subject" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000002; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
is "falls back to ai-title" "Opening topic" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000003; transcript "$ID" >/dev/null
add_user "$ID" "how do I center a div"
is "falls back to first prompt" "how do I center a div" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000004; transcript "$ID" >/dev/null
is "falls back to short id" "aaaaaaaa" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000005; transcript "$ID" >/dev/null
add_custom "$ID" "From the transcript"
pidfile "$$" "$ID" "Stale explicit name"       # nameSource absent = human-named
# The kit can write custom-title without touching the pid-file, so custom-title is
# the newer value whenever they disagree. Ranking the pid-file first would let a
# stale name shadow a fresh rename that the tab is already showing.
is "custom-title outranks an explicit pid-file name" "From the transcript" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000009; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
pidfile "$$" "$ID" "Explicitly named"
is "explicit pid-file name used when no custom-title" "Explicitly named" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000006; transcript "$ID" >/dev/null
add_custom "$ID" "detector-heuristic-testing"
pidfile "$$" "$ID" "documents-41" derived      # the post-restart state
is "custom-title beats a derived pid-file name" "detector-heuristic-testing" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000007; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
pidfile "$$" "$ID" "documents-41" derived
# "documents-41" is less use than a topic, and derived names collide across sessions.
is "ai-title beats a derived pid-file name" "Opening topic" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000010; transcript "$ID" >/dev/null
pidfile "$$" "$ID" "documents-41" derived
is "derived pid-file name still beats the short id" "documents-41" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000011; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
add_custom "$ID" "A good name"
add_custom "$ID" ""
# Empty custom-title entries occur in real transcripts. Taking the last one
# literally would mask the good name and fall back to the stale auto-title.
is "empty custom-title does not mask an earlier one" "A good name" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000012; transcript "$ID" >/dev/null
add_custom "$ID" "   "
add_custom "$ID" "A good name"
add_custom "$ID" $'   \n  \t '
is "whitespace-only custom-title is treated as empty" "A good name" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000013; transcript "$ID" >/dev/null
# /rename accepts pasted free text verbatim, so multi-line titles exist in real
# transcripts. A line-oriented reader would return the LAST LINE of the paste.
add_custom "$ID" $'Real title here\nsecond line of the paste\nthird line'
is "multi-line custom-title collapses to one line" \
   "Real title here second line of the paste third line" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000014; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
add_custom "$ID" "Set then unset"
add_custom "$ID" ""
add_custom "$ID" ""
is "several empties in a row still fall back to the good name" \
   "Set then unset" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000015; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
add_custom "$ID" ""
is "only-empty custom-titles fall through to ai-title" "Opening topic" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=aaaaaaaa-0000-0000-0000-000000000008; transcript "$ID" >/dev/null
# A user message that happens to quote the marker string must not be read as a title.
add_line "$ID" "$(jq -cn '{type:"user",message:{content:"grep for \"type\":\"custom-title\" in the file"}}')"
add_custom "$ID" "Genuine title"
is "quoted marker in a user message is ignored" "Genuine title" "$(cs_resolve_name "$ID")"
drop_home

# --- liveness ---------------------------------------------------------------

echo "liveness"

new_home
ID=bbbbbbbb-0000-0000-0000-000000000001; transcript "$ID" >/dev/null
pidfile "$$" "$ID" "alive" derived
cs_is_live "$ID" && ok "live process reads as live" || bad "live process reads as live" live dead
drop_home

new_home
ID=bbbbbbbb-0000-0000-0000-000000000002; transcript "$ID" >/dev/null
pidfile 999999 "$ID" "ghost" derived           # pid that cannot be running
cs_is_live "$ID" && bad "stale pid-file reads as dead" dead live || ok "stale pid-file reads as dead"
drop_home

# --- lookup -----------------------------------------------------------------

echo "lookup"

new_home
A=cccccccc-0000-0000-0000-000000000001; transcript "$A" >/dev/null; add_custom "$A" "documents-7c"
B=dddddddd-0000-0000-0000-000000000002; transcript "$B" >/dev/null; add_custom "$B" "documents-7c"
is "colliding names return both ids" 2 "$(cs_find documents-7c | wc -l | tr -d ' ')"
is "short-id prefix finds one" 1 "$(cs_find cccccccc | wc -l | tr -d ' ')"
is "name substring is case-insensitive" 2 "$(cs_find DOCUMENTS-7C | wc -l | tr -d ' ')"
drop_home

# --- title validation -------------------------------------------------------

echo "title validation"

rename_check_title "" 2>/dev/null && bad "rejects empty title" reject accept || ok "rejects empty title"
rename_check_title "two
lines" 2>/dev/null && bad "rejects multi-line title" reject accept || ok "rejects multi-line title"
rename_check_title "$(printf 'x%.0s' $(seq 1 201))" 2>/dev/null \
    && bad "rejects over-long title" reject accept || ok "rejects over-long title"
rename_check_title "A normal: sentence-style title" 2>/dev/null \
    && ok "accepts a sentence-style title" || bad "accepts a sentence-style title" accept reject

# --- applying ---------------------------------------------------------------

echo "applying"

new_home
ID=eeeeeeee-0000-0000-0000-000000000001; transcript "$ID" >/dev/null
add_ai "$ID" "Opening topic"
export CLAUDE_CODE_SESSION_ID="$ID"
rename_apply "Applied by the kit" 2>/dev/null
is "rename_apply sets the name" "Applied by the kit" "$(cs_resolve_name "$ID")"
is "rename_apply appends, keeps history" 1 "$(grep -c '"type":"ai-title"' "$PROJ/$ID.jsonl")"
unset CLAUDE_CODE_SESSION_ID
drop_home

new_home
ID=eeeeeeee-0000-0000-0000-000000000002; transcript "$ID" >/dev/null
OTHER=ffffffff-0000-0000-0000-000000000002; transcript "$OTHER" >/dev/null
add_ai "$OTHER" "Some other session"
export CLAUDE_CODE_SESSION_ID="$ID"
# Scoped to the current session by construction: there is no parameter that could
# aim this at $OTHER. Widening it belongs with handoff import — see the decision
# record in docs/DESIGN-naming.md.
rename_apply "Only the current one" 2>/dev/null
is "renames the current session" "Only the current one" "$(cs_resolve_name "$ID")"
is "leaves every other session alone" "Some other session" "$(cs_resolve_name "$OTHER")"
unset CLAUDE_CODE_SESSION_ID
drop_home

new_home
ID=eeeeeeee-0000-0000-0000-000000000007; transcript "$ID" >/dev/null
unset CLAUDE_CODE_SESSION_ID
rename_apply "Nowhere to write this" 2>/dev/null
is "refuses when there is no current session" 1 "$?"
drop_home

new_home
ID=eeeeeeee-0000-0000-0000-000000000003; transcript "$ID" >/dev/null
export CLAUDE_CODE_SESSION_ID="$ID"
rename_apply "First name" 2>/dev/null
PREV=$(rename_current_title)
rename_apply "Second name" 2>/dev/null
is "latest title wins" "Second name" "$(cs_resolve_name "$ID")"
rename_apply "$PREV" 2>/dev/null
is "undo restores by appending" "First name" "$(cs_resolve_name "$ID")"
is "undo did not rewrite the file" 3 "$(grep -c '"type":"custom-title"' "$PROJ/$ID.jsonl")"
unset CLAUDE_CODE_SESSION_ID
drop_home

new_home
ID=eeeeeeee-0000-0000-0000-000000000004; transcript "$ID" >/dev/null
export CLAUDE_CODE_SESSION_ID="$ID"
rename_apply 'Quotes " and \ backslashes and : colons' 2>/dev/null
is "escapes correctly" 'Quotes " and \ backslashes and : colons' "$(cs_resolve_name "$ID")"
is "stays valid JSONL" 1 "$(jq -s 'length' "$PROJ/$ID.jsonl")"
unset CLAUDE_CODE_SESSION_ID
drop_home

new_home
export CLAUDE_CODE_SESSION_ID=eeeeeeee-0000-0000-0000-000000000005
rename_apply "No transcript exists" 2>/dev/null
is "refuses a session with no transcript" 1 "$?"
unset CLAUDE_CODE_SESSION_ID
drop_home

# --- sourcing from other shells ---------------------------------------------
# rename.sh locates core/ relative to itself. BASH_SOURCE is bash-only, so a
# naive lookup breaks the moment someone sources it from an interactive zsh.

echo "portability"

if command -v zsh >/dev/null 2>&1; then
    if zsh -c ". '$ROOT/naming/rename.sh' && rename_command x >/dev/null" 2>/dev/null; then
        ok "sources cleanly under zsh"
    else
        bad "sources cleanly under zsh" "sourced" "failed to find core/sessions.sh"
    fi
else
    ok "sources cleanly under zsh (skipped, no zsh)"
fi

# The override is what a caller uses when its shell cannot report the sourced path.
if bash -c "CLAUDE_SESSION_KIT_ROOT='$ROOT' . '$ROOT/naming/rename.sh' && rename_command x >/dev/null" 2>/dev/null; then
    ok "CLAUDE_SESSION_KIT_ROOT overrides self-location"
else
    bad "CLAUDE_SESSION_KIT_ROOT overrides self-location" "sourced" "failed"
fi

# A shell that resolves the path wrongly must say so, not fail obscurely later.
# This is the shape the zsh bug took: it parsed fine and pointed somewhere absurd.
OUT=$(bash -c "CLAUDE_SESSION_KIT_ROOT=/nonexistent . '$ROOT/naming/rename.sh'" 2>&1)
case "$OUT" in
    *CLAUDE_SESSION_KIT_ROOT*) ok "a bad root fails loudly and names the fix" ;;
    *) bad "a bad root fails loudly and names the fix" "actionable error" "${OUT:-silence}" ;;
esac

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
