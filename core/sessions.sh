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
# Source it; do not execute it.

CS_VERIFIED_VERSION="2.1.222"

_cs_home()         { printf '%s' "${CLAUDE_SESSION_KIT_HOME:-$HOME}"; }
_cs_projects_dir() { printf '%s/.claude/projects' "$(_cs_home)"; }
_cs_pids_dir()     { printf '%s/.claude/sessions' "$(_cs_home)"; }

cs_have_deps() { command -v jq >/dev/null 2>&1; }

# The session this script is running inside, if any.
cs_current_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# cwd -> project dir name. Claude Code replaces every "/" with "-".
cs_encode_cwd() { printf '%s' "${1//\//-}"; }

# Highest version seen across live pid-files. Empty if none are running.
cs_running_version() {
    local f v
    for f in "$(_cs_pids_dir)"/*.json; do
        [ -f "$f" ] || continue
        v=$(jq -r '.version // empty' "$f" 2>/dev/null) && [ -n "$v" ] && printf '%s\n' "$v"
    done | sort -V | tail -1
}

# Warn once per shell if the running version is not the one this kit was verified
# against. Never blocks: an unverified version is a caution, not an error.
cs_version_guard() {
    [ -n "${_CS_VERSION_WARNED:-}" ] && return 0
    _CS_VERSION_WARNED=1
    local running
    running=$(cs_running_version)
    [ -z "$running" ] && return 0
    [ "$running" = "$CS_VERIFIED_VERSION" ] && return 0
    printf 'claude-session-kit: running Claude Code %s, verified against %s; internals may have moved\n' \
        "$running" "$CS_VERIFIED_VERSION" >&2
    return 0
}

# --- transcript access ------------------------------------------------------

# cs_transcript_path <session-id> -> path, or non-zero if not found.
cs_transcript_path() {
    local id="$1" f
    [ -n "$id" ] || return 1
    for f in "$(_cs_projects_dir)"/*/"$id".jsonl; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# _cs_last_of_type <file> <type> <field> -> last non-empty value of that type.
#
# grep pre-filters so we only parse candidate lines, then jq re-checks .type —
# a user message quoting the marker string parses fine and is filtered out.
#
# Walks entries newest-first and returns the first usable one, so an unusable
# entry never masks a good earlier name. Two kinds occur in real transcripts:
#
#   empty      — /rename with no argument leaves one behind
#   multi-line — /rename accepts pasted free text verbatim
#
# Multi-line values are the subtle one: this pipeline is line-oriented, so a
# title containing newlines would otherwise make `tail -1` return the last line
# *of that title* rather than the last title. Whitespace is collapsed inside jq
# so every entry emits exactly one line, which is also all a tab or picker can
# render anyway.
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
    local id="$1" f
    [ -n "$id" ] || return 1
    for f in "$(_cs_pids_dir)"/*.json; do
        [ -f "$f" ] || continue
        [ "$(jq -r '.sessionId // empty' "$f" 2>/dev/null)" = "$id" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# True when a registration exists AND its process is actually alive. Pid-files
# are pruned by Claude Code but a stale one must never read as live.
cs_is_live() {
    local f pid
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
# custom-title outranks even an explicit pid-file name. /rename writes both at
# once so they normally agree, but the kit can write custom-title on its own —
# which makes it the newer value whenever the two differ. Ranking the pid-file
# first would let a stale name shadow a fresh rename, while the tab (which reads
# custom-title) showed the new one.
#
# A derived pid-file name ranks below both transcript titles and the first
# prompt: "documents-41" is less use than "Brush up on SQL skills", and derived
# names collide across concurrent sessions.
cs_resolve_name() {
    local id="$1" pf name src tr v
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
    local f id
    cs_version_guard
    for f in "$(_cs_projects_dir)"/*/*.jsonl; do
        [ -f "$f" ] || continue
        id=$(basename "$f" .jsonl)
        printf '%s\t%s\t%s\n' "$id" "$(cs_is_live "$id" && echo live || echo dead)" "$(cs_resolve_name "$id")"
    done
}

# cs_find <ref> -> matching session ids, one per line.
#
# Accepts a full UUID, a short id prefix, or a case-insensitive name substring.
# Prints every match; callers that need exactly one must check the count. A
# substring can legitimately match several sessions, because derived names
# collide (two concurrent sessions have both been observed named documents-7c).
cs_find() {
    local ref="$1" id live name
    [ -n "$ref" ] || return 1
    if cs_transcript_path "$ref" >/dev/null 2>&1; then printf '%s\n' "$ref"; return 0; fi
    while IFS=$'\t' read -r id live name; do
        case "$id" in "$ref"*) printf '%s\n' "$id"; continue;; esac
        case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
            *"$(printf '%s' "$ref" | tr '[:upper:]' '[:lower:]')"*) printf '%s\n' "$id";;
        esac
    done < <(cs_list)
}
