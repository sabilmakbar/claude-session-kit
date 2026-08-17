#!/usr/bin/env bash
# core/sessions.sh — read-only session resolver.
#
# Every accessor to Claude Code internals lives here, behind a version guard, and
# fails quiet: on an unrecognised layout a function returns empty and non-zero
# rather than erroring, so a Claude Code update degrades the kit to "no data".
#
# Storage layers this reads (all undocumented internals, verified on 2.1.220–2.1.222):
#   ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl   transcript + title entries
#   ~/.claude/sessions/<pid>.json                         per-process registration
#
# VS Code's state.vscdb is deliberately never read or written: it only caches the
# rendered tab, and the tab itself resolves from the transcript.
#
# Source it; do not execute it. The shebang is a dialect hint, not enforcement — a
# sourced file runs under the caller's shell. bash and zsh both work; keep it that way.

# The version the AUTHOR tested against. A floor, not the whole answer — see
# cs_verified_version. Exported API (smoke.sh and export.sh read it directly); the
# long prefix marks kit infrastructure — user knobs alone wear CS_*.
CLAUDE_SESSION_KIT_VERIFIED_VERSION="2.1.222"

_cs_home()         { printf '%s' "${CLAUDE_SESSION_KIT_HOME:-$HOME}"; }
_cs_projects_dir() { printf '%s/.claude/projects' "$(_cs_home)"; }
_cs_pids_dir()     { printf '%s/.claude/sessions' "$(_cs_home)"; }
_cs_state_dir()    { printf '%s/.claude/session-kit' "$(_cs_home)"; }

# Every Claude Code version smoke.sh has PASSED against on THIS machine, one per
# line, oldest first. Written by smoke.sh, never by this library: core/ stays
# read-only, which is the invariant everything else leans on. Empty output means
# nothing has been recorded yet, and every caller falls back to the author's
# constant.
#
# This is what makes the warning mean something. Comparing against a constant baked
# into the source warns forever after any update, even one already checked, and a
# warning that never clears is one people stop reading.
#
# A LIST, not one value. It held a single version until a machine running several
# sessions at once showed why that fails: a smoke run started while only OLDER
# sessions were open overwrote a newer recorded pass with an older version, so the
# record went backwards and the suite re-ran for a version it had already cleared.
# A list cannot go backwards. It is also honest in a way a bare low-to-high range is
# not, because passing on 2.1.222 and 2.1.226 says nothing about 2.1.224: membership
# is exact, and only the display collapses to a span.
#
# The parse is deliberately forgiving about layout and strict about content. It
# accepts the single-line file older installs left behind, and it drops anything
# that is not dotted digits rather than letting a stray line become a version.
_cs_verified_list() {
    local f=""
    f="$(_cs_state_dir)/.verified"
    [ -r "$f" ] || return 0
    tr '[:space:]' '\n' <"$f" 2>/dev/null \
        | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V -u
}

# The newest version recorded here, falling back to the author's.
cs_verified_version() {
    local v=""
    v=$(_cs_verified_list | tail -1)
    [ -n "$v" ] || v="$CLAUDE_SESSION_KIT_VERIFIED_VERSION"
    printf '%s' "$v"
}

# Has this exact version passed here? With nothing recorded, the author's constant
# stands in, so a fresh checkout behaves as it always did.
cs_version_verified() {  # <version> -> 0 if recorded
    local list=""
    list=$(_cs_verified_list)
    [ -n "$list" ] || list="$CLAUDE_SESSION_KIT_VERIFIED_VERSION"
    printf '%s\n' "$list" | grep -qxF "$1"
}

# Human-facing summary of what has passed here: one version, or the span and how
# many points inside it were actually tested. The count is what keeps the span from
# reading as a claim about every version between the ends.
cs_verified_span() {
    local list="" lo="" hi="" n=""
    list=$(_cs_verified_list)
    [ -n "$list" ] || { printf '%s' "$CLAUDE_SESSION_KIT_VERIFIED_VERSION"; return; }
    lo=$(printf '%s\n' "$list" | head -1)
    hi=$(printf '%s\n' "$list" | tail -1)
    n=$(printf '%s\n' "$list" | wc -l | tr -d '[:space:]')
    if [ "$lo" = "$hi" ]; then printf '%s' "$hi"
    else printf '%s to %s (%s versions)' "$lo" "$hi" "$n"; fi
}

cs_have_deps() { command -v jq >/dev/null 2>&1; }

# --- the degraded notice ----------------------------------------------------
#
# The kit's normal state is silence, which is also exactly what it looks like when it
# is broken. Both known breakages are invisible: without jq all four hooks exit 0 and
# print nothing, and a self-check that FAILED after a Claude Code update only ever
# reaches you through cs_version_guard, which fires from the commands you type and
# from no hook at all. Someone who uses the kit through its hooks is never told.
#
# So this is the one channel that says the kit is not working. It is separate from the
# version guard on purpose: the guard warns that a version is UNVERIFIED, which is a
# caution, while this reports that the kit is DEGRADED right now, which is a fault.
#
# It must not use jq, since a missing jq is half of what it reports.

# What is wrong, as "<key> <sentence>", or non-zero when the kit is healthy. The key
# names the fault so a jq notice today cannot suppress a failed-check notice today.
cs_degraded_reason() {
    command -v jq >/dev/null 2>&1 || {
        printf 'jq jq is missing, so the kit is doing nothing at all. Install it (brew install jq) and it picks straight back up.'
        return 0; }
    [ -r "$(_cs_state_dir)/last-failure.md" ] && {
        printf 'selfcheck its last self-check failed, so it may be reading Claude Code wrongly. See what moved: bash %s/tests/smoke.sh --report' \
            "$(_cs_state_dir)"
        return 0; }
    return 1
}

# One notice per fault per day. mkdir is the throttle because it is atomic on every
# POSIX filesystem: all three prompt hooks race on the same marker and exactly one
# wins, so a fault is reported once and not three times. Markers from other days are
# swept by the winner, so the directory cannot grow.
_cs_notice_once() {  # <key> -> 0 if this caller should print
    local d="" today=""
    today=$(date +%F 2>/dev/null) || return 1
    d="$(_cs_state_dir)/.notices"
    mkdir -p "$d" 2>/dev/null || return 1
    mkdir "$d/$1-$today" 2>/dev/null || return 1
    find "$d" -mindepth 1 -maxdepth 1 -type d ! -name "*-$today" -exec rm -rf {} + 2>/dev/null
    return 0
}

# Prints one line to stdout, which for a UserPromptSubmit hook is how it reaches the
# session. Silent when healthy, silent when already reported today, and it stops on
# its own: the jq fault clears when jq returns, and the self-check fault clears when
# smoke.sh next passes and removes its report.
cs_notice_degraded() {
    local line="" key=""
    line=$(cs_degraded_reason) || return 0
    key=${line%% *}
    _cs_notice_once "$key" || return 0
    printf 'claude-session-kit: %s\n' "${line#* }"
}

# Tunable knobs: KEY=value lines in $(_cs_state_dir)/config — the same place
# .verified lives, so one file serves hooks, skills, and a dev checkout alike, and
# the tests' fake HOMEs isolate it for free. Parsed strictly and NEVER sourced: a
# stray line in a user-edited file must not become code inside a hook. Values must
# be whole numbers; anything else falls back to the caller's default, silently —
# hooks fail open. Precedence is env > file > default, with the env half at the
# call site: VAR="${VAR:-$(cs_conf VAR default)}" (indirect expansion is bash-only
# and this file must load under zsh too).
cs_conf() {  # <key> <default> -> value
    local k="$1" d="$2" f="" v=""
    f="$(_cs_state_dir)/config"
    [ -r "$f" ] || { printf '%s' "$d"; return; }
    v=$(grep -E "^${k}=" "$f" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]')
    case "$v" in ''|*[!0-9]*) v="$d";; esac
    printf '%s' "$v"
}

# The session this script is running inside, if any.
cs_current_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# cwd -> project dir name. Claude Code replaces every "/" with "-". (Removed once as
# dead code; reinstated when handoff import became its first real caller.)
cs_encode_cwd() { printf '%s' "${1//\//-}"; }

# Listing goes through find, never shell globs: zsh treats an unmatched glob as a fatal
# error where bash expands it to a literal, which silently broke every listing and
# lookup for zsh users while the bash-only suite stayed green. find matches both.
_cs_find_files() {  # <dir> <mindepth> <maxdepth> <name-pattern>
    find "$1" -mindepth "$2" -maxdepth "$3" -name "$4" -type f 2>/dev/null
}

# Highest version seen across live pid-files. Empty if none are running.
cs_running_version() {
    local f="" v=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        v=$(jq -r '.version // empty' "$f" 2>/dev/null)
        [ -n "$v" ] && printf '%s\n' "$v"
    done < <(_cs_find_files "$(_cs_pids_dir)" 1 1 '*.json') | sort -V | tail -1
}

# Warn once per shell if the running version is not the one this kit was verified
# against. Never blocks: an unverified version is a caution, not an error.
#
# The warning names smoke.sh because this is the only moment anything tells you to run
# it. Nothing else triggers it: CI cannot (a runner has no ~/.claude, so it always
# skips) and install.sh runs run.sh instead. A warning with no next step gets ignored,
# and "internals may have moved" is not answerable by reading it — only by checking the
# accessors against real transcripts, which is exactly what smoke.sh does.
cs_version_guard() {
    [ -n "${_CS_VERSION_WARNED:-}" ] && return 0
    _CS_VERSION_WARNED=1
    local running=""
    running=$(cs_running_version)
    [ -z "$running" ] && return 0
    cs_version_verified "$running" && return 0
    printf 'claude-session-kit: running Claude Code %s, verified here against %s.\n' \
        "$running" "$(cs_verified_span)" >&2
    printf '  Internals may have moved. Check with: bash tests/smoke.sh (from the kit root)\n' >&2
    return 0
}

# --- transcript access ------------------------------------------------------

# cs_transcript_path <session-id> -> path, or non-zero if not found.
#
# Glob metacharacters are refused because the id is handed to `find -name`, which
# treats it as a pattern: `cs_transcript_path '*'` otherwise matches the first
# transcript on the machine and reports it as that session. A lookup must not be able
# to answer with a session nobody asked for.
cs_transcript_path() {
    local id="$1" f=""
    [ -n "$id" ] || return 1
    case "$id" in *[\*\?\[\]]*) return 1;; esac
    f=$(_cs_find_files "$(_cs_projects_dir)" 2 2 "$id.jsonl" | head -1)
    [ -n "$f" ] || return 1
    printf '%s' "$f"
}

# _cs_last_of_type <file> <type> <field> -> last non-empty value of that type.
#
# grep pre-filters candidate lines; jq re-checks .type, so a user message quoting the
# marker string is filtered out. Unusable entries are dropped rather than allowed to
# mask a good earlier name — both empty (/rename with no argument) and multi-line
# (pasted free text) values occur in real transcripts. Whitespace is collapsed inside
# jq because this pipeline is line-oriented: a title containing newlines would make
# `tail -1` return the last line *of that title* rather than the last title.
_cs_last_of_type() {
    local file="$1" type="$2" field="$3"
    [ -f "$file" ] || return 1
    grep -F "\"type\":\"$type\"" "$file" 2>/dev/null \
        | jq -r --arg t "$type" --arg f "$field" '
            select(.type==$t) | .[$f]? // empty
            | select(type=="string")
            | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "")
            | select(. != "")' 2>/dev/null \
        | tail -1
}

# Titles are selected by entry TYPE, never by file order. The AI titler re-emits
# an ai-title after every custom-title, so "last title line" would discard the
# user's rename on the next message.
cs_custom_title() { _cs_last_of_type "$1" custom-title customTitle; }
cs_ai_title()     { _cs_last_of_type "$1" ai-title     aiTitle; }

# First user message, trimmed to one line — the weakest real name.
cs_first_prompt() {
    local file="$1"
    [ -f "$file" ] || return 1
    jq -r 'select(.type=="user") | .message.content? // .content? // empty
           | if type=="array" then (map(select(.type=="text").text) | join(" ")) else . end
           | select(type=="string") | select(length>0)' "$file" 2>/dev/null \
        | head -1 | tr '\n' ' ' | sed 's/  */ /g; s/ $//'
}

# --- pid-file access --------------------------------------------------------

# cs_pid_file <session-id> -> path of the registration file, if one exists.
cs_pid_file() {
    local id="$1" f="" hit=""
    [ -n "$id" ] || return 1
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ "$(jq -r '.sessionId // empty' "$f" 2>/dev/null)" = "$id" ] && { hit="$f"; break; }
    done < <(_cs_find_files "$(_cs_pids_dir)" 1 1 '*.json')
    [ -n "$hit" ] || return 1
    printf '%s' "$hit"
}

# True when a registration exists AND its process is actually alive. Pid-files
# are pruned by Claude Code but a stale one must never read as live.
cs_is_live() {
    local f="" pid=""
    f=$(cs_pid_file "$1") || return 1
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# --- name resolution --------------------------------------------------------

# cs_resolve_name <session-id> -> best-known display name.
#
# Precedence, highest first:
#   1. transcript last custom-title          (durable; survives restart and import)
#   2. pid-file name with nameSource absent  (explicit, but ephemeral)
#   3. transcript last ai-title              (pinned to the opening message)
#   4. first user message
#   5. pid-file name with derived/auto       (documents-41; uninformative, collides)
#   6. short id
#
# custom-title outranks even an explicit pid-file name: /rename writes both at once so
# they normally agree, but the kit writes custom-title alone, making it the newer value
# whenever the two differ. Ranking the pid-file first let a stale name shadow a fresh
# rename while the tab, which reads custom-title, showed the new one.
cs_resolve_name() {
    local id="$1" pf="" name="" src="" tr="" v=""
    [ -n "$id" ] || return 1
    cs_version_guard

    tr=$(cs_transcript_path "$id") || tr=""
    if pf=$(cs_pid_file "$id"); then
        name=$(jq -r '.name // empty'       "$pf" 2>/dev/null)
        src=$( jq -r '.nameSource // empty' "$pf" 2>/dev/null)
    fi

    if [ -n "$tr" ]; then
        v=$(cs_custom_title "$tr"); [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    fi

    [ -n "$name" ] && [ -z "$src" ] && { printf '%s' "$name"; return 0; }

    if [ -n "$tr" ]; then
        v=$(cs_ai_title     "$tr"); [ -n "$v" ] && { printf '%s' "$v"; return 0; }
        v=$(cs_first_prompt "$tr"); [ -n "$v" ] && { printf '%s' "${v:0:80}"; return 0; }
    fi

    [ -n "$name" ] && { printf '%s' "$name"; return 0; }

    printf '%s' "${id:0:8}"
}

# --- listing and lookup -----------------------------------------------------

# cs_list -> TSV: session-id, live flag, resolved name.
cs_list() {
    local f="" id=""
    cs_version_guard
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        id=$(basename "$f" .jsonl)
        printf '%s\t%s\t%s\n' "$id" "$(cs_is_live "$id" && echo live || echo dead)" "$(cs_resolve_name "$id")"
    done < <(_cs_find_files "$(_cs_projects_dir)" 2 2 '*.jsonl')
}

# cs_find <ref> -> matching session ids, one per line.
#
# Accepts a full UUID, a short-id prefix, or a case-insensitive name substring. Prints
# every match; callers needing exactly one must check the count, because derived names
# genuinely collide (two concurrent sessions have both been observed as documents-7c).
#
# Ids are matched from filenames and win outright; names are searched only when no id
# matched. Resolving a name costs a pid-file scan and several jq calls per session, so
# the old single pass through cs_list paid that for every session on the machine and
# then discarded it on the id branch. An id fragment that also appears inside someone's
# title is not a real case — titles are sentences.
cs_find() {
    local ref="$1" id="" live="" name="" f="" hit="" lower=""
    [ -n "$ref" ] || return 1
    if cs_transcript_path "$ref" >/dev/null 2>&1; then printf '%s\n' "$ref"; return 0; fi

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        id=$(basename "$f" .jsonl)
        case "$id" in "$ref"*) printf '%s\n' "$id"; hit=1;; esac
    done < <(_cs_find_files "$(_cs_projects_dir)" 2 2 '*.jsonl')
    [ -n "$hit" ] && return 0

    lower=$(printf '%s' "$ref" | tr '[:upper:]' '[:lower:]')
    while IFS=$'\t' read -r id live name; do
        case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
            *"$lower"*) printf '%s\n' "$id"; hit=1;;
        esac
    done < <(cs_list)
    [ -n "$hit" ] && return 0

    # Stage 4, and it exists because two of this kit's own rules pull against each
    # other. The rename skill requires a title to name the ARC of the work rather than
    # either endpoint, which is right for a title and makes it a poor routing key: the
    # better the name describes the whole arc, the less likely any word from a specific
    # question appears in it. Routing then returns nothing exactly when sessions are
    # well named, which is the state the kit is trying to produce (issue #20, where a
    # live, well-named session was missed by both `cs_find dev-pipeline` and
    # `cs_find plugin`).
    #
    # So when the NAME matches nothing, fall back to what the session actually holds:
    # the directory it runs in and the user's own words. Neither is subject to the
    # arc-naming rule. Ordered after the name search and skipped entirely when that
    # succeeded, so nothing about the existing behaviour changes; this only rescues the
    # empty result.
    cs_have_deps || return 0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        id=$(basename "$f" .jsonl)
        _cs_content_match "$lower" "$f" && printf '%s\n' "$id"
    done < <(_cs_find_files "$(_cs_projects_dir)" 2 2 '*.jsonl')
    # Explicit, because the loop's last content probe decides the exit status otherwise
    # and a total miss would start returning 1. Callers read stdout and several run
    # under `set -e`, so a silent status change here would abort them on an empty result.
    return 0
}

# Does this session's own content mention the term? Two sources, both outside the
# arc-naming rule: the cwd, which Claude Code encodes into the project directory name,
# and the prose of the conversation.
#
# `text` blocks only, from either speaker. That filter is the whole design:
#
#   - tool_result blocks are excluded, and they are the reason a naive grep of the raw
#     file is wrong. They carry role "user" in this format while holding command output,
#     file contents and paths, so raw matching would find every session that ever ran
#     `grep` on the word.
#   - tool_use blocks are excluded for the same reason, from the other side.
#   - thinking blocks are excluded: private reasoning is not what the session was about.
#   - the assistant's own text IS included, on evidence. Sampling a real 8000-entry
#     transcript found 10 user text blocks against 26 assistant ones in the same window;
#     user turns run to "yes" and "do it", so the vocabulary a routing query would use
#     mostly sits in the replies. Restricting to user turns finds almost nothing.
#
# The tail is bounded at 400 entries because this runs once per session on the machine
# and transcripts reach tens of thousands. The first prompt is added back explicitly: it
# is the one old entry that reliably says what the session was FOR.
_cs_content_match() {  # <lower-term> <transcript-path>
    local term="$1" f="$2" dir=""
    dir=$(basename "$(dirname "$f")" | tr '[:upper:]' '[:lower:]')
    case "$dir" in *"$term"*) return 0;; esac
    {
        cs_first_prompt "$f" 2>/dev/null
        tail -n 400 "$f" 2>/dev/null \
            | jq -r '.message.content
                     | if type == "array" then [.[]? | select(.type == "text") | .text] | join(" ")
                       elif type == "string" then .
                       else empty end' 2>/dev/null
    } | tr '[:upper:]' '[:lower:]' | grep -qF -- "$term"
}
