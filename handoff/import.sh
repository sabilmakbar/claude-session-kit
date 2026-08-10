#!/usr/bin/env bash
# handoff/import.sh — install a session-handoff bundle on this machine.
#
#   handoff/import.sh <bundle.tar.gz>
#
# Two phases, deliberately: EVERY check runs before ANY write, so a bad bundle leaves
# the machine untouched — a half-imported handoff is worse than a refused one.
#
# Sessions land in the project dir of the cwd this runs from (resolved question in
# DESIGN-handoff.md), keeping their original UUID filenames. Each newly installed
# transcript gets its manifest title appended as a custom-title line — this is the
# other-session write path deferred in DESIGN-naming.md's decision record, and import
# is its legitimate caller: the target has no process attached (no concurrent writer),
# and the id + title come from the manifest, an independent source, not from a lookup
# this script just performed. Titles are normalised here because import is the one
# place with no live auto-titler to race against.

set -euo pipefail

# Same guard as export.sh: with no sha tool, verification would compare empty digest
# to empty digest and wave a damaged bundle through. Refuse instead.
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
    || { echo "import: sha256sum or shasum is required (checksum verification)" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
. "$ROOT/core/sessions.sh"
. "$ROOT/naming/rename.sh"   # for RENAME_MAX_TITLE — rename_apply itself stays unused

[ $# -eq 1 ] || { echo "usage: import.sh <bundle.tar.gz>" >&2; exit 2; }
BUNDLE="$1"
[ -r "$BUNDLE" ] || { echo "import: cannot read $BUNDLE" >&2; exit 1; }
cs_have_deps || { echo "import: jq not found" >&2; exit 1; }
cs_version_guard

_ho_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

WORK=$(mktemp -d)
cleanup() { [ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"; }
trap cleanup EXIT

tar -xzf "$BUNDLE" -C "$WORK" 2>/dev/null || { echo "import: not a readable tar.gz" >&2; exit 1; }
M="$WORK/manifest.json"
[ -r "$M" ] || { echo "import: bundle has no manifest.json" >&2; exit 1; }
jq -e . "$M" >/dev/null 2>&1 || { echo "import: manifest.json does not parse" >&2; exit 1; }
[ "$(jq -r '.format // 0' "$M")" = "1" ] || {
    echo "import: manifest format $(jq -r '.format // "missing"' "$M") — this kit reads format 1" >&2; exit 1; }

DEST="$(_cs_projects_dir)/$(cs_encode_cwd "$PWD")"

# --- phase 1: validate everything, write nothing ------------------------------

INSTALL=(); SKIP=0; FAILED=0
while IFS= read -r id; do
    src="$WORK/sessions/$id.jsonl"
    want=$(jq -r --arg id "$id" '.sessions[] | select(.id==$id) | .sha256' "$M")

    if [ ! -r "$src" ]; then
        echo "import: manifest lists ${id:0:8} but the bundle has no file for it" >&2
        FAILED=1; continue
    fi
    got=$(_ho_sha256 "$src")
    if [ "$got" != "$want" ]; then
        echo "import: checksum mismatch for ${id:0:8} — bundle is damaged or was edited" >&2
        FAILED=1; continue
    fi
    if [ -e "$DEST/$id.jsonl" ]; then
        # Prefix comparison, not equality: a previous import appended a custom-title
        # line, and a resumed session appends turns — in both cases the local file
        # STARTS WITH the bundle's bytes and is the same-or-newer session, so skip.
        # No title append on skip either: the existing file may belong to a live
        # session, which import must never write into. A local file that does NOT
        # start with the bundle's bytes (including a local file that is shorter,
        # i.e. the bundle is newer) is a genuine divergence — updating in place
        # would be merging, a stated non-goal, so refuse.
        sz=$(wc -c <"$src" | tr -d ' ')
        if head -c "$sz" "$DEST/$id.jsonl" 2>/dev/null | cmp -s - "$src"; then
            SKIP=$((SKIP+1)); continue
        fi
        echo "import: session ${id:0:8} already exists here with diverged content — refusing" >&2
        echo "  ($DEST/$id.jsonl)" >&2
        FAILED=1; continue
    fi
    INSTALL+=("$id")
done < <(jq -r '.sessions[].id' "$M")

[ "$FAILED" -eq 0 ] || { echo "import: refused — nothing was installed" >&2; exit 1; }

# --- phase 2: install --------------------------------------------------------

mkdir -p "$DEST"
for id in ${INSTALL+"${INSTALL[@]}"}; do
    cp "$WORK/sessions/$id.jsonl" "$DEST/$id.jsonl"

    # Normalise (collapse whitespace, trim) and cap the title, then append it so the
    # name survives the move and shows in this machine's session picker. jq slices by
    # codepoint, so a multibyte title cannot be cut mid-character. Concurrency is not
    # a concern: this file was created two lines up and no process has it.
    title=$(jq -r --arg id "$id" '.sessions[] | select(.id==$id) | .title // ""' "$M" \
        | jq -Rrs --argjson max "$RENAME_MAX_TITLE" \
            'gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "") | .[0:$max]')
    if [ -n "$title" ]; then
        jq -cn --arg t "$title" --arg id "$id" \
            '{type:"custom-title",customTitle:$t,sessionId:$id}' >>"$DEST/$id.jsonl"
    fi
    printf 'installed: %s  %s\n' "${id:0:8}" "${title:-'(untitled)'}"
done
[ "$SKIP" -eq 0 ] || printf 'skipped: %s already-present identical session(s)\n' "$SKIP"

# Loose files stay in the extraction dir rather than being scattered into the cwd —
# import prints where they are and leaves placing them to the user.
if [ -d "$WORK/files" ] && [ -n "$(ls -A "$WORK/files" 2>/dev/null)" ]; then
    KEEP_WORK=1
    printf 'loose files kept at: %s/files\n' "$WORK"
fi

echo
echo "--- HANDOFF note ---"
cat "$WORK/notes/HANDOFF.md" 2>/dev/null || echo "(bundle carried no note)"
