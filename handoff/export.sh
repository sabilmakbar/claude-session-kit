#!/usr/bin/env bash
# handoff/export.sh — bundle sessions for another machine.
#
#   handoff/export.sh [-o <dir>] [-n <note.md>] <session-ref>... [-- <file>...]
#
# Each <session-ref> is a UUID, a short-id prefix, or a title substring (resolved via
# core/; ambiguity refuses with the candidates listed). Everything after `--` is a
# loose artifact (diff, patch) carried in files/. The note travels as notes/HANDOFF.md:
# pass one with -n, or a template is included — the note is written by a human or the
# agent, never generated here (DESIGN-handoff.md, lesson 2: the note is the most
# valuable file in the bundle).
#
# Output: session-handoff-<stamp>.tar.gz containing manifest.json, sessions/<id>.jsonl
# (original UUID filenames — no rename dance on import), notes/, files/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
. "$ROOT/core/sessions.sh"

usage() { echo "usage: export.sh [-o <dir>] [-n <note.md>] <session-ref>... [-- <file>...]" >&2; exit 2; }

_ho_sha256() {  # <file> -> hex digest, whichever tool this OS has
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

OUT_DIR="$PWD"; NOTE=""
while getopts 'o:n:' opt; do
    case "$opt" in
        o) OUT_DIR="$OPTARG" ;;
        n) NOTE="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

REFS=(); FILES=()
seen_sep=0
for arg in "$@"; do
    if [ "$arg" = "--" ]; then seen_sep=1; continue; fi
    if [ "$seen_sep" -eq 1 ]; then FILES+=("$arg"); else REFS+=("$arg"); fi
done
[ "${#REFS[@]}" -gt 0 ] || usage

cs_have_deps || { echo "export: jq not found" >&2; exit 1; }
cs_version_guard
[ -z "$NOTE" ] || [ -r "$NOTE" ] || { echo "export: cannot read note $NOTE" >&2; exit 1; }
for f in ${FILES+"${FILES[@]}"}; do
    [ -r "$f" ] || { echo "export: cannot read file $f" >&2; exit 1; }
done

# --- resolve every ref before writing anything -------------------------------
#
# Ambiguity refuses rather than guesses: derived names genuinely collide, and a bundle
# quietly built from the wrong session is the worst outcome this script has.
IDS=()
for ref in "${REFS[@]}"; do
    matches=$(cs_find "$ref") || matches=""
    n=$(printf '%s\n' "$matches" | grep -c . || true)
    case "$n" in
        0) echo "export: no session matches '$ref'" >&2; exit 1 ;;
        1) IDS+=("$(printf '%s' "$matches")") ;;
        *) echo "export: '$ref' is ambiguous — matches:" >&2
           while IFS= read -r m; do
               printf '  %s  %s\n' "${m:0:8}" "$(cs_resolve_name "$m")" >&2
           done <<<"$matches"
           exit 1 ;;
    esac
done

# --- validate every transcript before writing anything -----------------------
for id in "${IDS[@]}"; do
    tr=$(cs_transcript_path "$id") || { echo "export: no transcript for $id" >&2; exit 1; }
    badc=$(jq -R 'try (fromjson | empty) catch "x"' "$tr" 2>/dev/null | grep -c . || true)
    [ "$badc" -eq 0 ] || { echo "export: transcript for ${id:0:8} has $badc unparseable lines — refusing" >&2; exit 1; }
    if cs_is_live "$id"; then
        echo "export: note — ${id:0:8} is live; the bundle is a snapshot of this moment" >&2
    fi
done

# --- stage -------------------------------------------------------------------
STAMP=$(date +%Y%m%d-%H%M%S)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/sessions" "$STAGE/notes"

entries="[]"
for id in "${IDS[@]}"; do
    tr=$(cs_transcript_path "$id")
    cp "$tr" "$STAGE/sessions/$id.jsonl"
    # Manifest fields come from the COPY: the original may be live and still growing,
    # and the hash must describe the bytes actually in the bundle.
    c="$STAGE/sessions/$id.jsonl"
    entry=$(jq -n \
        --arg id "$id" \
        --arg title "$(cs_resolve_name "$id")" \
        --arg cwd "$(jq -rs 'map(select(.cwd)) | .[0].cwd // ""' "$c" 2>/dev/null)" \
        --arg first "$(jq -rs 'map(select(.timestamp)) | .[0].timestamp // ""' "$c" 2>/dev/null)" \
        --arg last "$(jq -rs 'map(select(.timestamp)) | .[-1].timestamp // ""' "$c" 2>/dev/null)" \
        --argjson lines "$(wc -l <"$c" | tr -d ' ')" \
        --arg sha "$(_ho_sha256 "$c")" \
        '{id:$id, title:$title, cwd:$cwd, first_ts:$first, last_ts:$last, lines:$lines, sha256:$sha}')
    entries=$(jq -n --argjson a "$entries" --argjson e "$entry" '$a + [$e]')
done

if [ -n "$NOTE" ]; then
    cp "$NOTE" "$STAGE/notes/HANDOFF.md"
else
    cat >"$STAGE/notes/HANDOFF.md" <<'EOF'
# HANDOFF — fill this in before relying on the bundle

## Context
(what this work is, one paragraph)

## Decided
(conclusions that should not be relitigated, with the why)

## Open threads
(what is unfinished, and its current state)

## Next
(the first thing to pick up on the other side)
EOF
    echo "export: no -n note given — a template was included; edit it before handing off" >&2
fi

fl="[]"
for f in ${FILES+"${FILES[@]}"}; do
    mkdir -p "$STAGE/files"
    cp "$f" "$STAGE/files/$(basename "$f")"
    fl=$(jq -n --argjson a "$fl" --arg f "files/$(basename "$f")" '$a + [$f]')
done

jq -n \
    --argjson sessions "$entries" \
    --argjson files "$fl" \
    --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg host "$(uname -n)" \
    --arg verified "$CS_VERIFIED_VERSION" \
    '{format:1, created:$created, host:$host, kit_verified_for:$verified,
      note:"notes/HANDOFF.md", sessions:$sessions, files:$files}' >"$STAGE/manifest.json"

# Never overwrite an existing bundle: two exports within the same second would
# otherwise silently clobber each other (found by a test doing exactly that).
BUNDLE="$OUT_DIR/session-handoff-$STAMP.tar.gz"
n=2
while [ -e "$BUNDLE" ]; do
    BUNDLE="$OUT_DIR/session-handoff-$STAMP-$n.tar.gz"; n=$((n+1))
done
mkdir -p "$OUT_DIR"
tar -czf "$BUNDLE" -C "$STAGE" .

echo "bundle: $BUNDLE"
jq -r '.sessions[] | "  \(.id[0:8])  \(.lines) lines  \(.title)"' "$STAGE/manifest.json"
[ "${#FILES[@]}" -eq 0 ] 2>/dev/null || printf '  +%s loose file(s)\n' "${#FILES[@]}"
