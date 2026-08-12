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
    # Match CLAUDE_SESSION_KIT_VERIFIED_VERSION so the version guard stays quiet; a mismatch here is
    # noise, and the guard's own behaviour is not what these cases are testing.
    jq -n --arg p "$1" --arg i "$2" --arg n "$3" --arg s "${4:-}" --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" \
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
   "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" "$(cs_verified_version)"

mkdir -p "$FAKE/.claude/session-kit"
echo "9.9.9" >"$FAKE/.claude/session-kit/.verified"
is "a recorded version overrides the author's" "9.9.9" "$(cs_verified_version)"

printf '  2.5.0 \n' >"$FAKE/.claude/session-kit/.verified"
is "surrounding whitespace is ignored" "2.5.0" "$(cs_verified_version)"

: >"$FAKE/.claude/session-kit/.verified"
is "an empty state file falls back, never resolves empty" \
   "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" "$(cs_verified_version)"

# The record is a LIST of versions that passed here, and the single-line file older
# installs wrote is a one-element list, so no migration is needed.
printf '2.1.222\n2.1.226\n2.1.9\n' >"$FAKE/.claude/session-kit/.verified"
is "several recorded versions resolve to the newest" "2.1.226" "$(cs_verified_version)"
is "version order is numeric, not lexical" "2.1.9" "$(_cs_verified_list | head -1)"

cs_version_verified 2.1.222 && ok "an older recorded version is still verified" \
    || bad "an older recorded version is still verified" "verified" "not verified"
cs_version_verified 2.1.224 && bad "an untested version between two passes is NOT verified" \
    "not verified" "verified" \
    || ok "an untested version between two passes is NOT verified"

is "the span names both ends and how many were tested" \
   "2.1.9 to 2.1.226 (3 versions)" "$(cs_verified_span)"
echo "2.1.222" >"$FAKE/.claude/session-kit/.verified"
is "a single recorded version reads as itself, not a span" "2.1.222" "$(cs_verified_span)"

# The file is user-visible state, so a hand-edited line must not become a version.
printf 'not-a-version\n2.1.222\n$(touch /tmp/pwned)\n' >"$FAKE/.claude/session-kit/.verified"
is "junk lines are dropped rather than treated as versions" "2.1.222" "$(_cs_verified_list)"
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

# Reopening an older session must not reawaken the warning: that version passed here
# too. Equality against the newest recorded version got this wrong.
printf '9.9.9\n9.9.10\n' >"$FAKE/.claude/session-kit/.verified"
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.9"}' >"$PIDS/1.json"
OUT=$(unset _CS_VERSION_WARNED; cs_version_guard 2>&1)
is "silent on an older version that also passed here" "" "$OUT"

# ...but the warning must still name the whole span when the version is genuinely new.
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.11"}' >"$PIDS/1.json"
OUT=$(unset _CS_VERSION_WARNED; cs_version_guard 2>&1)
case "$OUT" in
    *9.9.11*"9.9.9 to 9.9.10 (2 versions)"*) ok "the warning reports the span, not just the newest" ;;
    *) bad "the warning reports the span, not just the newest" "span" "${OUT:-silence}" ;;
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

# --- the degraded notice ----------------------------------------------------
#
# The kit's healthy state is silence, so both known breakages are invisible: without
# jq every hook exits 0 printing nothing, and a self-check that failed reaches you
# only through the commands you type. These cases are the difference between "quiet
# because all is well" and "quiet because nothing is running".
#
# A PATH holding the notice path's tools but NOT jq reproduces the first one honestly,
# rather than stubbing out the probe and testing the stub.

echo "the degraded notice"

nojq_run() {  # <shell-code> -> run it with a real PATH minus jq
    local d="$FAKE/nojq" t=""
    mkdir -p "$d"
    for t in mkdir date find rm; do ln -sf "$(command -v "$t")" "$d/$t" 2>/dev/null; done
    env PATH="$d" CLAUDE_SESSION_KIT_HOME="$FAKE" \
        "$(command -v bash)" -c ". '$ROOT/core/sessions.sh' 2>/dev/null; $1" 2>&1
}

new_home
mkdir -p "$FAKE/.claude/session-kit"
is "a healthy kit says nothing" "" "$(cs_notice_degraded)"
cs_degraded_reason >/dev/null 2>&1 \
    && bad "a healthy kit reports no reason" "non-zero" "zero" \
    || ok "a healthy kit reports no reason"

# The jq fault, reproduced rather than simulated.
OUT=$(nojq_run 'cs_notice_degraded')
case "$OUT" in
    *"claude-session-kit:"*"jq is missing"*"brew install jq"*)
        ok "a missing jq is reported, and names the fix" ;;
    *)  bad "a missing jq is reported, and names the fix" "the jq line" "${OUT:-silence}" ;;
esac

# ...and it must be reported ONCE a day, however many hooks fire.
OUT=$(nojq_run 'cs_notice_degraded')
is "the same fault is not repeated the same day" "" "$OUT"
drop_home

# A failed self-check is the other fault. smoke.sh's report file IS the signal, so it
# clears itself: a later passing run deletes that file (asserted in failure reporting).
new_home
mkdir -p "$FAKE/.claude/session-kit"
echo "stale report" >"$FAKE/.claude/session-kit/last-failure.md"
OUT=$(cs_notice_degraded)
case "$OUT" in
    *"claude-session-kit:"*"last self-check failed"*"--report"*)
        ok "a failed self-check is reported, and names the report command" ;;
    *)  bad "a failed self-check is reported, and names the report command" \
            "the self-check line" "${OUT:-silence}" ;;
esac
is "...and it too is reported only once a day" "" "$(cs_notice_degraded)"

# Two faults on one day must not silence each other, which keying on the fault buys.
OUT=$(nojq_run 'cs_notice_degraded')
case "$OUT" in
    *"jq is missing"*) ok "a second, different fault still gets through the same day" ;;
    *) bad "a second, different fault still gets through the same day" "the jq line" "${OUT:-silence}" ;;
esac

# The marker directory must not grow forever.
mkdir -p "$FAKE/.claude/session-kit/.notices/jq-2020-01-01"
rm -rf "$FAKE/.claude/session-kit/.notices/selfcheck-$(date +%F)"
OUT=$(cs_notice_degraded)
[ -d "$FAKE/.claude/session-kit/.notices/jq-2020-01-01" ] \
    && bad "markers from other days are swept" "gone" "still there" \
    || ok "markers from other days are swept"
drop_home

# The whole point is that this reaches a hooks-only user, so assert it through a real
# hook: the notice comes out, and the hook still exits 0 and never breaks a prompt.
new_home
mkdir -p "$FAKE/.claude/session-kit"
NOJQ="$FAKE/nojq"; mkdir -p "$NOJQ"
for t in mkdir date find rm cat; do ln -sf "$(command -v "$t")" "$NOJQ/$t" 2>/dev/null; done
OUT=$(printf '{"session_id":"x"}' | env PATH="$NOJQ" CLAUDE_SESSION_KIT_HOME="$FAKE" \
      CLAUDE_SESSION_KIT_ROOT="$ROOT" "$(command -v bash)" "$ROOT/hooks/session-note.sh" 2>&1); RC=$?
is "the session-note hook still exits 0 with no jq" 0 "$RC"
case "$OUT" in
    *"jq is missing"*) ok "...and the notice reaches a hooks-only user" ;;
    *) bad "...and the notice reaches a hooks-only user" "the jq line" "${OUT:-silence}" ;;
esac
drop_home

# smoke.sh must stop calling a broken install a clean run.
new_home
NOJQ="$FAKE/nojq"; mkdir -p "$NOJQ"
for t in mkdir date find rm cat printf; do ln -sf "$(command -v "$t")" "$NOJQ/$t" 2>/dev/null; done
OUT=$(env PATH="$NOJQ" CLAUDE_SESSION_KIT_HOME="$FAKE" \
      "$(command -v bash)" "$ROOT/tests/smoke.sh" 2>&1); RC=$?
is "smoke refuses rather than reporting a clean run with no jq" 1 "$RC"
case "$OUT" in
    *"nothing can be checked"*) ok "...and says the kit is not working" ;;
    *) bad "...and says the kit is not working" "the refusal" "${OUT:-silence}" ;;
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
jq -n --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" '{pid:1,sessionId:"z",name:"n",version:$v}' >"$PIDS/1.json"

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
jq -n --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" '{pid:1,sessionId:"z",name:"n",version:$v}' >"$PIDS/1.json"
mkdir -p "$FAKE/.claude/session-kit"
echo "stale" >"$FAKE/.claude/session-kit/last-failure.md"
bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1
[ -f "$FAKE/.claude/session-kit/last-failure.md" ] \
    && bad "a passing run clears a stale report" "removed" "still there" \
    || ok "a passing run clears a stale report"
is "a passing run records the verified version" \
   "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" "$(cat "$FAKE/.claude/session-kit/.verified" 2>/dev/null)"
drop_home

# The record only ever widens. This was a live bug on a machine running several
# sessions at once: a pass while only OLDER sessions were live overwrote a newer
# recorded pass, so the record went backwards and the suite re-ran for a version it
# had already cleared. The pid-file here is deliberately the OLDER version.
new_home
ID=77777777-0000-0000-0000-000000000003; transcript "$ID" >/dev/null
add_ai "$ID" "Perfectly fine"
jq -n --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" '{pid:1,sessionId:"z",name:"n",version:$v}' >"$PIDS/1.json"
mkdir -p "$FAKE/.claude/session-kit"
printf '99.0.0\n' >"$FAKE/.claude/session-kit/.verified"
bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1
is "a pass on an older version does not erase a newer one" "99.0.0" "$(cs_verified_version)"
is "...and the older version is added alongside it" \
   "$CLAUDE_SESSION_KIT_VERIFIED_VERSION
99.0.0" "$(_cs_verified_list)"

# Re-running on a version already recorded must leave the record exactly as it is.
BEFORE=$(cat "$FAKE/.claude/session-kit/.verified")
bash "$ROOT/tests/smoke.sh" >/dev/null 2>&1
is "re-recording a known version changes nothing" "$BEFORE" \
   "$(cat "$FAKE/.claude/session-kit/.verified")"
[ -z "$(find "$FAKE/.claude/session-kit" -name '.verified.*' 2>/dev/null)" ] \
    && ok "the staged write leaves no temp file behind" \
    || bad "the staged write leaves no temp file behind" "none" "present"
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

# Switching back to an older session must not launch anything: that version is in the
# record. Under the old equality check it did, on every switch, forever.
printf '9.9.8\n9.9.9\n' >"$FAKE/.claude/session-kit/.verified"
jq -n '{pid:1,sessionId:"z",name:"n",version:"9.9.8"}' >"$PIDS/1.json"
CLAUDE_SESSION_KIT_ROOT="$FAKE/kit" bash "$ROOT/hooks/version-check.sh"
sleep 0.5
is "switching back to an older recorded version launches nothing" 2 \
   "$(grep -c x "$FAKE/kit/.count" 2>/dev/null)"
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
# The hook is COPIED into the scratch repo and invoked from there: hookdir resolves
# relative to the hook file, so this is what keeps every test below hermetic — the
# developer's real guardrail/denylist.local is never read, the scratch one is.
mkdir -p "$GR/guardrail"
cp "$ROOT/guardrail/pre-commit" "$GR/guardrail/pre-commit"

printf 'a clean line, ~ instead of a real path\n' >"$GR/ok.md"
git -C "$GR" add ok.md
is "clean staged content passes" 0 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"

leak_path="/Use""rs/janedoe/secret-project"
printf 'data at %s today\n' "$leak_path" >"$GR/leak.md"
git -C "$GR" add leak.md
is "a staged home path is blocked" 1 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached leak.md

leak_mail="someone@""example.com"
printf 'contact: %s\n' "$leak_mail" >"$GR/mail.md"
git -C "$GR" add mail.md
is "a staged email is blocked" 1 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached mail.md

printf 'remote: git@github.com:someone/repo.git\n' >"$GR/rem.md"
git -C "$GR" add rem.md
is "an SSH remote URL is not treated as an email" 0 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached rem.md

printf 'the contoso engagement notes\n' >"$GR/dl.md"
git -C "$GR" add dl.md
is "a denylisted term via env is blocked" 1 \
   "$(cd "$GR" && CLAUDE_CONFIG_DENYLIST=contoso bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"

# The FILE path was untested while being the documented mechanism, and its failure
# is silent: generic patterns keep blocking, only private terms quietly stop. The
# same staged leak, no env var — the term must come from denylist.local alone.
printf '# private terms\ncontoso\n' >"$GR/guardrail/denylist.local"
is "a denylisted term via the FILE is blocked" 1 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached dl.md

# The example ships comments-only and install.sh seeds it verbatim: the seeded
# default must block nothing (a parsing slip could turn comments into patterns).
cp "$ROOT/guardrail/denylist.local.example" "$GR/guardrail/denylist.local"
printf 'an ordinary line about work\n' >"$GR/plain.md"
git -C "$GR" add plain.md
is "the shipped example (comments only) blocks nothing" 0 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached plain.md
rm -f "$GR/guardrail/denylist.local"

# The style rule scopes to reader-facing docs only (README.md, docs/*.md), so this
# suite may hold the literal em-dash safely — run.sh is never inside that scope.
mkdir -p "$GR/docs"
printf 'a clause — set off wrong\n' >"$GR/docs/style.md"
git -C "$GR" add docs/style.md
is "an em-dash staged in docs/*.md is blocked" 1 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached docs/style.md

printf 'a clause — set off wrong\n' >"$GR/README.md"
git -C "$GR" add README.md
is "an em-dash staged in README.md is blocked" 1 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
git -C "$GR" rm -q --cached README.md

printf 'a scratch note — em-dash allowed here\n' >"$GR/scratch.md"
git -C "$GR" add scratch.md
is "an em-dash outside README/docs passes (scope is the path, not the extension)" 0 \
   "$(cd "$GR" && bash "$GR/guardrail/pre-commit" >/dev/null 2>&1; echo $?)"
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

# No sha tool on the machine: refuse before touching anything, never emit a bundle
# with empty digests. Simulated with an empty PATH — the guard is the first line
# after set -e, so nothing else can run first. The message is asserted too, so a
# different command-not-found dying under set -e cannot pass this for the wrong reason.
BASHBIN=$(command -v bash)
NOSHA=$(PATH='' "$BASHBIN" "$ROOT/handoff/export.sh" whatever 2>&1 >/dev/null); RC=$?
is "export with no sha tool refuses" 1 "$RC"
case "$NOSHA" in *shasum*) ok "…naming the missing tool" ;;
    *) bad "…naming the missing tool" "'shasum' in the error" "$NOSHA";; esac
NOSHA=$(PATH='' "$BASHBIN" "$ROOT/handoff/import.sh" whatever.tar.gz 2>&1 >/dev/null); RC=$?
is "import with no sha tool refuses" 1 "$RC"
case "$NOSHA" in *shasum*) ok "…naming the missing tool" ;;
    *) bad "…naming the missing tool" "'shasum' in the error" "$NOSHA";; esac

# A sha tool that EXISTS but misbehaves (prints nothing) is the deeper version of the
# same hole: presence passes the guard, so the digest VALUE must be validated at each
# use — otherwise a blank lands in the manifest, and blank == blank verifies on import.
STUB=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' >"$STUB/sha256sum" && chmod +x "$STUB/sha256sum"
BROKE=$(PATH="$STUB:$PATH" CLAUDE_SESSION_KIT_HOME="$HA" \
        bash "$ROOT/handoff/export.sh" -o "$OUT" "$S1" 2>&1 >/dev/null); RC=$?
is "a sha tool that outputs nothing refuses export" 1 "$RC"
case "$BROKE" in *checksum*) ok "…blaming the checksum, not something else" ;;
    *) bad "…blaming the checksum, not something else" "'checksum' in the error" "$BROKE";; esac
BROKE=$(PATH="$STUB:$PATH" CLAUDE_SESSION_KIT_HOME="$HB" \
        bash "$ROOT/handoff/import.sh" "$BUNDLE" 2>&1 >/dev/null); RC=$?
is "a sha tool that outputs nothing refuses import" 1 "$RC"
case "$BROKE" in *checksum*) ok "…blaming the checksum, not something else" ;;
    *) bad "…blaming the checksum, not something else" "'checksum' in the error" "$BROKE";; esac
rm -rf "$STUB"

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
jq -n --arg p "$$" --arg i "$S1" --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" \
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
jq -n --arg p "$$" --arg i "$ID" --arg v "$CLAUDE_SESSION_KIT_VERIFIED_VERSION" \
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

# --- the config file ---------------------------------------------------------
#
# Knobs resolve env > file > default. The file lives in the state dir (beside
# .verified), is parsed strictly and never sourced — the injection test proves a
# command-shaped value cannot run — and anything malformed falls back to the
# default: hooks fail open.

echo "the config file"

new_home
CONF="$FAKE/.claude/session-kit"; mkdir -p "$CONF"
. "$ROOT/core/sessions.sh"

is "no config file: the default answers" 200 "$(cs_conf CS_DRIFT_EVERY 200)"
printf 'CS_DRIFT_EVERY=300\n' >"$CONF/config"
is "a file value overrides the default" 300 "$(cs_conf CS_DRIFT_EVERY 200)"
is "a key the file lacks keeps its default" 20 "$(cs_conf CS_DRIFT_MIN_HISTORY 20)"
printf '# comment\nCS_DRIFT_EVERY=300\nCS_DRIFT_EVERY=400\n' >"$CONF/config"
is "the last duplicate wins" 400 "$(cs_conf CS_DRIFT_EVERY 200)"
printf 'CS_DRIFT_EVERY=  77  \n' >"$CONF/config"
is "surrounding whitespace is tolerated" 77 "$(cs_conf CS_DRIFT_EVERY 200)"
printf 'CS_DRIFT_EVERY=ten\n' >"$CONF/config"
is "a non-numeric value falls back to the default" 200 "$(cs_conf CS_DRIFT_EVERY 200)"
printf 'CS_DRIFT_EVERY=$(touch %s/pwned)\n' "$FAKE" >"$CONF/config"
is "a command-shaped value falls back to the default" 200 "$(cs_conf CS_DRIFT_EVERY 200)"
[ ! -e "$FAKE/pwned" ] && ok "…and provably never executed" \
    || bad "…and provably never executed" "no side effect" "pwned file exists"

# End to end through the drift hook: the file value drives gate B, and env still
# wins over the file. Both branches discriminate: if the file were ignored, the
# default cadence (200) would keep every fixture silent.
ID9=cccc9999-0000-0000-0000-000000000001; transcript "$ID9" >/dev/null
add_ai "$ID9" "Config knob test"
pidfile "$$" "$ID9" "documents-9" derived
printf 'CS_DRIFT_EVERY=10\nCS_DRIFT_MIN_HISTORY=3\n' >"$CONF/config"
drift9() { printf '{"session_id":"%s"}' "$1" | bash "$ROOT/hooks/session-drift.sh"; }
is "hook via file config: a near-empty session stays quiet" "" "$(drift9 "$ID9")"
fill "$ID9" 10
case "$(drift9 "$ID9")" in *Drift\ check*) ok "the drift cadence honors the config file" ;;
    *) bad "the drift cadence honors the config file" "drift payload" "silence";; esac
fill "$ID9" 3
case "$(CS_DRIFT_EVERY=3 drift9 "$ID9")" in *Drift\ check*) ok "env still beats the file" ;;
    *) bad "env still beats the file" "drift payload" "silence";; esac
drop_home

# The pickup knobs, previously untested. Max-history gates who counts as brand-new
# (file form, proving the guard reads the config too); the window knob is shown by
# inversion: an aged marker plus a huge window is still offered, where the default
# window (already tested above) would have gone stale.
new_home
CONF="$FAKE/.claude/session-kit"; mkdir -p "$CONF"
OLD9=cccc9999-0000-0000-0000-000000000002
NEW9=cccc9999-0000-0000-0000-000000000003
transcript "$OLD9" >/dev/null; add_ai "$OLD9" "Knob source"
transcript "$NEW9" >/dev/null; add_ai "$NEW9" "x"
pidfile "$$" "$OLD9" "documents-8" derived
printf '## Context\nx\n## Assertions\n- x\n' >"$FAKE/note9.md"
CLAUDE_CODE_SESSION_ID=$OLD9 bash "$ROOT/handoff/split.sh" -n "$FAKE/note9.md" -t "knobs" >/dev/null 2>&1
guard9() { printf '{"session_id":"%s"}' "$1" | bash "$ROOT/hooks/session-guard.sh"; }

printf 'CS_PICKUP_MAX_HISTORY=1\n' >"$CONF/config"
is "pickup max-history via the config file gates the nudge" "" "$(guard9 "$NEW9")"
rm -f "$CONF/config" "$FAKE/.claude/session-handoffs/$NEW9.pickup-seen"
touch -t 202001010000 "$FAKE/.claude/session-handoffs/$OLD9.handed"
case "$(CS_PICKUP_WINDOW_MIN=99999999 guard9 "$NEW9")" in *pending*claim.sh*) ok "a wider pickup window keeps an aged handoff alive" ;;
    *) bad "a wider pickup window keeps an aged handoff alive" "pickup payload" "silence";; esac
case "$(CS_PICKUP_WINDOW_MIN=99999999 guard9 "$OLD9")" in *NEVER\ CLAIMED*) bad "…and the source guard is not stale under it" "normal guard" "stale";;
    *split\ off*) ok "…and the source guard is not stale under it" ;;
    *) bad "…and the source guard is not stale under it" "normal guard" "silence";; esac
drop_home

# --- install and uninstall ------------------------------------------------------
#
# install.sh is invoked for real against a scratch prefix (CLAUDE_SESSION_KIT_NO_GATE
# skips its run.sh gate — gating would recurse). Everything here is a property the
# installer promises in the README, so a broken promise fails a test rather than a
# user's machine.

echo "install and uninstall"

inst() { CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
         bash "$ROOT/install.sh" "$@" >/dev/null 2>&1; }
# Hooks belonging to THIS kit, counted by the four shipped basenames. The leading
# [/] is load-bearing: unanchored, "session-note.sh" also matches the near-miss
# "mysession-note.sh" below, and this counter would report the installer buggy
# when it behaved correctly (it did, the first time this was written).
ours() { jq '[.hooks[]?[]?.hooks[]?.command // ""
              | select(test("[/](version-check|session-note|session-guard|session-drift)[.]sh"))]
             | length' "$SETT" 2>/dev/null; }

new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"
# Seed a pre-existing config so the backup assertions below have something to back
# up. A machine with no settings.json is a different case, covered further down:
# there, undoing means removing the file we created, so no backup is written.
mkdir -p "$IPREFIX"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/bin/pre-existing.sh"}]}]}}' >"$SETT"

inst; is "install from the checkout exits 0" 0 $?

# --- what lands on disk ---
for f in core/sessions.sh naming/rename.sh notes/note.sh tests/smoke.sh \
         hooks/version-check.sh hooks/session-note.sh hooks/session-guard.sh hooks/session-drift.sh \
         handoff/export.sh handoff/import.sh handoff/split.sh handoff/claim.sh handoff/release.sh \
         config.example settings.snippet.json; do
    [ -f "$IPREFIX/session-kit/$f" ] || { bad "installs $f" "present" "missing"; continue; }
    ok "installs $f"
done
for h in version-check session-note session-guard session-drift; do
    [ -x "$IPREFIX/session-kit/hooks/$h.sh" ] && ok "hooks/$h.sh is executable" \
        || bad "hooks/$h.sh is executable" "executable" "not executable"
done
for s in rename-session session-note handoff; do
    [ -f "$IPREFIX/skills/$s/SKILL.md" ] && ok "installs the $s skill" \
        || bad "installs the $s skill" "present" "missing"
done
# A missed path rewrite installs a skill that silently cannot find its libraries.
is "skills have no un-rewritten relative sources" "" \
   "$(grep -lE '^\. (core|naming|notes)/|^handoff/' "$IPREFIX"/skills/*/SKILL.md 2>/dev/null)"

# --- the config file, seeded once ---
[ -f "$IPREFIX/session-kit/config" ] && ok "a fresh install seeds the config" \
    || bad "a fresh install seeds the config" "config present" "missing"
printf 'CS_DRIFT_EVERY=42\n' >"$IPREFIX/session-kit/config"

# --- hook wiring ---
is "install wires all four hooks" 4 "$(ours)"
is "…one of them on SessionStart" 1 \
   "$(jq '[.hooks.SessionStart[]?.hooks[]?] | length' "$SETT")"
is "…and three on UserPromptSubmit" 3 \
   "$(jq '[.hooks.UserPromptSubmit[]?.hooks[]?] | length' "$SETT")"
[ -f "$SETT.session-kit.bak" ] && ok "…leaving a backup" \
    || bad "…leaving a backup" "settings.json.session-kit.bak" "missing"
# The shared name belongs to nobody: claude-memory-kit backs up to settings.json.bak
# too, so writing there would destroy whichever kit installed first.
[ -e "$SETT.bak" ] && bad "…without touching the shared settings.json.bak" "untouched" "written" \
    || ok "…without touching the shared settings.json.bak"

# Every command the snippet wires must name a script the kit actually installs.
# Drift here would wire a hook at a path that never fires, silently.
for b in $(jq -r '[.hooks[][].hooks[].command] | .[]' "$ROOT/settings.snippet.json" \
           | grep -oE '[A-Za-z0-9_-]+\.sh'); do
    [ -f "$IPREFIX/session-kit/hooks/$b" ] && ok "the snippet's $b is a script we ship" \
        || bad "the snippet's $b is a script we ship" "installed hook" "no such file"
done

inst
is "a re-run (the upgrade path) preserves the edited config" "CS_DRIFT_EVERY=42" \
   "$(cat "$IPREFIX/session-kit/config")"
[ -f "$IPREFIX/session-kit/config.example" ] && ok "…while the example ships regardless" \
    || bad "…while the example ships regardless" "example present" "missing"
is "…and wiring is idempotent, still four" 4 "$(ours)"

# Deleting a hook and re-installing puts it back: "install" means "wire my hooks".
# The README says so in both the Upgrading section and the FAQ, so pin it.
jq 'del(.hooks.UserPromptSubmit[0].hooks[0])' "$SETT" >"$SETT.t" && mv "$SETT.t" "$SETT"
is "sanity: one hook deleted by hand" 3 "$(ours)"
inst
is "re-installing restores a hook the user deleted" 4 "$(ours)"
drop_home

# Identity is the script BASENAME, never the exact command string. Each spelling
# below is a real way the same hook gets written; exact-string matching duplicated
# every one of them. Pre-wire all four in variant spellings: install must add NONE.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
cat >"$SETT" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "/abs/elsewhere/session-kit/hooks/version-check.sh 2>/dev/null || true" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/session-note.sh\" || true" },
        { "type": "command", "command": "CS_DRIFT_EVERY=50 \"$HOME/.claude/session-kit/hooks/session-drift.sh\" 2>/dev/null || true" },
        { "type": "command", "command": "\"$HOME/.claude/session-kit/hooks/session-guard.sh\"    2>/dev/null   || true" }
      ] }
    ]
  }
}
JSON
inst
is "five spellings of the same hooks are recognised, none duplicated" 4 "$(ours)"

# Near-miss and foreign scripts are never ours, in either direction.
jq '.hooks.UserPromptSubmit += [
      {"hooks":[{"type":"command","command":"\"$HOME/.claude/x/mysession-note.sh\""}]},
      {"hooks":[{"type":"command","command":"\"$HOME/.claude/memory-kit/scripts/memory-delta-ping.sh\" 2>/dev/null || true"}]}
    ]' "$SETT" >"$SETT.tmp" && mv "$SETT.tmp" "$SETT"
inst
is "a near-miss basename is not treated as ours" 1 \
   "$(jq '[.hooks[]?[]?.hooks[]?.command | select(test("mysession-note[.]sh"))] | length' "$SETT")"
is "…and install still adds nothing" 4 "$(ours)"

inst --uninstall
is "uninstall removes every spelling of our hooks" 0 "$(ours)"
is "…and leaves the foreign kit's hook alone" 1 \
   "$(jq '[.hooks[]?[]?.hooks[]?.command | select(test("memory-delta-ping[.]sh"))] | length' "$SETT")"
is "…and leaves the near-miss alone" 1 \
   "$(jq '[.hooks[]?[]?.hooks[]?.command | select(test("mysession-note[.]sh"))] | length' "$SETT")"
is "…and prunes the event left empty" "null" "$(jq -r '.hooks.SessionStart // "null"' "$SETT")"
[ -d "$IPREFIX/session-kit" ] && bad "uninstall removes the kit tree" "gone" "present" \
    || ok "uninstall removes the kit tree"
is "…and the skills" "" "$(ls "$IPREFIX/skills" 2>/dev/null)"
inst --uninstall
is "uninstalling twice is not an error" 0 $?
drop_home

# A DIFFERENT toolkit shipping a script with one of our filenames. Basename alone
# cannot tell them apart, and getting it wrong fails in both directions at once:
# we skip wiring ours (a kit that silently does nothing) and delete theirs on
# uninstall. The DIRECTORY decides, and the clash is reported rather than passed
# over in silence, because silence there looks like a bug in us.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
cat >"$SETT" <<'JSON'
{ "hooks": { "UserPromptSubmit": [ { "hooks": [
  { "type": "command", "command": "\"$HOME/.claude/other-toolkit/hooks/session-note.sh\" 2>/dev/null || true" }
] } ] } }
JSON
theirs() { jq '[.hooks[]?[]?.hooks[]?.command | select(test("other-toolkit"))] | length' "$SETT"; }
mine()   { jq '[.hooks[]?[]?.hooks[]?.command | select(test("session-kit/hooks/"))] | length' "$SETT"; }
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" bash "$ROOT/install.sh" 2>&1)
case "$OUT" in *"owned by something else"*other-toolkit*) ok "install warns about a same-named hook owned by another toolkit" ;;
    *) bad "install warns about a same-named hook owned by another toolkit" "a clash warning" "${OUT:-silence}";; esac
is "…and wires all four of ours anyway" 4 "$(mine)"
is "…without disturbing theirs" 1 "$(theirs)"
inst --uninstall
is "uninstall removes only hooks living under session-kit/hooks" 0 "$(mine)"
is "…so the other toolkit's hook is still there" 1 "$(theirs)"
drop_home

# Pruning all the way up: when ours were the only hooks, no scaffolding is left.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"
inst
is "sanity: four wired before the prune test" 4 "$(ours)"
inst --uninstall
is "an emptied settings.json keeps no hooks key at all" "null" "$(jq -r '.hooks // "null"' "$SETT")"
is "…and stays valid JSON" 0 "$(jq -e . "$SETT" >/dev/null 2>&1; echo $?)"
drop_home

# Shapes we do not recognise are left exactly as they are: a malformed command
# counts as NOT ours, so removal tidies nobody else's mess and cannot crash.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
cat >"$SETT" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": "not-an-array" }, { "no_hooks_key": 1 } ],
    "Weird": "a string where an array belongs"
  },
  "otherSetting": {"keep": true}
}
JSON
inst; is "install survives malformed pre-existing settings" 0 $?
is "…and wires our four anyway" 4 "$(ours)"
inst --uninstall; is "uninstall survives them too" 0 $?
is "…leaving the malformed entries untouched" 2 \
   "$(jq '.hooks.UserPromptSubmit | length' "$SETT")"
is "…the foreign event untouched" '"a string where an array belongs"' "$(jq -c '.hooks.Weird' "$SETT")"
is "…and unrelated settings untouched" '{"keep":true}' "$(jq -c '.otherSetting' "$SETT")"
drop_home

# --dry-run must not touch anything, which is the whole point of offering it.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"
inst --dry-run
[ -e "$IPREFIX/session-kit" ] && bad "--dry-run installs nothing" "nothing" "kit tree created" \
    || ok "--dry-run installs nothing"
[ -e "$SETT" ] && bad "--dry-run writes no settings.json" "nothing" "settings.json created" \
    || ok "--dry-run writes no settings.json"
drop_home

# settings.json is the user's global config, so a broken run must never leave it
# altered. Three guarantees: the .bak holds exactly what was there before, a run
# that fails before the wiring step leaves the file byte-identical, and a failure
# after the write rolls it back.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
printf '{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"~/bin/mine.sh"}]}]}}' >"$SETT"
cp "$SETT" "$FAKE/original.json"
inst
is "the backup holds exactly the pre-install file" "" "$(diff "$FAKE/original.json" "$SETT.session-kit.bak")"
is "…and unrelated settings survive the merge" '"opus"' "$(jq -c .model "$SETT")"
is "…as does the user's own hook" 1 \
   "$(jq '[.hooks[]?[]?.hooks[]?.command | select(test("bin/mine"))] | length' "$SETT")"

# A run that changes nothing writes nothing. Without this, the second install would
# back up the already-wired file, and the copy of the pre-kit config would be gone
# after a single upgrade, which is exactly when someone might want it back.
inst; inst
is "…and it survives two more installs" "" "$(diff "$FAKE/original.json" "$SETT.session-kit.bak")"
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" bash "$ROOT/install.sh" 2>&1)
case "$OUT" in *"already wired"*"left untouched"*) ok "a no-op run says so and writes nothing" ;;
    *) bad "a no-op run says so and writes nothing" "already wired / left untouched" "$OUT";; esac

# Round trip: install then uninstall returns the file to what it was. Compared as
# parsed content, not bytes, because jq reformats what it rewrites.
inst --uninstall
is "install then uninstall restores the original content" "" \
   "$(diff <(jq -S . "$FAKE/original.json") <(jq -S . "$SETT"))"
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
      bash "$ROOT/install.sh" --uninstall 2>&1)
case "$OUT" in *"no kit hooks were wired"*) ok "a second uninstall writes nothing either" ;;
    *) bad "a second uninstall writes nothing either" "left untouched" "$OUT";; esac
drop_home

# A run that fails partway must not touch settings.json at all. An incomplete
# checkout forces that honestly: it refuses in preflight, long before the wiring
# step, which is the ordering this asserts.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"~/bin/mine.sh"}]}]}}' >"$SETT"
cp "$SETT" "$FAKE/original.json"
PARTIAL="$FAKE/partial"; mkdir -p "$PARTIAL"
( cd "$ROOT" && tar cf - --exclude .git . ) | ( cd "$PARTIAL" && tar xf - )
rm -f "$PARTIAL/core/sessions.sh"
CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
    bash "$PARTIAL/install.sh" >/dev/null 2>&1
is "a failed install leaves settings.json byte-identical" "" "$(diff "$FAKE/original.json" "$SETT")"
drop_home

# Another writer lands between our read and our write. Claude Code and other
# installers edit this file too, and without the check our merge, built from the
# older copy, would silently erase whatever they just added. Simulated by a copy
# whose merge step is followed by an edit from "somebody else".
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/bin/U.sh"}]}]}}' >"$SETT"
RACER="$FAKE/racer"; mkdir -p "$RACER"
( cd "$ROOT" && tar cf - --exclude .git . ) | ( cd "$RACER" && tar xf - )
python3 - "$RACER/install.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
# Right after the merge is staged, have someone else write the live file.
old = '''    local before after'''
new = '''    jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"~/bin/RACE.sh"}]}]' \\
        "$SETTINGS" >"$SETTINGS.race" && mv "$SETTINGS.race" "$SETTINGS"
    local before after'''
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new))
PY
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
      bash "$RACER/install.sh" 2>&1)
case "$OUT" in *"changed while it was being read"*) ok "a concurrent write is detected, not clobbered" ;;
    *) bad "a concurrent write is detected, not clobbered" "a changed-underneath message" "$OUT";; esac
is "…and the other writer's hook survives" 1 \
   "$(jq '[.hooks[]?[]?.hooks[]?.command | select(test("RACE[.]sh"))] | length' "$SETT")"
is "…while ours were not written" 0 "$(ours)"
is "…and no snapshot file is left behind" 0 \
   "$(find "$IPREFIX" -maxdepth 1 -name 'settings.json.snap.*' 2>/dev/null | grep -c . || true)"
drop_home

new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"~/bin/mine.sh"}]}]}}' >"$SETT"
cp "$SETT" "$FAKE/original.json"

# The rollback itself: a failure AFTER the write must restore the previous file.
# Forced with a copy whose wiring step is followed by a guaranteed failure, which
# is the ordering the real installer deliberately avoids.
BROKEN="$FAKE/broken"; mkdir -p "$BROKEN"
( cd "$ROOT" && tar cf - --exclude .git . ) | ( cd "$BROKEN" && tar xf - )
python3 - "$BROKEN/install.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'echo "wiring hooks"\nhooks_wire'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, old + '\nfalse'))
PY
CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
    bash "$BROKEN/install.sh" >/dev/null 2>&1
is "a failure after the write rolls settings.json back" "" "$(diff "$FAKE/original.json" "$SETT")"
drop_home

# A machine with no settings.json at all. Undoing a file we created means REMOVING
# it: restoring an empty one would leave behind something the machine never had.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"
inst
is "a fresh install with no settings.json wires all four" 4 "$(ours)"
[ -e "$SETT.session-kit.bak" ] && bad "…and writes no backup of a file that did not exist" "no backup" "backup written" \
    || ok "…and writes no backup of a file that did not exist"
rm -rf "$IPREFIX"
BROKEN2="$FAKE/broken2"; mkdir -p "$BROKEN2"
( cd "$ROOT" && tar cf - --exclude .git . ) | ( cd "$BROKEN2" && tar xf - )
python3 - "$BROKEN2/install.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'echo "wiring hooks"\nhooks_wire'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, old + '\nfalse'))
PY
CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
    bash "$BROKEN2/install.sh" >/dev/null 2>&1
[ -e "$SETT" ] && bad "a failed install removes the settings.json it created" "no file" "left behind" \
    || ok "a failed install removes the settings.json it created"
drop_home

# A settings.json that is ALREADY broken is caught in preflight, before anything is
# written. Without that check the run installs everything and then dies at the very
# last step with a bare parser error, which reads as "the kit is broken".
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"; mkdir -p "$IPREFIX"
printf '{"hooks": {oops not json' >"$SETT"
cp "$SETT" "$FAKE/original.json"
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
      bash "$ROOT/install.sh" 2>&1); RC=$?
is "an already-broken settings.json refuses the install" 1 "$RC"
case "$OUT" in *"not a valid JSON object"*) ok "…saying which file to fix" ;;
    *) bad "…saying which file to fix" "a clear message" "$OUT";; esac
is "…leaving it exactly as it was" "" "$(diff "$FAKE/original.json" "$SETT")"
[ -d "$IPREFIX/session-kit" ] && bad "…and installing nothing at all" "nothing" "kit tree created" \
    || ok "…and installing nothing at all"
drop_home

# Nothing may be left lying beside settings.json. The staging file is created there
# on purpose (a rename inside one directory is atomic, a cross-filesystem move is
# not), so it has to be gone by the end of both operations.
new_home
IPREFIX="$FAKE/.claude"; SETT="$IPREFIX/settings.json"
inst
is "install leaves no staging file behind" 0 \
   "$(find "$IPREFIX" -maxdepth 1 -name 'settings.json.tmp.*' 2>/dev/null | grep -c . || true)"
inst --uninstall
is "uninstall leaves no staging file behind" 0 \
   "$(find "$IPREFIX" -maxdepth 1 -name 'settings.json.tmp.*' 2>/dev/null | grep -c . || true)"
drop_home

# An incomplete checkout must refuse BEFORE copying, or a re-run (the upgrade path)
# would half-overwrite a working install.
new_home
IPREFIX="$FAKE/.claude"; PARTIAL="$FAKE/partial"
mkdir -p "$PARTIAL"
( cd "$ROOT" && tar cf - --exclude .git . ) | ( cd "$PARTIAL" && tar xf - )
rm -f "$PARTIAL/hooks/session-drift.sh"
OUT=$(CLAUDE_SESSION_KIT_NO_GATE=1 CLAUDE_SESSION_KIT_PREFIX="$IPREFIX" \
      bash "$PARTIAL/install.sh" 2>&1); RC=$?
is "an incomplete checkout refuses to install" 1 "$RC"
case "$OUT" in *session-drift.sh*full\ checkout*) ok "…naming the missing file" ;;
    *) bad "…naming the missing file" "the missing path" "$OUT";; esac
[ -e "$IPREFIX/session-kit" ] && bad "…having written nothing" "nothing" "kit tree created" \
    || ok "…having written nothing"
drop_home

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
