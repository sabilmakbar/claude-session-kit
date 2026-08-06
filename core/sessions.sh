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
# cs_verified_version.
CS_VERIFIED_VERSION="2.1.222"

_cs_home()         { printf '%s' "${CLAUDE_SESSION_KIT_HOME:-$HOME}"; }
_cs_projects_dir() { printf '%s/.claude/projects' "$(_cs_home)"; }
_cs_pids_dir()     { printf '%s/.claude/sessions' "$(_cs_home)"; }
_cs_state_dir()    { printf '%s/.claude/session-kit' "$(_cs_home)"; }

# The newest Claude Code version smoke.sh has PASSED against on THIS machine, falling
# back to the author's. Written by smoke.sh, never by this library: core/ stays
# read-only, which is the invariant everything else leans on.
#
# This is what makes the warning mean something. Comparing against a constant baked
# into the source warns forever after any update, even one already checked, and a
# warning that never clears is one people stop reading.
cs_verified_version() {
    local f="" v=""
    f="$(_cs_state_dir)/.verified"
    [ -r "$f" ] && v=$(head -1 "$f" 2>/dev/null | tr -d '[:space:]')
    [ -n "$v" ] || v="$CS_VERIFIED_VERSION"
    printf '%s' "$v"
}

cs_have_deps() { command -v jq >/dev/null 2>&1; }

# The session this script is running inside, if any.
cs_current_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

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
    local running="" verified=""
    running=$(cs_running_version)
    [ -z "$running" ] && return 0
    verified=$(cs_verified_version)
    [ "$running" = "$verified" ] && return 0
    printf 'claude-session-kit: running Claude Code %s, last verified against %s.\n' \
        "$running" "$verified" >&2
    printf '  Internals may have moved. Check with: bash tests/smoke.sh (from the kit root)\n' >&2
    return 0
}

# --- transcript access ------------------------------------------------------

# cs_transcript_path <session-id> -> path, or non-zero if not found.
cs_transcript_path() {
    local id="$1" f=""
    [ -n "$id" ] || return 1
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
            *"$lower"*) printf '%s\n' "$id";;
        esac
    done < <(cs_list)
}
