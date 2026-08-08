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
