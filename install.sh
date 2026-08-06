#!/usr/bin/env bash
# install.sh — idempotent. Re-running is safe and is the upgrade path.
#
# Installs to the same shape claude-memory-kit uses: real directories under
# ~/.claude, referenced by absolute path. Nothing is symlinked, so the checkout
# can move or disappear without breaking an installed skill.
#
#   ~/.claude/session-kit/{core,naming}/   the libraries
#   ~/.claude/skills/rename-session/       the skill, with paths rewritten
#
# Usage: ./install.sh [--dry-run] [--uninstall]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEST_LIB="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/session-kit"
DEST_SKILL="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/skills/rename-session"

DRY=0; UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY=1 ;;
        --uninstall) UNINSTALL=1 ;;
        *) echo "install.sh: unknown option $arg" >&2; exit 2 ;;
    esac
done

run() { [ "$DRY" -eq 1 ] && { printf '  would: %s\n' "$*"; return 0; }; "$@"; }

if [ "$UNINSTALL" -eq 1 ]; then
    echo "uninstalling"
    run rm -rf "$DEST_LIB" "$DEST_SKILL"
    echo "removed $DEST_LIB and $DEST_SKILL"
    exit 0
fi

# --- preflight --------------------------------------------------------------

command -v jq >/dev/null 2>&1 || {
    echo "install.sh: jq is required (brew install jq)" >&2; exit 1; }

for f in core/sessions.sh naming/rename.sh skills/rename-session/SKILL.md; do
    [ -f "$ROOT/$f" ] || { echo "install.sh: missing $f — run from a full checkout" >&2; exit 1; }
done

# Refuse to install something the tests reject.
if [ "$DRY" -eq 0 ] && [ -f "$ROOT/tests/run.sh" ]; then
    bash "$ROOT/tests/run.sh" >/dev/null 2>&1 || {
        echo "install.sh: tests fail, refusing to install" >&2
        echo "  run: bash tests/run.sh" >&2
        exit 1; }
fi

# --- libraries --------------------------------------------------------------

echo "installing to $DEST_LIB"
run mkdir -p "$DEST_LIB/core" "$DEST_LIB/naming"
run cp "$ROOT/core/sessions.sh"  "$DEST_LIB/core/sessions.sh"
run cp "$ROOT/naming/rename.sh"  "$DEST_LIB/naming/rename.sh"

# --- skill ------------------------------------------------------------------
#
# The checked-in SKILL.md sources core/ and naming/ by relative path so it works
# from a checkout. Installed, cwd is whatever project the user is in, so rewrite
# those to absolute paths at copy time.

echo "installing skill to $DEST_SKILL"
run mkdir -p "$DEST_SKILL"
if [ "$DRY" -eq 1 ]; then
    printf '  would: rewrite source paths and write %s/SKILL.md\n' "$DEST_SKILL"
else
    sed -e "s|^\. core/sessions\.sh|. \"$DEST_LIB/core/sessions.sh\"|" \
        -e "s|^\. naming/rename\.sh|. \"$DEST_LIB/naming/rename.sh\"|" \
        "$ROOT/skills/rename-session/SKILL.md" >"$DEST_SKILL/SKILL.md"

    # A missed rewrite installs a skill that silently cannot find its libraries.
    if grep -qE '^\. (core|naming)/' "$DEST_SKILL/SKILL.md"; then
        echo "install.sh: some source paths were not rewritten" >&2
        exit 1
    fi
fi

# --- verify -----------------------------------------------------------------

if [ "$DRY" -eq 0 ]; then
    # shellcheck source=/dev/null
    ( . "$DEST_LIB/naming/rename.sh" && rename_check_title x ) >/dev/null 2>&1 || {
        echo "install.sh: installed copy failed to load" >&2; exit 1; }
    echo "verified: installed copy loads"
fi

echo
echo "done. /rename-session is available in new sessions."
echo "the libraries are usable directly too:"
echo "  . $DEST_LIB/core/sessions.sh && cs_list"
