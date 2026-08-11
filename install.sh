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
DEST_SKILL_NOTE="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/skills/session-note"
DEST_SKILL_HANDOFF="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/skills/handoff"

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
    # Note DATA (~/.claude/session-notes) is deliberately left alone: it is user
    # content, not kit code, which is also why it lives outside $DEST_LIB.
    run rm -rf "$DEST_LIB" "$DEST_SKILL" "$DEST_SKILL_NOTE" "$DEST_SKILL_HANDOFF"
    echo "removed $DEST_LIB and the three skills"
    echo "(the knobs config went with it — it configures nothing once the kit is gone)"
    exit 0
fi

# --- preflight --------------------------------------------------------------

command -v jq >/dev/null 2>&1 || {
    echo "install.sh: jq is required (brew install jq)" >&2; exit 1; }

for f in core/sessions.sh naming/rename.sh notes/note.sh tests/smoke.sh config.example \
         hooks/version-check.sh hooks/session-note.sh hooks/session-guard.sh hooks/session-drift.sh \
         handoff/export.sh handoff/import.sh handoff/split.sh handoff/claim.sh handoff/release.sh \
         skills/rename-session/SKILL.md skills/session-note/SKILL.md skills/handoff/SKILL.md; do
    [ -f "$ROOT/$f" ] || { echo "install.sh: missing $f — run from a full checkout" >&2; exit 1; }
done

# Refuse to install something the tests reject. CS_INSTALL_NO_GATE exists for the
# suite itself, whose install fixtures call this installer — gating would recurse.
if [ "$DRY" -eq 0 ] && [ -z "${CS_INSTALL_NO_GATE:-}" ] && [ -f "$ROOT/tests/run.sh" ]; then
    bash "$ROOT/tests/run.sh" >/dev/null 2>&1 || {
        echo "install.sh: tests fail, refusing to install" >&2
        echo "  run: bash tests/run.sh" >&2
        exit 1; }
fi

# --- commit guardrail (checkout only) ----------------------------------------
#
# Wired via hooksPath so the TRACKED hook file stays the live one — updates arrive
# with git pull, nothing to re-copy. Blocks staged home paths / emails / denylisted
# terms; this repo once needed a history rewrite for exactly that leak. No-op when
# this is not a git checkout (an installed copy has no commits to guard).
if [ -d "$ROOT/.git" ] && [ -f "$ROOT/guardrail/pre-commit" ]; then
    run git -C "$ROOT" config core.hooksPath guardrail
    [ -f "$ROOT/guardrail/denylist.local" ] || run cp "$ROOT/guardrail/denylist.local.example" "$ROOT/guardrail/denylist.local"
fi

# --- libraries --------------------------------------------------------------

echo "installing to $DEST_LIB"
run mkdir -p "$DEST_LIB/core" "$DEST_LIB/naming" "$DEST_LIB/notes" "$DEST_LIB/tests" "$DEST_LIB/hooks" "$DEST_LIB/handoff"
run cp "$ROOT/core/sessions.sh"  "$DEST_LIB/core/sessions.sh"
run cp "$ROOT/naming/rename.sh"  "$DEST_LIB/naming/rename.sh"
run cp "$ROOT/notes/note.sh"     "$DEST_LIB/notes/note.sh"

# smoke.sh ships with the libraries because the version guard tells people to run it.
# Advice that names a file only a checkout has is advice most users cannot follow.
# It locates core/ as ../core relative to itself, so this layout works unchanged.
run cp "$ROOT/tests/smoke.sh"    "$DEST_LIB/tests/smoke.sh"

# Knobs: the example ships (and updates) every install; the LIVE config is seeded
# once and never overwritten, so user-edited values survive upgrades — same shape
# as the guardrail's denylist.local. Removed by --uninstall along with the kit.
run cp "$ROOT/config.example" "$DEST_LIB/config.example"
[ -f "$DEST_LIB/config" ] || run cp "$ROOT/config.example" "$DEST_LIB/config"

# The SessionStart hook is installed but NOT wired up: adding it to settings.json
# is the user's call, not an installer's. Printed at the end instead.
run cp "$ROOT/hooks/version-check.sh" "$DEST_LIB/hooks/version-check.sh"
run cp "$ROOT/hooks/session-note.sh"  "$DEST_LIB/hooks/session-note.sh"
run cp "$ROOT/hooks/session-guard.sh" "$DEST_LIB/hooks/session-guard.sh"
run cp "$ROOT/hooks/session-drift.sh" "$DEST_LIB/hooks/session-drift.sh"
run chmod +x "$DEST_LIB/hooks/version-check.sh" "$DEST_LIB/hooks/session-note.sh" \
             "$DEST_LIB/hooks/session-guard.sh" "$DEST_LIB/hooks/session-drift.sh"

# The handoff commands install whole: export/import for cross-machine, then
# split/claim/release for same-machine. The skill's code blocks point here.
for h in export import split claim release; do
    run cp "$ROOT/handoff/$h.sh" "$DEST_LIB/handoff/$h.sh"
    run chmod +x "$DEST_LIB/handoff/$h.sh"
done

# --- skill ------------------------------------------------------------------
#
# The checked-in SKILL.md sources core/ and naming/ by relative path so it works
# from a checkout. Installed, cwd is whatever project the user is in, so rewrite
# those to absolute paths at copy time.

for pair in "rename-session|$DEST_SKILL" "session-note|$DEST_SKILL_NOTE" "handoff|$DEST_SKILL_HANDOFF"; do
    name="${pair%%|*}"; dest="${pair##*|}"
    echo "installing skill to $dest"
    run mkdir -p "$dest"
    if [ "$DRY" -eq 1 ]; then
        printf '  would: rewrite source paths and write %s/SKILL.md\n' "$dest"
        continue
    fi
    # Never clobber a skill this kit did not write. Ours always source a library
    # under .../session-kit/ (the rewrite below guarantees it); a pre-existing
    # SKILL.md without that marker belongs to the user or another tool.
    if [ -f "$dest/SKILL.md" ] && ! grep -q 'session-kit' "$dest/SKILL.md"; then
        echo "install.sh: $dest/SKILL.md exists and was not written by this kit — refusing to overwrite" >&2
        echo "  move it aside (or delete it) and re-run" >&2
        exit 1
    fi
    sed -e "s|^\. core/sessions\.sh|. \"$DEST_LIB/core/sessions.sh\"|" \
        -e "s|^\. naming/rename\.sh|. \"$DEST_LIB/naming/rename.sh\"|" \
        -e "s|^\. notes/note\.sh|. \"$DEST_LIB/notes/note.sh\"|" \
        -e "s|^handoff/|$DEST_LIB/handoff/|" \
        "$ROOT/skills/$name/SKILL.md" >"$dest/SKILL.md"

    # A missed rewrite installs a skill that silently cannot find its libraries.
    if grep -qE '^\. (core|naming|notes)/|^handoff/' "$dest/SKILL.md"; then
        echo "install.sh: some source paths were not rewritten in $name" >&2
        exit 1
    fi
done

# --- verify -----------------------------------------------------------------

if [ "$DRY" -eq 0 ]; then
    # shellcheck source=/dev/null
    ( . "$DEST_LIB/naming/rename.sh" && rename_check_title x ) >/dev/null 2>&1 || {
        echo "install.sh: installed copy failed to load" >&2; exit 1; }
    ( . "$DEST_LIB/notes/note.sh" && type note_write ) >/dev/null 2>&1 || {
        echo "install.sh: installed notes module failed to load" >&2; exit 1; }
    echo "verified: installed copy loads"
fi

echo
echo "done. /rename-session, /session-note and /handoff are available in new sessions."
echo "the libraries are usable directly too:"
echo "  . $DEST_LIB/core/sessions.sh && cs_list"
echo "if Claude Code updates and the kit warns that internals may have moved:"
echo "  bash $DEST_LIB/tests/smoke.sh"
echo
echo "to re-verify automatically instead, add to SessionStart in settings.json:"
echo "  \"$DEST_LIB/hooks/version-check.sh\" 2>/dev/null || true"
echo "to have session notes surface on resume, add to UserPromptSubmit:"
echo "  \"$DEST_LIB/hooks/session-note.sh\" 2>/dev/null || true"
echo "to have split sessions remind you where the topic went, also add:"
echo "  \"$DEST_LIB/hooks/session-guard.sh\" 2>/dev/null || true"
echo "to get drift checks (rename / split / wrong tab), also add:"
echo "  \"$DEST_LIB/hooks/session-drift.sh\" 2>/dev/null || true"
