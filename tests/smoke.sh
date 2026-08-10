#!/usr/bin/env bash
# tests/smoke.sh — run the read-only accessors against the REAL ~/.claude.
#
# Run: bash tests/smoke.sh  /  zsh tests/smoke.sh
#
# This exists because run.sh cannot find a certain class of bug. Its fixtures encode
# what the author believed transcripts look like, so they can only ever confirm that
# belief; three bugs in one day lived in the gap between the belief and the file on
# disk. This suite has no fixtures — the data is whatever you actually have.
#
# The trade is that it cannot assert exact values, only invariants: it does not know
# what your sessions are called. So every check here is of the form "whatever the
# answer is, it must have this shape". Two rules keep it honest:
#
#   1. Raw entries are extracted by a DIFFERENT path than the resolver uses (tolerant
#      whole-file jq, no grep prefilter). Reusing the resolver to check the resolver
#      proves only that it agrees with itself.
#   2. Read-only. It sources core/ and never naming/, so no code that can write is
#      even loaded, and it verifies afterwards that nothing changed on disk.
#
# Never wire this into CI as a required check: it passes or skips depending on the
# machine it runs on, which is the point. run.sh is the gate; this is the reality check.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

FAILED=""; SUSPECT=""

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED="$FAILED$1|$2|$3
"; printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }
skip() { SKIP=$((SKIP+1)); printf '  skip %s (%s)\n' "$1" "$2"; }

# Sourcing core/ only. naming/rename.sh is deliberately absent: the one function that
# can write a transcript is never in scope, so a typo here cannot damage real data.
. "$ROOT/core/sessions.sh"

REPORT="$(_cs_state_dir)/last-failure.md"

# --- the shareable failure report -------------------------------------------
#
# This file is written to be pasted into an issue, so it is built to be safe to
# publish. That is a design constraint, not a courtesy: transcripts are full of
# real work. Titles name repositories, clients and projects, and the project
# directory names Claude Code uses are the full cwd with slashes swapped, so
# "-Users-<you>-Documents" carries a username and a directory layout.
#
# Two layers, in this order:
#
#   1. Construct from safe fields only. Nothing here reads a title or a path. A
#      session is identified by the first 8 characters of its id, which is enough
#      to find the file yourself and means nothing to anyone else.
#   2. Redact whatever got through. A backstop for fields added later by someone
#      who has not read this comment.
#
# Layer 1 is the real protection. Layer 2 exists because layer 1 depends on every
# future edit staying disciplined, and that is not a safe thing to depend on.
#
# The console output is NOT redacted, deliberately. That is your terminal, and
# seeing the offending title is what makes a failure debuggable. Only the file
# meant for sharing is stripped.
redact() {
    sed -e "s|$HOME|~|g" -e "s|$(id -un 2>/dev/null || echo __nouser__)|USER|g"
}

write_report() {
    local running="" verified=""
    running=$(cs_running_version 2>/dev/null)
    verified=$(cs_verified_version 2>/dev/null)
    mkdir -p "$(_cs_state_dir)" 2>/dev/null || return 1
    {
        echo "# claude-session-kit: smoke failure"
        echo
        echo "The read-only accessors stopped agreeing with the real transcript layout."
        echo "No titles or paths are included; sessions appear as the first 8 characters"
        echo "of their id so you can find them locally."
        echo
        echo '## Environment'
        echo
        printf -- '- claude code running: `%s`\n' "${running:-unknown}"
        printf -- '- last verified against: `%s`\n' "${verified:-unknown}"
        printf -- '- kit verified for: `%s`\n' "$CS_VERIFIED_VERSION"
        printf -- '- os: `%s`\n' "$(uname -sr 2>/dev/null)"
        printf -- '- bash: `%s`\n' "$(bash --version 2>/dev/null | head -1 | sed 's/.*version //;s/ .*//')"
        printf -- '- zsh: `%s`\n' "$(zsh --version 2>/dev/null | awk '{print $2}')"
        printf -- '- jq: `%s`\n' "$(jq --version 2>/dev/null)"
        printf -- '- transcripts scanned: `%s`\n' "$N"
        echo
        echo '## Failed checks'
        echo
        printf '%s' "$FAILED" | while IFS='|' read -r nm exp act; do
            [ -n "$nm" ] || continue
            printf -- '- **%s**: expected `%s`, got `%s`\n' "$nm" "$exp" "$act"
        done
        if [ -n "$SUSPECT" ]; then
            echo
            echo '## Sessions involved'
            echo
            printf '%s' "$SUSPECT" | sort -u | while IFS= read -r s; do
                [ -n "$s" ] && printf -- '- `%s`\n' "$s"
            done
        fi
        echo
        echo '## Reproduce'
        echo
        echo '```'
        echo 'bash tests/smoke.sh'
        echo '```'
    } 2>/dev/null | redact >"$REPORT" 2>/dev/null
}

# --- preconditions ----------------------------------------------------------
#
# Skipping is a pass, not a failure. A CI runner has no ~/.claude and never will.

# --report prints the last recorded failure and exits.
#
# Separate from running the checks on purpose. Auto-filing was considered and
# rejected: gh is not on a hook's PATH (/opt/homebrew/bin), so it would silently do
# nothing; the hook fires every session start, so a persistent failure would file a
# duplicate every time; and anything leaving the machine should be a deliberate act,
# not a side effect of a background process.
if [ "${1:-}" = "--report" ]; then
    [ -r "$REPORT" ] || { echo "smoke: no failure recorded"; exit 0; }
    cat "$REPORT"
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "smoke: jq not found — nothing to check"; exit 0; }

PROJECTS="$(_cs_projects_dir)"
[ -d "$PROJECTS" ] || { echo "smoke: no $PROJECTS — skipping (this is fine on CI)"; exit 0; }

# A session transcript is <session-uuid>.jsonl directly inside a project dir. Keying on
# the UUID matters: subagent transcripts live a level deeper as agent-*.jsonl, and a
# plain depth count would read those 8-on-this-machine as misplaced sessions.
CS_UUID_RE='/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl$'

FILES=$(find "$PROJECTS" -mindepth 2 -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null | grep -E "$CS_UUID_RE")
N=$(printf '%s\n' "$FILES" | grep -c .)
ANYWHERE=$(find "$PROJECTS" -name '*.jsonl' -type f 2>/dev/null | grep -cE "$CS_UUID_RE")

# Genuinely nothing here — a CI runner, or a fresh machine. Skipping is correct.
#
# Note what is NOT skipped: transcripts existing but not where we look. That is a
# layout change, and reporting it as "nothing to check" would turn total breakage into
# a clean exit 0. The difference between "no data" and "we can no longer find the data"
# is the whole point of this suite, so it is asserted below rather than assumed here.
[ "$ANYWHERE" -gt 0 ] || { echo "smoke: no transcripts under $PROJECTS — skipping (fine on CI)"; exit 0; }

printf 'smoke: %d transcripts\n\n' "$N"

# --- independent extraction -------------------------------------------------
#
# Tolerant, whole-file, no grep prefilter — on purpose. `fromjson?` drops lines that
# do not parse instead of aborting, so one malformed line cannot hide every entry
# behind it.
#
# One pass, not three. These files run to megabytes, and scanning each one once per
# question does not scale with a session history. Output is tagged so a single read
# answers all three: `!` for a line that is not JSON, `<type>\t<value>` for a title.
scan() {  # <file> -> tagged lines
    jq -Rr '
        . as $line
        | try (fromjson
               | select(.type=="custom-title" or .type=="ai-title")
               | [.type, (.customTitle // .aiTitle // empty)]
               | select(.[1] != null and (.[1] | type) == "string")
               | .[0] + "\t" + (.[1] | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; ""))
               | select(endswith("\t") | not))
          catch "!"' "$1" 2>/dev/null
}

# The invariant that catches the fragment bug: whatever the resolver returns must be
# one of the entries actually in the file, not a piece of one. WHICH entry it picks is
# the resolver's business and run.sh covers it; that it returns a whole one is
# checkable without knowing anything about your data.
#
# The resolved value is compared verbatim, never re-normalised here. Collapsing it
# first would flatten a multi-line value and let a resolver that stopped collapsing
# pass anyway — the test would hide the exact regression it exists to catch.
check_whole_entry() {  # <file> <id> <type> <resolved> <entries>
    local got="$4"
    [ -n "$5" ] || return 0
    checked_titles=$((checked_titles+1))
    printf '%s\n' "$5" | grep -Fxq "$got" && return 0
    notanentry=$((notanentry+1))
    # The id goes to the report; the title stays on your terminal only.
    SUSPECT="$SUSPECT${2:0:8}
"
    printf '     %s: %s resolved to a value that is not an entry in the file\n' "${2:0:8}" "$3"
    printf '     got: %s\n' "$got"
}

# --- checks -----------------------------------------------------------------

printf 'layout\n'

# Every one of these three exists because the kit failed them SILENTLY. Each check
# below turns a "0 failed" into a real failure, and each is a way the data can move
# without any invariant about the data itself being violated.

# 1. Transcripts must be where we look. If some are findable at another depth, the
#    layout moved and every accessor is now blind.
is "every transcript is at the expected depth" "$ANYWHERE" "$N"

# 2. The version guard reads its version from the pid-files. If that schema moves, the
#    guard silently reads nothing, stops warning, and the hook exits early — the entire
#    early-warning system switches off without saying so. It cannot detect its own
#    blindness, so this does it from outside.
pidfiles=$(find "$(_cs_pids_dir)" -mindepth 1 -maxdepth 1 -name '*.json' -type f 2>/dev/null | grep -c .)
if [ "$pidfiles" -gt 0 ]; then
    [ -n "$(cs_running_version)" ] \
        && ok "a Claude Code version is readable from the pid-files" \
        || bad "a Claude Code version is readable from the pid-files" \
               "a version" "none from $pidfiles pid-files; schema moved"
else
    skip "pid-file schema check" "no pid-files present"
fi

printf '\ntranscripts\n'

unparsed=0; noname=0; multiline=0; notanentry=0; unresolved_path=0; checked_titles=0; titled=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    id=$(basename "$file" .jsonl)

    # Every transcript must be findable from its own id. This is the lookup every
    # other feature is built on, and it is the one most likely to break on a layout
    # change (an extra nesting level, a renamed directory).
    found=$(cs_transcript_path "$id" 2>/dev/null)
    [ "$found" = "$file" ] || { unresolved_path=$((unresolved_path+1)); continue; }

    tagged=$(scan "$file")
    printf '%s\n' "$tagged" | grep -qx '!' && unparsed=$((unparsed+1))
    printf '%s\n' "$tagged" | grep -qE '^(custom-title|ai-title)	' && titled=$((titled+1))

    # A name is always required. Falling all the way through to the short id is a
    # legitimate answer; empty never is, because callers print it.
    name=$(cs_resolve_name "$id" 2>/dev/null)
    [ -n "$name" ] || noname=$((noname+1))
    case "$name" in *$'\n'*) multiline=$((multiline+1));; esac

    check_whole_entry "$file" "$id" custom-title "$(cs_custom_title "$file")" \
        "$(printf '%s\n' "$tagged" | sed -n 's/^custom-title\t//p')"
    check_whole_entry "$file" "$id" ai-title "$(cs_ai_title "$file")" \
        "$(printf '%s\n' "$tagged" | sed -n 's/^ai-title\t//p')"
done <<EOF
$FILES
EOF

is "every transcript is findable by its own id"        0 "$unresolved_path"
is "every transcript parses as JSONL"                  0 "$unparsed"
is "every session resolves to a non-empty name"        0 "$noname"
is "no resolved name spans multiple lines"             0 "$multiline"
is "every resolved title is a whole entry in the file" 0 "$notanentry"
[ "$checked_titles" -gt 0 ] \
    && printf '       (%d title entries cross-checked)\n' "$checked_titles" \
    || skip "title cross-check" "no title entries in the sample"

# 3. If Claude Code renames the title entry types, every accessor still returns a name —
#    it just falls through to a worse one. Nothing above fires, because "a name was
#    produced" stays true. The only observable signal is that the types vanish
#    everywhere at once.
#
#    Thresholded: a handful of title-less sessions is ordinary, so this only concludes
#    when zero out of many is implausible rather than merely unlucky.
TITLE_MIN=${SMOKE_TITLE_MIN:-5}
if [ "$N" -ge "$TITLE_MIN" ]; then
    [ "$titled" -gt 0 ] \
        && ok "known title entry types still appear" \
        || bad "known title entry types still appear" \
               "at least 1 of $N" "0; custom-title/ai-title renamed or removed"
else
    skip "title-type check" "$N transcripts, need $TITLE_MIN to conclude"
fi

printf '\nliveness\n'

# cs_is_live must agree with the operating system, not just with the pid-file. A
# stale registration reading as live is the failure that matters: it would let a
# caller treat a dead session as one it must not touch, or the reverse.
live=0; wrong=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    id=$(basename "$file" .jsonl)
    if cs_is_live "$id" 2>/dev/null; then
        live=$((live+1))
        pf=$(cs_pid_file "$id" 2>/dev/null) || { wrong=$((wrong+1)); continue; }
        pid=$(jq -r '.pid // empty' "$pf" 2>/dev/null)
        kill -0 "$pid" 2>/dev/null || wrong=$((wrong+1))
    fi
done <<EOF
$FILES
EOF

is "every session reported live has a running process" 0 "$wrong"
printf '       (%d live in the sample)\n' "$live"

# The current session, if we are inside one, is the strongest single case available:
# it is known to exist and known to be live.
#
# Only meaningful against the real home. With CLAUDE_SESSION_KIT_HOME redirected the
# id names a session that lives somewhere else, so these would fail on the redirect
# rather than on anything about the kit.
cur=$(cs_current_id)
if [ -n "${CLAUDE_SESSION_KIT_HOME:-}" ]; then
    skip "current-session checks" "CLAUDE_SESSION_KIT_HOME is redirected"
elif [ -n "$cur" ]; then
    cs_transcript_path "$cur" >/dev/null 2>&1
    is "the current session has a transcript" 0 $?
    [ -n "$(cs_resolve_name "$cur" 2>/dev/null)" ] \
        && ok "the current session resolves to a name" \
        || bad "the current session resolves to a name" "non-empty" "(empty)"
    hits=$(cs_find "${cur:0:8}" 2>/dev/null | grep -Fxc "$cur")
    is "cs_find matches the current session by short id" 1 "$hits"
else
    skip "current-session checks" "CLAUDE_CODE_SESSION_ID unset"
fi

printf '\nread-only\n'

# Proof by measurement, not by inspection. Only dead sessions are measured: a live
# session is being appended to by its own process while this runs, so a size change
# there would prove nothing.
changed=0; watched=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    id=$(basename "$file" .jsonl)
    cs_is_live "$id" 2>/dev/null && continue
    watched=$((watched+1))
    before=$(wc -c <"$file")
    cs_resolve_name "$id" >/dev/null 2>&1
    cs_custom_title "$file" >/dev/null 2>&1
    cs_ai_title "$file" >/dev/null 2>&1
    cs_first_prompt "$file" >/dev/null 2>&1
    [ "$(wc -c <"$file")" = "$before" ] || changed=$((changed+1))
done <<EOF
$FILES
EOF

is "reading a dead session never changes its transcript" 0 "$changed"
printf '       (%d dead transcripts watched)\n' "$watched"

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"

# The one write in this file, and the only reason it is not purely read-only.
#
# Recording the version that PASSED is what lets the version guard go quiet again.
# Without it the guard compares against a constant in the source and warns after
# every update forever, including ones already checked. On failure nothing is
# written, so the warning keeps appearing until someone looks — the absent write
# IS the failure report, which is why no marker file is needed.
if [ "$FAIL" -eq 0 ]; then
    running=$(cs_running_version)
    if [ -n "$running" ]; then
        mkdir -p "$(_cs_state_dir)" 2>/dev/null \
            && printf '%s\n' "$running" >"$(_cs_state_dir)/.verified" 2>/dev/null \
            && printf 'verified against Claude Code %s\n' "$running"
    fi
    # A stale failure report sitting next to a passing run reads as a live problem.
    rm -f "$REPORT" 2>/dev/null
else
    write_report && printf '\nreport written: %s\n  paste it with: bash tests/smoke.sh --report\n' "$REPORT"
fi

[ "$FAIL" -eq 0 ]
