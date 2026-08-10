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
. "$ROOT/notes/note.sh"

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

# Real messages also store content as an ARRAY of blocks, not a plain string.
new_home
ID=aaaaaaaa-0000-0000-0000-000000000016; transcript "$ID" >/dev/null
add_line "$ID" "$(jq -cn '{type:"user",message:{content:[{type:"text",text:"block-form prompt"}]}}')"
is "array-form message content resolves too" "block-form prompt" "$(cs_resolve_name "$ID")"
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

# --- version tracking -------------------------------------------------------
#
# The guard compares against what smoke.sh last PASSED against on this machine, not
# the constant in the source. Otherwise every update warns forever, including ones
# already checked, and a warning that never clears stops being read.

echo "version tracking"

new_home
is "falls back to the author's version with no state file" \
   "$CS_VERIFIED_VERSION" "$(cs_verified_version)"

mkdir -p "$FAKE/.claude/session-kit"
echo "9.9.9" >"$FAKE/.claude/session-kit/.verified"
is "a recorded version overrides the author's" "9.9.9" "$(cs_verified_version)"

printf '  2.5.0 \n' >"$FAKE/.claude/session-kit/.verified"
is "surrounding whitespace is ignored" "2.5.0" "$(cs_verified_version)"

: >"$FAKE/.claude/session-kit/.verified"
is "an empty state file falls back, never resolves empty" \
   "$CS_VERIFIED_VERSION" "$(cs_verified_version)"
drop_home

# The guard must stay quiet once the running version has been verified here, and
# speak up again the moment it moves.
new_home
mkdir -p "$FAKE/.claude/session-kit"
echo "9.9.9" >"$FAKE/.claude/session-kit/.verified"
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.9"}' >"$PIDS/1.json"
OUT=$(unset _CS_VERSION_WARNED; cs_version_guard 2>&1)
is "silent when running matches the recorded version" "" "$OUT"

jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.10"}' >"$PIDS/1.json"
OUT=$(unset _CS_VERSION_WARNED; cs_version_guard 2>&1)
case "$OUT" in
    *9.9.10*9.9.9*smoke.sh*) ok "warns on a new version and names smoke.sh" ;;
    *) bad "warns on a new version and names smoke.sh" "both versions + smoke.sh" "${OUT:-silence}" ;;
esac
drop_home

# Several sessions can run at once on different versions mid-upgrade; the guard
# compares against the HIGHEST, and 2.1.10 must sort above 2.1.9 (version sort,
# not string sort — string sort would call 2.1.9 the newer one).
new_home
jq -n '{pid:1,sessionId:"a",name:"n",version:"2.1.9"}'  >"$PIDS/1.json"
jq -n '{pid:2,sessionId:"b",name:"n",version:"2.1.10"}' >"$PIDS/2.json"
is "the running version is the highest, version-sorted" "2.1.10" "$(cs_running_version)"
drop_home

# --- failure reporting ------------------------------------------------------
#
# The report is built to be pasted into an issue on a repo that will be public, so
# these cases are about what must NOT be in it. A malformed JSONL line is the
# cheapest way to force a real failure without faking one.

echo "failure reporting"

SECRET="Acme Corp migration for client Contoso"

new_home
ID=77777777-0000-0000-0000-000000000001; transcript "$ID" >/dev/null
add_custom "$ID" "$SECRET"
printf 'this is not json\n' >>"$PROJ/$ID.jsonl"
jq -n --arg v "$CS_VERIFIED_VERSION" '{pid:1,sessionId:"z",name:"n",version:$v}' >"$PIDS/1.json"

OUT=$(bash "$ROOT/tests/smoke.sh" 2>&1); RC=$?
REPORT="$FAKE/.claude/session-kit/last-failure.md"

is  "a malformed line makes smoke.sh fail"  1 "$RC"
[ -f "$REPORT" ] && ok "a failure writes a report" || bad "a failure writes a report" "file" "missing"

grep -Fq "$SECRET" "$REPORT" 2>/dev/null \
    && bad "the report leaks no session title" "absent" "PRESENT" \
    || ok "the report leaks no session title"

grep -Fq "$HOME" "$REPORT" 2>/dev/null \
    && bad "the report leaks no home path" "absent" "PRESENT" \
    || ok "the report leaks no home path"

grep -Fq "$(id -un)" "$REPORT" 2>/dev/null \
    && bad "the report leaks no username" "absent" "PRESENT" \
    || ok "the report leaks no username"

grep -q "every transcript parses as JSONL" "$REPORT" 2>/dev/null \
    && ok "the report names the failed check" \
    || bad "the report names the failed check" "check name" "absent"

grep -q "claude code running" "$REPORT" 2>/dev/null \
    && ok "the report records the environment" \
    || bad "the report records the environment" "version fields" "absent"

is "--report prints the recorded failure" 0 \
   "$(bash "$ROOT/tests/smoke.sh" --report >/dev/null 2>&1; echo $?)"
bash "$ROOT/tests/smoke.sh" --report 2>/dev/null | grep -q 'smoke failure' \
    && ok "--report emits the report body" \
    || bad "--report emits the report body" "body" "nothing"

# A failing run must not record the version as verified, or the warning would
# clear while the kit is still broken.
[ -f "$FAKE/.claude/session-kit/.verified" ] \
    && bad "a failing run records no verified version" "absent" "PRESENT" \
    || ok "a failing run records no verified version"
drop_home

# A later passing run must clear the stale report.
new_home
ID=77777777-0000-0000-0000-000000000002; transcript "$ID" >/dev/null
add_ai "$ID" "Perfectly fine"
jq -n --arg v "$CS_VERIFIED_VERSION" '{pid:1,sessionId:"z",name:"n",version:$v}' >"$PIDS/1.json"
mkdir -p "$FAKE/.claude/session-kit"
echo "stale" >"$FAKE/.claude/session-kit/last-failure.md"
bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1
[ -f "$FAKE/.claude/session-kit/last-failure.md" ] \
    && bad "a passing run clears a stale report" "removed" "still there" \
    || ok "a passing run clears a stale report"
is "a passing run records the verified version" \
   "$CS_VERIFIED_VERSION" "$(cat "$FAKE/.claude/session-kit/.verified" 2>/dev/null)"
drop_home

# --- hostile and degenerate input -------------------------------------------
#
# Titles are free text a user pastes, and ids reach `find -name`, so both are
# untrusted. Two of these were live bugs when the cases were written.

echo "hostile input"

# A whitespace-only title passes an emptiness check but resolves to nothing, so the
# rename would report success and change no name.
rename_check_title "   " 2>/dev/null \
    && bad "rejects a whitespace-only title" reject accept || ok "rejects a whitespace-only title"
rename_check_title "$(printf '\t \t')" 2>/dev/null \
    && bad "rejects a tabs-only title" reject accept || ok "rejects a tabs-only title"

# The cap protects append atomicity, which is a byte property. ${#t} counts characters
# or bytes depending on locale, so measuring it that way makes the limit machine-dependent.
rename_check_title "$(printf 'x%.0s' $(seq 1 200))" 2>/dev/null \
    && ok "accepts exactly $RENAME_MAX_TITLE bytes" || bad "accepts exactly $RENAME_MAX_TITLE bytes" accept reject
rename_check_title "$(printf 'x%.0s' $(seq 1 201))" 2>/dev/null \
    && bad "rejects one byte over" reject accept || ok "rejects one byte over"
# 150 two-byte characters = 300 bytes: over the limit however the locale counts.
rename_check_title "$(printf 'é%.0s' $(seq 1 150))" 2>/dev/null \
    && bad "measures multibyte titles in bytes" reject accept || ok "measures multibyte titles in bytes"

new_home
ID=11111111-0000-0000-0000-00000000000a; transcript "$ID" >/dev/null
# find treats -name as a pattern, so an unfiltered id could match a transcript nobody
# asked for and report it as that session.
is "a glob metacharacter never resolves to a transcript" 1 \
   "$(cs_transcript_path '*'   >/dev/null 2>&1; echo $?)"
is "a bracket expression never resolves either" 1 \
   "$(cs_transcript_path '[a]' >/dev/null 2>&1; echo $?)"
add_custom "$ID" "a real title"
is "cs_find does not invent a session from a glob" "" "$(cs_find '*')"

# cs_list is TSV, and cs_find reads it back with IFS=tab. A tab inside a title would
# split one row into the wrong fields; whitespace collapse is what prevents it.
add_custom "$ID" "$(printf 'before\tafter')"
is "a tab in a title cannot break the TSV" "before after" "$(cs_resolve_name "$ID")"
is "and the row still parses back" "$ID" "$(cs_find after)"

# printf format specifiers must survive as literal text, never be interpreted.
add_custom "$ID" '100% done %s %d %n'
is "printf specifiers in a title stay literal" '100% done %s %d %n' "$(cs_resolve_name "$ID")"
drop_home

echo "degenerate data"

new_home
ID=22222222-0000-0000-0000-00000000000b; transcript "$ID" >/dev/null
is "an empty transcript falls back to the short id" "22222222" "$(cs_resolve_name "$ID")"
printf '\n\n   \n' >"$PROJ/$ID.jsonl"
is "a blank-line transcript falls back too" "22222222" "$(cs_resolve_name "$ID")"
printf '{"type":"ai-title","aiTitle":"CRLF title"}\r\n' >"$PROJ/$ID.jsonl"
is "CRLF line endings still parse" "CRLF title" "$(cs_resolve_name "$ID")"
drop_home

new_home
ID=33333333-0000-0000-0000-00000000000c; transcript "$ID" >/dev/null
add_ai "$ID" "Good name"
printf 'not json at all\n' >"$PIDS/1.json"          # malformed
printf '{}\n'              >"$PIDS/2.json"          # valid JSON, no fields
is "a malformed pid-file does not break resolution" "Good name" "$(cs_resolve_name "$ID")"
cs_is_live "$ID" && bad "a malformed pid-file never reads as live" dead live \
                 || ok "a malformed pid-file never reads as live"
is "an unreadable version reads as empty, not garbage" "" "$(cs_running_version)"
drop_home

echo "contracts"

new_home
is "cs_transcript_path refuses an empty id"  1 "$(cs_transcript_path '' >/dev/null 2>&1; echo $?)"
is "cs_find refuses an empty ref"            1 "$(cs_find ''            >/dev/null 2>&1; echo $?)"
is "cs_resolve_name refuses an empty id"     1 "$(cs_resolve_name ''    >/dev/null 2>&1; echo $?)"
is "cs_is_live is false for an unknown id"   1 "$(cs_is_live nope       >/dev/null 2>&1; echo $?)"
unset CLAUDE_CODE_SESSION_ID
is "rename_current_title refuses with no session" 1 \
   "$(rename_current_title >/dev/null 2>&1; echo $?)"
drop_home

echo "the SessionStart hook"

# The hook runs unattended on every session start. Every failure path must exit 0:
# breaking session start is far worse than skipping a check.
new_home
is "hook exits 0 when the kit root is wrong" 0 \
   "$(CLAUDE_SESSION_KIT_ROOT=/nonexistent bash "$ROOT/hooks/version-check.sh" >/dev/null 2>&1; echo $?)"
is "hook exits 0 when no pid-file exists" 0 \
   "$(CLAUDE_SESSION_KIT_ROOT="$ROOT" bash "$ROOT/hooks/version-check.sh" >/dev/null 2>&1; echo $?)"
is "hook prints nothing on the quiet path" "" \
   "$(CLAUDE_SESSION_KIT_ROOT="$ROOT" bash "$ROOT/hooks/version-check.sh" 2>&1)"

# Matching version: must not launch the suite.
mkdir -p "$FAKE/.claude/session-kit"
echo "7.7.7" >"$FAKE/.claude/session-kit/.verified"
jq -n '{pid:1,sessionId:"z",name:"n",version:"7.7.7"}' >"$PIDS/1.json"
CLAUDE_SESSION_KIT_ROOT="$ROOT" bash "$ROOT/hooks/version-check.sh" >/dev/null 2>&1
is "hook exits 0 when the version is already verified" 0 $?
drop_home

# The attempt throttle (design borrowed back from claude-memory-kit): a mismatch
# launches the suite ONCE per version per day, not on every session start — a
# persistently failing suite gives the same answer however often it is re-asked.
# A stub kit root with a counting smoke.sh makes the launches observable.
new_home
mkdir -p "$FAKE/kit/core" "$FAKE/kit/tests" "$FAKE/kit/hooks"
cp "$ROOT/core/sessions.sh" "$FAKE/kit/core/sessions.sh"
printf '#!/bin/bash\necho x >>"%s/kit/.count"\n' "$FAKE" >"$FAKE/kit/tests/smoke.sh"
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.9"}' >"$PIDS/1.json"
CLAUDE_SESSION_KIT_ROOT="$FAKE/kit" bash "$ROOT/hooks/version-check.sh"
CLAUDE_SESSION_KIT_ROOT="$FAKE/kit" bash "$ROOT/hooks/version-check.sh"
CLAUDE_SESSION_KIT_ROOT="$FAKE/kit" bash "$ROOT/hooks/version-check.sh"
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$FAKE/kit/.count" ] && break; sleep 0.3; done
is "three session starts on one bad version launch the suite once" 1 \
   "$(grep -c x "$FAKE/kit/.count" 2>/dev/null)"
is "…and the attempt is stamped" "9.9.9 $(date +%F)" \
   "$(cat "$FAKE/.claude/session-kit/.smoke-attempt" 2>/dev/null)"
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.10"}' >"$PIDS/1.json"
CLAUDE_SESSION_KIT_ROOT="$FAKE/kit" bash "$ROOT/hooks/version-check.sh"
for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(grep -c x "$FAKE/kit/.count" 2>/dev/null)" = "2" ] && break; sleep 0.3; done
is "a NEW version bypasses the day throttle" 2 "$(grep -c x "$FAKE/kit/.count" 2>/dev/null)"
drop_home

# --- the commit guardrail ------------------------------------------------------
#
# Leak fixtures are built by string concatenation so THIS file never contains a
# literal home path or email — once the guardrail is wired, it scans every commit
# to this repo, including commits that edit this very suite.

echo "the commit guardrail"

# (No committer identity configured: the scratch repo only ever stages, and the
# guardrail itself blocked an email-shaped config value here when it was inline.)
GR=$(mktemp -d)
git -C "$GR" init -q

printf 'a clean line, ~ instead of a real path\n' >"$GR/ok.md"
git -C "$GR" add ok.md
is "clean staged content passes" 0 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"

leak_path="/Use""rs/janedoe/secret-project"
printf 'data at %s today\n' "$leak_path" >"$GR/leak.md"
git -C "$GR" add leak.md
is "a staged home path is blocked" 1 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached leak.md

leak_mail="someone@""example.com"
printf 'contact: %s\n' "$leak_mail" >"$GR/mail.md"
git -C "$GR" add mail.md
is "a staged email is blocked" 1 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached mail.md

printf 'remote: git@github.com:someone/repo.git\n' >"$GR/rem.md"
git -C "$GR" add rem.md
is "an SSH remote URL is not treated as an email" 0 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached rem.md

printf 'the contoso engagement notes\n' >"$GR/dl.md"
git -C "$GR" add dl.md
is "a denylisted term via env is blocked" 1 \
   "$(cd "$GR" && CLAUDE_CONFIG_DENYLIST=contoso bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached dl.md

# The style rule scopes to reader-facing docs only (README.md, docs/*.md), so this
# suite may hold the literal em-dash safely — run.sh is never inside that scope.
mkdir -p "$GR/docs"
printf 'a clause — set off wrong\n' >"$GR/docs/style.md"
git -C "$GR" add docs/style.md
is "an em-dash staged in docs/*.md is blocked" 1 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached docs/style.md

printf 'a clause — set off wrong\n' >"$GR/README.md"
git -C "$GR" add README.md
is "an em-dash staged in README.md is blocked" 1 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached README.md

printf 'a scratch note — em-dash allowed here\n' >"$GR/scratch.md"
git -C "$GR" add scratch.md
is "an em-dash outside README/docs passes (scope is the path, not the extension)" 0 \
   "$(cd "$GR" && bash "$ROOT/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
rm -rf "$GR"

# --- session notes -----------------------------------------------------------
#
# Storage is trivial; the tests aim at the feature's two real risks — a note
# surfacing into the wrong session (or on every prompt), and prose corrupting on
# the way through. Body chosen to be hostile: quotes, backslash, printf specifiers,
# emoji, blank lines.

echo "session notes"

HOSTILE_NOTE='## Decided
- use "custom-title", not a sidecar (path: C:\temp\x)
- 100% done %s %d 🪨

## Next
- export first'

new_home
ID=44444444-0000-0000-0000-00000000000d; transcript "$ID" >/dev/null
add_ai "$ID" "Some session"
export CLAUDE_CODE_SESSION_ID="$ID"
printf '%s\n' "$HOSTILE_NOTE" | note_write
is "hostile prose round-trips byte-identical" "$HOSTILE_NOTE" "$(note_read "$ID")"
printf 'replaced\n' | note_write
is "writing replaces, never appends" "replaced" "$(note_read "$ID")"
printf '   \n\t\n' | note_write 2>/dev/null
is "a whitespace-only body is refused" 1 "$?"
is "…and the previous note survives the refusal" "replaced" "$(note_read "$ID")"
unset CLAUDE_CODE_SESSION_ID
printf 'orphan\n' | note_write 2>/dev/null
is "note_write refuses with no current session" 1 "$?"
is "note_read refuses a traversal id" 1 "$(note_read '../../etc/passwd' >/dev/null 2>&1; echo $?)"
drop_home

new_home
ID=44444444-0000-0000-0000-00000000000e; transcript "$ID" >/dev/null
add_ai "$ID" "T"
export CLAUDE_CODE_SESSION_ID="$ID"
printf 'the note\n' | note_write
is "a fresh note has age 0" 0 "$(note_age "$ID")"
add_user "$ID" "one"; add_user "$ID" "two"; add_user "$ID" "three"
is "age counts entries added since the write" 3 "$(note_age "$ID")"
case "$(note_render "$ID")" in *"3 transcript entries ago"*) ok "render carries the age" ;;
    *) bad "render carries the age" "mentions 3 entries" "$(note_render "$ID" | head -1)";; esac
rm "$PROJ/$ID.jsonl"
is "age is unknown when the transcript is gone" "?" "$(note_age "$ID")"
case "$(note_render "$ID")" in *"age unknown"*) ok "render admits unknown age instead of guessing" ;;
    *) bad "render admits unknown age instead of guessing" "age unknown" "$(note_render "$ID" | head -1)";; esac
unset CLAUDE_CODE_SESSION_ID
drop_home

# Coexistence: the notes directory is shared real estate under ~/.claude, so the kit
# must survive whatever else turns up there — a blocking file, foreign files, notes
# edited by hand.

new_home
ID=44444444-0000-0000-0000-000000000010; transcript "$ID" >/dev/null
add_ai "$ID" "T"
export CLAUDE_CODE_SESSION_ID="$ID"
printf 'blocked' >"$FAKE/.claude/session-notes"        # a FILE where the dir should be
printf 'body\n' | note_write 2>/dev/null
is "a file blocking the notes dir fails the write loudly" 1 "$?"
is "…and the hook stays silent instead of erroring" "" \
   "$(printf '{"session_id":"%s"}' "$ID" | bash "$ROOT/hooks/session-note.sh")"
rm -f "$FAKE/.claude/session-notes"

mkdir -p "$FAKE/.claude/session-notes"
printf 'not ours\n' >"$FAKE/.claude/session-notes/somebody-elses.md"
printf 'our body\n' | note_write
is "foreign files in the notes dir are never touched" "not ours" \
   "$(cat "$FAKE/.claude/session-notes/somebody-elses.md")"
is "…and our note still works beside them" "our body" "$(note_read "$ID")"

printf 'no header, just prose\n' >"$FAKE/.claude/session-notes/$ID.md"
is "a hand-edited note keeps its whole body" "no header, just prose" "$(note_read "$ID")"
is "…and reports its age as unknown, not a guess" "?" "$(note_age "$ID")"
unset CLAUDE_CODE_SESSION_ID
drop_home

# The hook. Once per opened session, never into the session that wrote it, silent on
# every failure path.

echo "the session-note hook"

hook_note() { printf '{"session_id":"%s"}' "$1" | bash "$ROOT/hooks/session-note.sh"; }

new_home
ID=55555555-0000-0000-0000-00000000000f; transcript "$ID" >/dev/null
add_ai "$ID" "T"
pidfile "$$" "$ID" "n"
export CLAUDE_CODE_SESSION_ID="$ID"
printf '%s\n' "$HOSTILE_NOTE" | note_write     # stamps .seen with this live process
unset CLAUDE_CODE_SESSION_ID

is "the writing process never gets its own note echoed" "" "$(hook_note "$ID")"

# A restart: the same session now runs under a different (live) process.
sleep 30 & NEWPID=$!
rm -f "$PIDS/$$.json"; pidfile "$NEWPID" "$ID" "n"
OUT=$(hook_note "$ID"); RC=$?
case "$OUT" in *'use "custom-title"'*'🪨'*) ok "a reopened session receives the note verbatim" ;;
    *) bad "a reopened session receives the note verbatim" "the hostile body" "${OUT:-nothing}";; esac
is "…with exit 0" 0 "$RC"
case "$OUT" in *"transcript entries ago"*) ok "…stamped with its age" ;;
    *) bad "…stamped with its age" "an age line" "$(printf '%s' "$OUT" | head -1)";; esac
is "…and only once — the next prompt is silent" "" "$(hook_note "$ID")"
{ kill "$NEWPID" && wait "$NEWPID"; } 2>/dev/null

# A dead registration must not surface the note (cannot attribute it to a process).
rm -f "$PIDS"/*.json; pidfile 999999 "$ID" "n"; rm -f "$FAKE/.claude/session-notes/$ID.seen"
is "no live process, no note" "" "$(hook_note "$ID")"

OUT=$(printf 'not json' | bash "$ROOT/hooks/session-note.sh"); RC=$?
is "garbage stdin prints nothing" "" "$OUT"
is "…and exits 0" 0 "$RC"
is "a session with no note is silent" "" "$(hook_note 99999999-0000-0000-0000-000000000001)"
is "a traversal session_id is silent" "" "$(printf '{"session_id":"../../evil"}' | bash "$ROOT/hooks/session-note.sh")"
drop_home

# --- handoff export / import -------------------------------------------------
#
# The round-trip is the oracle: export from home A, import into home B, and compare
# against the ORIGINAL files — so the test never depends on a belief about what should
# have been copied. Atomicity is the other target: a refused import must leave the
# target machine byte-for-byte untouched.

echo "handoff export/import"

HA=$(mktemp -d); HB=$(mktemp -d); CWDB=$(mktemp -d); OUT=$(mktemp -d)
PROJA="$HA/.claude/projects/-src-cwd"; mkdir -p "$PROJA" "$HA/.claude/sessions"
S1=aaaa9999-0000-0000-0000-000000000001
S2=bbbb9999-0000-0000-0000-000000000002
{ jq -cn --arg id "$S1" '{type:"user",cwd:"/src/cwd",timestamp:"2026-08-01T00:00:00Z",sessionId:$id,message:{content:"work on the parser"}}'
  jq -cn --arg id "$S1" --arg t 'Parser: quote "handling" 🪨 100%' '{type:"custom-title",customTitle:$t,sessionId:$id}'
} >"$PROJA/$S1.jsonl"
{ jq -cn --arg id "$S2" '{type:"user",cwd:"/src/cwd",timestamp:"2026-08-02T09:00:00Z",sessionId:$id,message:{content:"second thing"}}'
  jq -cn --arg id "$S2" '{type:"ai-title",aiTitle:"Second parser session",sessionId:$id}'
} >"$PROJA/$S2.jsonl"
printf 'diff --git a/x b/x\n' >"$OUT/held.diff"
printf '# HANDOFF\nreal note content\n' >"$OUT/note.md"

BOUT=$(CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" \
        -o "$OUT" -n "$OUT/note.md" "$S1" "$S2" -- "$OUT/held.diff" 2>/dev/null)
BUNDLE=$(printf '%s\n' "$BOUT" | sed -n 's/^bundle: //p')
[ -f "$BUNDLE" ] && ok "export produces a bundle" || bad "export produces a bundle" "a tar.gz" "${BUNDLE:-nothing}"

# "parser" matches BOTH titles — this must exercise the ambiguity branch, not the
# unknown-ref branch, so the assertion checks the message too.
AMB=$(CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" parser 2>&1 >/dev/null); RC=$?
is "an ambiguous ref is refused" 1 "$RC"
case "$AMB" in *ambiguous*) ok "…via the ambiguity branch, listing candidates" ;;
    *) bad "…via the ambiguity branch, listing candidates" "'ambiguous' in the error" "$AMB";; esac
is "unknown refs are refused" 1 \
   "$(CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" no-such-session >/dev/null 2>&1; echo $?)"

printf 'this line is not json\n' >>"$PROJA/$S2.jsonl"
is "a corrupt transcript refuses to export" 1 \
   "$(CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" "$S2" >/dev/null 2>&1; echo $?)"
# restore S2 for the rest of the section
head -2 "$PROJA/$S2.jsonl" >"$PROJA/$S2.tmp" && mv "$PROJA/$S2.tmp" "$PROJA/$S2.jsonl"

IOUT=$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB" bash "$ROOT/handoff/import.sh" "$BUNDLE" 2>/dev/null)
DESTB="$HB/.claude/projects/$(printf '%s' "$CWDB" | tr '/' '-')"
[ -f "$DESTB/$S1.jsonl" ] && ok "import installs into the target project dir" \
    || bad "import installs into the target project dir" "$DESTB/$S1.jsonl" "missing"

# The oracle: the installed file must BE the original, plus exactly the title line.
n1=$(wc -l <"$PROJA/$S1.jsonl" | tr -d ' ')
head -n "$n1" "$DESTB/$S1.jsonl" | cmp -s - "$PROJA/$S1.jsonl" \
    && ok "installed transcript is byte-identical to the source" \
    || bad "installed transcript is byte-identical to the source" "identical prefix" "diverged"
is "the manifest title survives as the resolved name" \
   'Parser: quote "handling" 🪨 100%' \
   "$(CLAUDE_SESSION_KIT_HOME="$HB" bash -c '. "'"$ROOT"'/core/sessions.sh"; cs_resolve_name '"$S1"'')"
case "$IOUT" in *"real note content"*) ok "the note is printed on import" ;;
    *) bad "the note is printed on import" "note text" "absent";; esac
case "$IOUT" in *"loose files kept at:"*) ok "loose files are surfaced, not scattered" ;;
    *) bad "loose files are surfaced, not scattered" "a kept path" "absent";; esac

# Idempotency: importing the same bundle again must be a clean no-op.
sha_before=$(cksum "$DESTB/$S1.jsonl")
IOUT2=$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB" bash "$ROOT/handoff/import.sh" "$BUNDLE" 2>/dev/null); RC=$?
is "re-importing the same bundle succeeds" 0 "$RC"
case "$IOUT2" in *skipped*) ok "…and reports the sessions as skipped" ;;
    *) bad "…and reports the sessions as skipped" "a skip line" "$IOUT2";; esac
is "…and modifies nothing" "$sha_before" "$(cksum "$DESTB/$S1.jsonl")"

# Exporting a LIVE session is allowed but must say the bundle is a snapshot.
# (This section builds its homes by hand, so write the pid-file into HA directly —
# the pidfile helper writes into new_home's dirs, which are not in play here.)
jq -n --arg p "$$" --arg i "$S1" --arg v "$CS_VERIFIED_VERSION" \
    '{pid:($p|tonumber),sessionId:$i,name:"n",version:$v}' >"$HA/.claude/sessions/$$.json"
LOUT=$(CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" "$S1" 2>&1 >/dev/null); RC=$?
is "a live session still exports" 0 "$RC"
case "$LOUT" in *live*snapshot*) ok "…with a snapshot warning" ;;
    *) bad "…with a snapshot warning" "'live … snapshot' on stderr" "${LOUT:-silence}";; esac
rm -f "$HA/.claude/sessions/$$.json"

# Two exports in the same second must produce two bundles, not one overwriting the
# other — this exact collision silently swapped the bundle under later tests once.
before=$(ls "$OUT"/session-handoff-*.tar.gz | wc -l | tr -d ' ')
CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" "$S1" >/dev/null 2>&1
CLAUDE_SESSION_KIT_HOME="$HA" bash "$ROOT/handoff/export.sh" -o "$OUT" "$S1" >/dev/null 2>&1
is "back-to-back exports never overwrite each other" "$((before+2))" \
   "$(ls "$OUT"/session-handoff-*.tar.gz | wc -l | tr -d ' ')"

# Garbage inputs to import: each refuses cleanly, before any write.
printf 'not a tarball' >"$OUT/garbage.tar.gz"
is "import refuses a file that is not a tar.gz" 1 \
   "$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB" bash "$ROOT/handoff/import.sh" "$OUT/garbage.tar.gz" >/dev/null 2>&1; echo $?)"
NODIR=$(mktemp -d); printf 'x\n' >"$NODIR/loose.txt"
( cd "$NODIR" && tar -czf "$OUT/nomanifest.tar.gz" . )
is "import refuses a bundle with no manifest" 1 \
   "$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB" bash "$ROOT/handoff/import.sh" "$OUT/nomanifest.tar.gz" >/dev/null 2>&1; echo $?)"
TDIRF=$(mktemp -d); tar -xzf "$BUNDLE" -C "$TDIRF"
jq '.format = 2' "$TDIRF/manifest.json" >"$TDIRF/m.tmp" && mv "$TDIRF/m.tmp" "$TDIRF/manifest.json"
( cd "$TDIRF" && tar -czf "$OUT/format2.tar.gz" . )
is "import refuses a manifest format it does not read" 1 \
   "$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB" bash "$ROOT/handoff/import.sh" "$OUT/format2.tar.gz" >/dev/null 2>&1; echo $?)"
rm -rf "$NODIR" "$TDIRF"

# Tamper with a bundled transcript: checksum must catch it, and nothing may install.
HB2=$(mktemp -d); TDIR=$(mktemp -d)
tar -xzf "$BUNDLE" -C "$TDIR"
printf '%s\n' '{"type":"user","message":{"content":"injected"}}' >>"$TDIR/sessions/$S1.jsonl"
( cd "$TDIR" && tar -czf "$OUT/tampered.tar.gz" . )
is "a tampered bundle is refused" 1 \
   "$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB2" bash "$ROOT/handoff/import.sh" "$OUT/tampered.tar.gz" >/dev/null 2>&1; echo $?)"
[ ! -e "$HB2/.claude/projects" ] || [ -z "$(find "$HB2/.claude/projects" -name '*.jsonl' 2>/dev/null)" ] \
    && ok "…and installs nothing" || bad "…and installs nothing" "no transcripts" "something installed"

# Divergent collision: refuse the WHOLE bundle, even the sessions that were fine.
HB3=$(mktemp -d); DEST3="$HB3/.claude/projects/$(printf '%s' "$CWDB" | tr '/' '-')"
mkdir -p "$DEST3"
printf '%s\n' '{"type":"user","message":{"content":"a different history"}}' >"$DEST3/$S2.jsonl"
is "a diverged session refuses the import" 1 \
   "$(cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB3" bash "$ROOT/handoff/import.sh" "$BUNDLE" >/dev/null 2>&1; echo $?)"
[ ! -e "$DEST3/$S1.jsonl" ] && ok "…and the healthy session was not installed either" \
    || bad "…and the healthy session was not installed either" "atomic refusal" "partial install"

# A hand-made manifest with a multi-line title: import must normalise it.
HB4=$(mktemp -d); TDIR2=$(mktemp -d)
tar -xzf "$BUNDLE" -C "$TDIR2"
jq --arg id "$S1" '(.sessions[] | select(.id==$id) | .title) |= "line one\nline two"' \
    "$TDIR2/manifest.json" >"$TDIR2/m.tmp" && mv "$TDIR2/m.tmp" "$TDIR2/manifest.json"
( cd "$TDIR2" && tar -czf "$OUT/multiline.tar.gz" . )
( cd "$CWDB" && CLAUDE_SESSION_KIT_HOME="$HB4" bash "$ROOT/handoff/import.sh" "$OUT/multiline.tar.gz" >/dev/null 2>&1 )
is "a multi-line manifest title is normalised on import" "line one line two" \
   "$(CLAUDE_SESSION_KIT_HOME="$HB4" bash -c '. "'"$ROOT"'/core/sessions.sh"; cs_resolve_name '"$S1"'')"

rm -rf "$HA" "$HB" "$HB2" "$HB3" "$HB4" "$CWDB" "$OUT" "$TDIR" "$TDIR2"

# --- same-machine split: split / claim / guard / release ----------------------
#
# The lifecycle under test: old session splits (link pending, no bundle) → fresh
# session claims (link completed both ways) → old session's guard reminds once per
# opening → release removes the guard in one step and never touches the folder.

echo "same-machine split"

new_home
OLD=cccc9999-0000-0000-0000-000000000001
NEW=dddd9999-0000-0000-0000-000000000002
transcript "$OLD" >/dev/null; add_ai "$OLD" "The overgrown session"
transcript "$NEW" >/dev/null
pidfile "$$" "$OLD" "n"
HDIR="$FAKE/.claude/session-handoffs"

cat >"$FAKE/note.md" <<'EOF'
## Context
splitting the parser work out

## Assertions
- the tokenizer rewrite was REJECTED for cache reasons
EOF

is "split refuses without a note" 2 \
   "$(CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/split.sh" >/dev/null 2>&1; echo $?)"
is "split refuses outside a session" 1 \
   "$(bash "$ROOT/handoff/split.sh" -n "$FAKE/note.md" >/dev/null 2>&1; echo $?)"

SOUT=$(CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/split.sh" -n "$FAKE/note.md" -t "parser work" 2>/dev/null)
FOLDER=$(printf '%s\n' "$SOUT" | sed -n 's/^split: folder written — //p')
[ -r "$FOLDER/HANDOFF.md" ] && ok "split writes the folder with the note" \
    || bad "split writes the folder with the note" "HANDOFF.md" "missing"
is "…and records who split it" "$OLD" "$(cat "$FOLDER/from" 2>/dev/null)"
is "…with the link still pending" "null" "$(jq -r '.to' "$HDIR/$OLD.handed")"

# A note without assertions warns but is not refused.
printf '## Context\nno assertions here\n' >"$FAKE/note2.md"
WOUT=$(CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/split.sh" -n "$FAKE/note2.md" 2>&1 >/dev/null); RC=$?
is "a note without assertions still splits" 0 "$RC"
case "$WOUT" in *Assertions*) ok "…but says the claim check will have nothing to check" ;;
    *) bad "…but says the claim check will have nothing to check" "a warning naming Assertions" "${WOUT:-silence}";; esac
# restore the first split as the active one (second overwrote the marker)
CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/split.sh" -n "$FAKE/note.md" -t "parser work" >/dev/null 2>&1
FOLDER=$(jq -r '.folder' "$HDIR/$OLD.handed")

guard() { printf '{"session_id":"%s"}' "$1" | bash "$ROOT/hooks/session-guard.sh"; }

# Before any claim, the guard must still work — naming the folder, and saying the
# destination is pending rather than inventing one.
POUT=$(guard "$OLD")
case "$POUT" in *"not claimed"*) ok "the guard works while the claim is pending" ;;
    *) bad "the guard works while the claim is pending" "'not claimed' wording" "${POUT:-silence}";; esac
rm -f "$HDIR/$OLD.guard-seen"

is "claim refuses from the session that split" 1 \
   "$(CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/claim.sh" "$FOLDER" >/dev/null 2>&1; echo $?)"

COUT=$(CLAUDE_CODE_SESSION_ID=$NEW bash "$ROOT/handoff/claim.sh" "$FOLDER" 2>/dev/null)
is "claim completes the old side of the link" "$NEW" "$(jq -r '.to' "$HDIR/$OLD.handed")"
is "…and the new side" "$OLD" "$(jq -r '.from' "$HDIR/$NEW.claimed")"
case "$COUT" in *"tokenizer rewrite was REJECTED"*) ok "claim prints the note as seed context" ;;
    *) bad "claim prints the note as seed context" "the note body" "absent";; esac

is "the guard is silent for an unrelated session" "" "$(guard "$NEW")"
GOUT=$(guard "$OLD")
case "$GOUT" in *"parser work"*"${NEW:0:8}"*) ok "the guard names the topic and the destination" ;;
    *) bad "the guard names the topic and the destination" "topic + ${NEW:0:8}" "${GOUT:-silence}";; esac
is "…once per opening — second prompt is silent" "" "$(guard "$OLD")"

ROUT=$(bash "$ROOT/handoff/release.sh" "$OLD" 2>/dev/null); RC=$?
is "release succeeds" 0 "$RC"
[ ! -e "$HDIR/$OLD.handed" ] && [ ! -e "$HDIR/$NEW.claimed" ] \
    && ok "release clears both sides of the link" \
    || bad "release clears both sides of the link" "markers gone" "still present"
is "…and the guard goes quiet" "" "$(rm -f "$HDIR/$OLD.guard-seen"; guard "$OLD")"
[ -r "$FOLDER/HANDOFF.md" ] && ok "…while the folder survives as the record" \
    || bad "…while the folder survives as the record" "folder kept" "deleted"
is "releasing again refuses — nothing active" 1 \
   "$(bash "$ROOT/handoff/release.sh" "$OLD" >/dev/null 2>&1; echo $?)"

# release with no argument means "this session" — the form the guard's own message
# suggests, so it has to work.
CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/split.sh" -n "$FAKE/note.md" >/dev/null 2>&1
is "release with no argument releases the current session" 0 \
   "$(CLAUDE_CODE_SESSION_ID=$OLD bash "$ROOT/handoff/release.sh" >/dev/null 2>&1; echo $?)"
[ ! -e "$HDIR/$OLD.handed" ] && ok "…and the marker is gone" || bad "…and the marker is gone" "removed" "present"
drop_home

# --- handoff pickup --------------------------------------------------------------
#
# The new-session side of the split: a brand-new session's first message surfaces a
# pending handoff so the agent can claim it — the one manual step left is opening
# the tab. Scoped hard: near-empty sessions only, unclaimed only, once per session.

echo "handoff pickup"

new_home
OLD2=ffff9999-0000-0000-0000-000000000001
FRESH=ffff9999-0000-0000-0000-000000000002
BUSY=ffff9999-0000-0000-0000-000000000003
transcript "$OLD2" >/dev/null; add_ai "$OLD2" "The source session"
transcript "$FRESH" >/dev/null; add_ai "$FRESH" "x"
transcript "$BUSY" >/dev/null; for i in $(seq 1 25); do add_line "$BUSY" '{"type":"filler"}'; done
pidfile "$$" "$OLD2" "documents-2" derived    # derived, so the ai-title resolves
printf '## Context\nrelease pass\n## Assertions\n- x\n' >"$FAKE/note3.md"
CLAUDE_CODE_SESSION_ID=$OLD2 bash "$ROOT/handoff/split.sh" -n "$FAKE/note3.md" -t "release pass" >/dev/null 2>&1

guard() { printf '{"session_id":"%s"}' "$1" | bash "$ROOT/hooks/session-guard.sh"; }

OUT=$(guard "$FRESH")
case "$OUT" in *pending*"release pass"*"The source session"*claim.sh*) ok "a fresh session is told about the pending handoff" ;;
    *) bad "a fresh session is told about the pending handoff" "pickup payload" "${OUT:-silence}";; esac
is "…once — the next message is quiet" "" "$(guard "$FRESH")"
is "a session with real history is never nudged" "" "$(guard "$BUSY")"

# After the claim, other fresh sessions stay quiet.
FRESH2=ffff9999-0000-0000-0000-000000000004
transcript "$FRESH2" >/dev/null; add_ai "$FRESH2" "x"
CLAUDE_CODE_SESSION_ID=$FRESH bash "$ROOT/handoff/claim.sh" \
    "$(jq -r '.folder' "$FAKE/.claude/session-handoffs/$OLD2.handed")" >/dev/null 2>&1
is "a claimed handoff nudges nobody else" "" "$(guard "$FRESH2")"

# Release also stops the nudge (fresh marker, then release before any claim).
CLAUDE_CODE_SESSION_ID=$OLD2 bash "$ROOT/handoff/split.sh" -n "$FAKE/note3.md" >/dev/null 2>&1
bash "$ROOT/handoff/release.sh" "$OLD2" >/dev/null 2>&1
FRESH3=ffff9999-0000-0000-0000-000000000005
transcript "$FRESH3" >/dev/null; add_ai "$FRESH3" "x"
is "a released handoff nudges nobody" "" "$(guard "$FRESH3")"
drop_home

# Stale: unclaimed past the pickup window. The old session's guard must say so and
# name all three exits; fresh sessions must no longer be nudged at all.
new_home
OLD4=ffff9999-0000-0000-0000-000000000006
FRESH5=ffff9999-0000-0000-0000-000000000007
transcript "$OLD4" >/dev/null; add_ai "$OLD4" "Stale source"
transcript "$FRESH5" >/dev/null; add_ai "$FRESH5" "x"
pidfile "$$" "$OLD4" "documents-4" derived
printf '## Context\nx\n## Assertions\n- x\n' >"$FAKE/note4.md"
CLAUDE_CODE_SESSION_ID=$OLD4 bash "$ROOT/handoff/split.sh" -n "$FAKE/note4.md" -t "old topic" >/dev/null 2>&1
touch -t 202001010000 "$FAKE/.claude/session-handoffs/$OLD4.handed"

is "an aged handoff no longer nudges fresh sessions" "" "$(guard "$FRESH5")"
SOUT=$(guard "$OLD4")
case "$SOUT" in *NEVER\ CLAIMED*stale*claim.sh*re-split*release*) ok "the stale guard names the three exits" ;;
    *) bad "the stale guard names the three exits" "stale wording + claim/re-split/release" "${SOUT:-silence}";; esac
# Re-splitting re-arms: fresh marker → normal (non-stale) guard and pickup again.
CLAUDE_CODE_SESSION_ID=$OLD4 bash "$ROOT/handoff/split.sh" -n "$FAKE/note4.md" -t "old topic" >/dev/null 2>&1
rm -f "$FAKE/.claude/session-handoffs/$OLD4.guard-seen" "$FAKE/.claude/session-handoffs/$FRESH5.pickup-seen"
case "$(guard "$OLD4")" in *NEVER\ CLAIMED*) bad "re-splitting re-arms the flow" "normal guard" "still stale";;
    *split\ off*) ok "re-splitting re-arms the flow" ;;
    *) bad "re-splitting re-arms the flow" "normal guard" "silence";; esac
case "$(guard "$FRESH5")" in *pending*claim.sh*) ok "…and fresh sessions are nudged again" ;;
    *) bad "…and fresh sessions are nudged again" "pickup payload" "silence";; esac
drop_home

# --- the drift hook ------------------------------------------------------------
#
# The hook never judges drift — it decides WHEN to ask, and the agent judges. So the
# tests cover the WHEN: first message of a reopened session with real history (gate
# A), every N entries (gate B), and silence everywhere else. Cadence and history
# floor are shrunk via env so fixtures stay small.

echo "the drift hook"

drift() { printf '{"session_id":"%s"}' "$1" \
    | CS_DRIFT_EVERY=10 CS_DRIFT_MIN_HISTORY=3 bash "$ROOT/hooks/session-drift.sh"; }
fill() { local i=0; while [ $i -lt "$2" ]; do add_line "$1" '{"type":"filler"}'; i=$((i+1)); done; }

new_home
ID=eeee9999-0000-0000-0000-000000000001; transcript "$ID" >/dev/null
add_ai "$ID" "Fixing the tokenizer"
pidfile "$$" "$ID" "documents-1" derived

OUT=$(printf 'garbage' | bash "$ROOT/hooks/session-drift.sh"); RC=$?
is "garbage stdin is silent" "" "$OUT"; is "…and exits 0" 0 "$RC"
is "a traversal session_id is silent" "" \
   "$(printf '{"session_id":"../../x"}' | bash "$ROOT/hooks/session-drift.sh")"

# One entry of history: a brand-new session has no established topic to be wrong
# about, so the first-message check stays quiet (but the marker is laid down).
is "a near-empty session gets no wrong-session check" "" "$(drift "$ID")"

fill "$ID" 10
OUT=$(drift "$ID")   # same pid — gate A cannot re-fire; gate B: 11-1=10 >= 10
case "$OUT" in *Drift\ check*Fixing\ the\ tokenizer*rename-session*handoff*) ok "the cadence check names the title and both remedies" ;;
    *) bad "the cadence check names the title and both remedies" "drift payload" "${OUT:-silence}";; esac
is "…and immediately after, it is quiet again" "" "$(drift "$ID")"

fill "$ID" 4
is "below the cadence, still quiet" "" "$(drift "$ID")"
fill "$ID" 6
case "$(drift "$ID")" in *Drift\ check*) ok "at the cadence, it asks again" ;;
    *) bad "at the cadence, it asks again" "drift payload" "silence";; esac

# A new process on a session with real history: the wrong-session check, exactly once.
sleep 30 & DPID=$!
rm -f "$PIDS/$$.json"; pidfile "$DPID" "$ID" "documents-1" derived
OUT=$(drift "$ID")
case "$OUT" in *Wrong-session\ check*Fixing\ the\ tokenizer*) ok "a reopened session gets the wrong-session check first" ;;
    *) bad "a reopened session gets the wrong-session check first" "wrong-session payload" "${OUT:-silence}";; esac
# The same payload sets the session-long standing watch — the initiative lives in
# the kit, delivered once per opening, not in any per-user memory.
case "$OUT" in *Standing\ watch*split*rename-session*) ok "…and sets the standing health watch" ;;
    *) bad "…and sets the standing health watch" "standing-watch instruction" "${OUT:-silence}";; esac
# A live trial showed an agent flagging the mismatch and then running a locate
# anyway, dumping unrelated directory listings into the session. The payload must
# forbid preliminary work outright, allow cs_find as the one routing lookup, and
# gate "do it here" on an explicit user override.
case "$OUT" in *NO\ tool\ calls*nothing\ preliminary*) ok "…and forbids preliminary work on an off-topic ask" ;;
    *) bad "…and forbids preliminary work on an off-topic ask" "a no-preliminary clause" "${OUT:-silence}";; esac
case "$OUT" in *cs_find*explicitly*) ok "…and routes via cs_find with override gated on explicit consent" ;;
    *) bad "…and routes via cs_find with override gated on explicit consent" "cs_find + explicit override" "${OUT:-silence}";; esac
is "…exactly once — the next message is quiet" "" "$(drift "$ID")"
{ kill "$DPID" && wait "$DPID"; } 2>/dev/null
drop_home

# A session that resolves to nothing better than its short id: the cadence check
# becomes a naming nudge instead of a drift question against a meaningless title.
new_home
ID=eeee9999-0000-0000-0000-000000000002; transcript "$ID" >/dev/null
fill "$ID" 2
jq -n --arg p "$$" --arg i "$ID" --arg v "$CS_VERIFIED_VERSION" \
    '{pid:($p|tonumber),sessionId:$i,version:$v}' >"$PIDS/$$.json"
drift "$ID" >/dev/null                      # lay the marker (near-empty: silent)
fill "$ID" 10
case "$(drift "$ID")" in *Naming\ check*rename-session*) ok "an untitled session is nudged toward a name" ;;
    *) bad "an untitled session is nudged toward a name" "naming payload" "silence";; esac
drop_home

# --- silent-drift detection -------------------------------------------------
#
# Three ways Claude Code can move that break the kit WITHOUT violating any invariant
# about the data itself. Each of these passed 0-failed before the checks existed, so
# each is pinned here: the point is not that smoke.sh runs, but that it still fails
# when it should.

echo "silent drift"

# Six sessions: enough to clear the title-type threshold, so the check concludes
# rather than skipping.
six() { for i in 1 2 3 4 5 6; do
    printf '%s\n' "$2" > "$1/$(printf '%08x' "$i")-0000-0000-0000-000000000001.jsonl"; done; }

# Claude Code renames the title entry types. Every accessor still returns a name — it
# just silently degrades to a worse one — so nothing else can notice.
new_home
six "$PROJ" "$(jq -cn '{type:"sessionTitle",sessionTitle:"the new format"}')"
pidfile "$$" z n
OUT=$(bash "$ROOT/tests/smoke.sh" 2>&1); RC=$?
is "renamed title entry types fail the suite" 1 "$RC"
case "$OUT" in *"known title entry types still appear"*) ok "…and name the reason" ;;
    *) bad "…and name the reason" "title-type check fires" "something else" ;; esac
drop_home

# The pid-file schema moves. cs_running_version goes empty, so the version guard stops
# warning and the hook exits early — the early-warning system switches itself off.
new_home
six "$PROJ" "$(jq -cn '{type:"ai-title",aiTitle:"T"}')"
jq -n '{pid:1,session_id:"z",name:"n",claudeVersion:"9.9.9"}' >"$PIDS/1.json"
OUT=$(bash "$ROOT/tests/smoke.sh" 2>&1); RC=$?
is "an unreadable pid-file version fails the suite" 1 "$RC"
case "$OUT" in *"version is readable from the pid-files"*) ok "…and name the reason" ;;
    *) bad "…and name the reason" "pid-schema check fires" "something else" ;; esac
drop_home

# The directory layout gains a level. Transcripts exist but not where we look, which
# used to read as "nothing to check" and exit 0 — total breakage as a clean pass.
new_home
mkdir -p "$PROJ/nested"
six "$PROJ/nested" "$(jq -cn '{type:"ai-title",aiTitle:"T"}')"
pidfile "$$" z n
OUT=$(bash "$ROOT/tests/smoke.sh" 2>&1); RC=$?
is "a moved layout fails instead of skipping" 1 "$RC"
case "$OUT" in *"expected depth"*) ok "…and name the reason" ;;
    *) bad "…and name the reason" "depth check fires" "something else" ;; esac
drop_home

# The opposite must stay true: genuinely empty is a skip, not a failure, or CI breaks.
new_home
OUT=$(bash "$ROOT/tests/smoke.sh" 2>&1); RC=$?
is "a genuinely empty home still skips cleanly" 0 "$RC"
drop_home

# Subagent transcripts (agent-*.jsonl, one level deeper) are not sessions and must not
# be counted as misplaced ones — 8 exist on the machine this was written on.
new_home
six "$PROJ" "$(jq -cn '{type:"ai-title",aiTitle:"T"}')"
mkdir -p "$PROJ/aaaaaaaa-0000-0000-0000-000000000001"
printf '%s\n' '{"type":"user"}' >"$PROJ/aaaaaaaa-0000-0000-0000-000000000001/agent-abc123.jsonl"
pidfile "$$" z n
is "subagent transcripts do not trip the depth check" 0 \
   "$(bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1; echo $?)"
drop_home

# --- sourcing from other shells ---------------------------------------------
# rename.sh locates core/ relative to itself. BASH_SOURCE is bash-only, so a
# naive lookup breaks the moment someone sources it from an interactive zsh.

echo "portability"

if command -v zsh >/dev/null 2>&1; then
    if zsh -c ". '$ROOT/naming/rename.sh' && rename_check_title x >/dev/null" 2>/dev/null; then
        ok "sources cleanly under zsh"
    else
        bad "sources cleanly under zsh" "sourced" "failed to find core/sessions.sh"
    fi
    if zsh -c ". '$ROOT/notes/note.sh' && type note_write >/dev/null" 2>/dev/null; then
        ok "notes module sources cleanly under zsh"
    else
        bad "notes module sources cleanly under zsh" "sourced" "failed to find core/sessions.sh"
    fi
else
    ok "sources cleanly under zsh (skipped, no zsh)"
fi

# The override is what a caller uses when its shell cannot report the sourced path.
if bash -c "CLAUDE_SESSION_KIT_ROOT='$ROOT' . '$ROOT/naming/rename.sh' && rename_check_title x >/dev/null" 2>/dev/null; then
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
