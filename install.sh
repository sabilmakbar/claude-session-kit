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

# --- settings.json hook wiring ------------------------------------------------
#
# This kit wires its own hooks and removes them again, matching claude-memory-kit:
# two kits shipping two different installer contracts is worse than either choice
# on its own. settings.snippet.json is the single source of truth for both halves
# and for anyone who would rather paste the JSON by hand.
#
# Identity is the script basename tokenised out of the command AND the directory
# that basename sits in, never the exact command string. Exact matching duplicated
# a hook on five spellings (a knob prefix, an absolute path where the snippet
# writes $HOME, a missing 2>/dev/null, single quotes for double, extra spacing);
# basename alone was worse in both directions, because tool names collide: another
# tool shipping its own session-note.sh made us skip wiring ours (a silently dead
# kit) and then deleted THEIR hook on uninstall. So a hook is ours only when the
# basename is one we ship and its directory ends in session-kit/hooks.
#
# Three rules protect a file we share with every other tool: a command naming a
# script we do not own is never touched, a malformed command counts as NOT ours
# (removal tidies nobody else's mess), and a same-named hook belonging to someone
# else is left alone AND reported, because silence there looks like a bug in us.
SETTINGS="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/settings.json"
# Kit-specific backup name on purpose: claude-memory-kit backs the same file up to
# settings.json.bak, so a shared name means each kit's installer clobbers the
# other's copy. It lives beside settings.json rather than inside the kit tree
# because --uninstall removes that tree, which is exactly when a backup matters.
SETTINGS_BAK="$SETTINGS.session-kit.bak"
SNIPPET="$ROOT/settings.snippet.json"
[ -f "$SNIPPET" ] || SNIPPET="$DEST_LIB/settings.snippet.json"

# settings.json is the user's global config, shared with every other tool, so it
# gets three layers of protection rather than one:
#   1. it is written LAST, after everything else has installed and verified, so a
#      run that breaks earlier never reaches it at all;
#   2. the merged result is checked before it replaces the live file, so a bad
#      merge is discarded instead of saved;
#   3. if the script still dies after the write, this trap puts the previous
#      contents back from the .bak taken moments earlier.
SETTINGS_TOUCHED=0
SETTINGS_CREATED=0
rollback_settings() {
    local rc=$?
    [ "$rc" -eq 0 ] && return 0
    # A file we created ourselves is undone by removing it, not by restoring an
    # empty one: on a machine that had no settings.json, leaving a {} behind is
    # not the state the run started in.
    if [ "$SETTINGS_CREATED" -eq 1 ]; then
        rm -f "$SETTINGS" 2>/dev/null \
            && echo "install.sh: run failed, so the settings.json it created was removed again" >&2
        return 0
    fi
    [ "$SETTINGS_TOUCHED" -eq 1 ] || return 0
    [ -f "$SETTINGS_BAK" ] || return 0
    cp "$SETTINGS_BAK" "$SETTINGS" 2>/dev/null \
        && echo "install.sh: run failed, so settings.json was rolled back to its previous contents" >&2
    return 0
}
trap rollback_settings EXIT

# Tokens of a command: split on whitespace, then drop characters a path cannot
# contain, which strips the quotes it was written with instead of parsing them. A
# non-string command yields nothing, which is what makes malformed read as "not
# ours". Basenames are compared WHOLE, so mysession-note.sh is never ours either.
JQ_LIB='
def cmd_tokens:
    if type == "string"
    then [scan("[^\\s]+")] | map(gsub("[^A-Za-z0-9._/$~{}-]"; "")) | map(select(length > 0))
    else [] end;
def cmd_basenames: cmd_tokens | map(split("/") | last);
# Every managed basename this command references, split by whether the path is
# ours: refs($managed; true) is this kit, refs($managed; false) is someone else
# using the same filename. The directory test is the whole point, and it holds for
# a deployed tree, a custom prefix, and a checkout alike, since all three end
# .../session-kit/hooks.
def refs($managed; $mine):
    [ (.command | cmd_tokens)[] as $t
      | ($t | split("/") | last) as $b
      | ($t | split("/") | .[:-1] | join("/")) as $dir
      | select($managed | index($b))
      | select(($dir | endswith("session-kit/hooks")) == $mine)
      | $b ];
# Managed = the .sh basenames THIS kit ships in the snippet. Deriving it from the
# snippet keeps the list in exactly one place: adding a hook there is the only
# edit either half needs. The .sh filter drops shell noise ("null" from
# 2>/dev/null, "true", "||") that would otherwise match across unrelated hooks.
def managed_names: [.hooks[]?[]?.hooks[]?.command | cmd_basenames[] | select(endswith(".sh"))] | unique;
'

hooks_wire() {
    [ -f "$SNIPPET" ] || { echo "install.sh: no settings.snippet.json — skipping hook wiring" >&2; return 0; }
    if [ "$DRY" -eq 1 ]; then printf '  would: merge kit hooks into %s\n' "$SETTINGS"; return 0; fi
    mkdir -p "$(dirname "$SETTINGS")"
    if [ ! -f "$SETTINGS" ]; then echo '{}' >"$SETTINGS"; SETTINGS_CREATED=1; fi

    # Warn about hooks that use one of our filenames but live somewhere else. They
    # are another tool's, so they are neither counted as already-wired nor removed
    # later; saying so is the difference between a shared file and a surprise.
    local clash
    clash=$(jq -rs "$JQ_LIB"'
      .[0] as $live | .[1] as $snip
      | ($snip | managed_names) as $managed
      | [$live.hooks[]?[]?.hooks[]? | select((refs($managed; false) | length) > 0) | .command]
      | unique | .[]' "$SETTINGS" "$SNIPPET" 2>/dev/null)
    if [ -n "$clash" ]; then
        echo "  ! settings.json already has hooks named like ours, owned by something else:" >&2
        printf '      %s\n' "$clash" >&2
        echo "    left untouched; this kit only ever writes or removes .../session-kit/hooks/*" >&2
    fi

    # Staged NEXT TO settings.json, not in $TMPDIR: a rename within one directory is
    # atomic, while moving across filesystems is a copy that can be interrupted
    # partway and leave the config truncated.
    local tmp; tmp=$(mktemp "$SETTINGS.tmp.XXXXXX")
    # Merge against a SNAPSHOT, then check the live file still matches it before
    # renaming over the top. Claude Code and other installers write this file too,
    # and without the check a change landing mid-merge would be silently undone.
    local snap; snap=$(mktemp "$SETTINGS.snap.XXXXXX")
    cp "$SETTINGS" "$snap"
    # Dedup is PER HOOK, not per group: a group keyed on its first hook silently
    # drops any hook added to that group later, so upgrades would never land.
    jq -s "$JQ_LIB"'
      .[0] as $live | .[1] as $snip
      | ($snip | managed_names) as $managed
      | $live
      | .hooks = (reduce ($snip.hooks | keys[]) as $ev ((.hooks // {});
          (.[$ev] // []) as $existing
          | ([$existing[]?.hooks[]? | refs($managed; true)[]] | unique) as $have
          | ($snip.hooks[$ev]
             | map(.hooks |= map(select(
                 ([refs($managed; true)[] | select(. as $b | $have | index($b))] | length) == 0)))
             | map(select((.hooks | length) > 0))) as $new
          | .[$ev] = ($existing + $new)))
    ' "$snap" "$SNIPPET" >"$tmp"

    # Check before replacing. Wiring only ever ADDS, so a result that is not valid
    # JSON, or that holds fewer hooks than we started with, means the merge went
    # wrong and the live file is better off untouched.
    local before after
    before=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$snap" 2>/dev/null || echo 0)
    after=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$tmp" 2>/dev/null || echo -1)
    if ! jq -e . "$tmp" >/dev/null 2>&1 || [ "$after" -lt "$before" ]; then
        rm -f "$tmp" "$snap"
        echo "install.sh: the settings.json merge did not look right, so your file was left alone" >&2
        echo "  it is unchanged, and a copy is at $SETTINGS_BAK" >&2
        return 1
    fi
    # Identical result means there is nothing to do, so neither file is touched.
    # That is what keeps an older backup intact: re-running the installer, which is
    # also the upgrade path, cannot overwrite the copy of your pre-kit config.
    if cmp -s "$tmp" "$SETTINGS"; then
        rm -f "$tmp" "$snap"
        echo "  hooks already wired; $SETTINGS left untouched"
        return 0
    fi
    if ! cmp -s "$snap" "$SETTINGS"; then
        rm -f "$tmp" "$snap"
        echo "install.sh: $SETTINGS changed while it was being read, so nothing was written" >&2
        echo "  another tool wrote it at the same moment. Re-run to merge against the new file." >&2
        return 1
    fi
    rm -f "$snap"
    # Nothing to back up when the file did not exist a moment ago; the rollback for
    # that case is removing it, which needs no copy.
    if [ "$SETTINGS_CREATED" -eq 0 ]; then cp "$SETTINGS" "$SETTINGS_BAK"; fi
    SETTINGS_TOUCHED=1
    mv "$tmp" "$SETTINGS"
    if [ "$SETTINGS_CREATED" -eq 1 ]
    then echo "  hooks wired into $SETTINGS (created; there was no settings.json before)"
    else echo "  hooks wired into $SETTINGS (previous contents: $SETTINGS_BAK)"; fi
}

hooks_unwire() {
    [ -f "$SETTINGS" ] || return 0
    [ -f "$SNIPPET" ] || { echo "install.sh: no settings.snippet.json — leaving hooks in place" >&2; return 0; }
    # Without jq the hooks cannot be removed safely, and the tree is about to go, so
    # say exactly what is left behind and how to finish by hand. The hooks stay
    # harmless meanwhile, since each exits quietly when its script is missing, but
    # silence would leave a config nobody knows is stale.
    command -v jq >/dev/null 2>&1 || {
        echo "install.sh: jq not found, so the hooks cannot be removed from $SETTINGS" >&2
        echo "  they will keep pointing at files this uninstall is about to delete." >&2
        echo "  Nothing breaks (each hook exits quietly when its script is gone). To tidy" >&2
        echo "  up, delete the lines naming these from $SETTINGS:" >&2
        echo "    version-check.sh  session-note.sh  session-guard.sh  session-drift.sh" >&2
        return 0; }
    if [ "$DRY" -eq 1 ]; then printf '  would: remove kit hooks from %s\n' "$SETTINGS"; return 0; fi
    # Staged NEXT TO settings.json, not in $TMPDIR: a rename within one directory is
    # atomic, while moving across filesystems is a copy that can be interrupted
    # partway and leave the config truncated.
    local tmp; tmp=$(mktemp "$SETTINGS.tmp.XXXXXX")
    local snap; snap=$(mktemp "$SETTINGS.snap.XXXXXX")
    cp "$SETTINGS" "$snap"
    # Prune upward so an emptied file keeps no scaffolding: our hooks, then groups
    # that became empty, then events, then the "hooks" key itself. Shapes we do not
    # recognise pass through untouched rather than being tidied away.
    jq -s "$JQ_LIB"'
      .[0] as $live | .[1] as $snip
      | ($snip | managed_names) as $managed
      | $live
      | if (.hooks | type) != "object" then .
        else .hooks = (.hooks
            | map_values(
                if type == "array" then
                    map(if (.hooks | type) == "array"
                        then .hooks |= map(select((refs($managed; true) | length) == 0))
                        else . end)
                    | map(select((.hooks | type) != "array" or (.hooks | length) > 0))
                else . end)
            | with_entries(select((.value | type) != "array" or (.value | length) > 0)))
          | if (.hooks | type) == "object" and (.hooks | length) == 0 then del(.hooks) else . end
        end
    ' "$snap" "$SNIPPET" >"$tmp"

    # Check before replacing. Removal is expected to shrink the file, so counting
    # totals proves nothing; what must hold is that every hook that was NOT ours
    # survived. Anything else means we were about to delete someone else's config.
    local keep_before keep_after
    keep_before=$(jq -s "$JQ_LIB"'
        .[0] as $live | .[1] as $snip | ($snip | managed_names) as $managed
        | [$live.hooks[]?[]?.hooks[]? | select((refs($managed; true) | length) == 0)] | length' \
        "$snap" "$SNIPPET" 2>/dev/null || echo -1)
    keep_after=$(jq '[.hooks[]?[]?.hooks[]?] | length' "$tmp" 2>/dev/null || echo -2)
    if ! jq -e . "$tmp" >/dev/null 2>&1 || [ "$keep_after" != "$keep_before" ]; then
        rm -f "$tmp" "$snap"
        echo "install.sh: removing the hooks would have changed something else, so your file was left alone" >&2
        echo "  it is unchanged, and a copy is at $SETTINGS_BAK" >&2
        return 1
    fi
    if cmp -s "$tmp" "$SETTINGS"; then
        rm -f "$tmp" "$snap"
        echo "  no kit hooks were wired; $SETTINGS left untouched"
        return 0
    fi
    if ! cmp -s "$snap" "$SETTINGS"; then
        rm -f "$tmp" "$snap"
        echo "install.sh: $SETTINGS changed while it was being read, so nothing was written" >&2
        echo "  the hooks are still wired. Re-run --uninstall to try again." >&2
        return 1
    fi
    rm -f "$snap"
    cp "$SETTINGS" "$SETTINGS_BAK"
    SETTINGS_TOUCHED=1
    mv "$tmp" "$SETTINGS"
    echo "  hooks removed from $SETTINGS (previous contents: $SETTINGS_BAK)"
}

if [ "$UNINSTALL" -eq 1 ]; then
    echo "uninstalling"
    # Unwire BEFORE the tree goes: the snippet that names our hooks may be the
    # installed copy. An uninstalled kit whose hooks still fire at a path that no
    # longer exists is the failure this half exists to prevent.
    hooks_unwire
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
         settings.snippet.json \
         hooks/version-check.sh hooks/session-note.sh hooks/session-guard.sh hooks/session-drift.sh \
         handoff/export.sh handoff/import.sh handoff/split.sh handoff/claim.sh handoff/release.sh \
         skills/rename-session/SKILL.md skills/session-note/SKILL.md skills/handoff/SKILL.md; do
    [ -f "$ROOT/$f" ] || { echo "install.sh: missing $f — run from a full checkout" >&2; exit 1; }
done

# A settings.json that is already broken stops us before anything is written. The
# wiring step would fail on it at the very end anyway, after a full install, with
# nothing but a raw parser error to show for it. Failing here costs nothing and
# says which file to fix.
if [ -f "$SETTINGS" ] && ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
    echo "install.sh: $SETTINGS is not a valid JSON object, so the hooks cannot be wired" >&2
    echo "  fix or move that file and re-run. Nothing has been installed or changed." >&2
    exit 1
fi

# Refuse to install something the tests reject. CLAUDE_SESSION_KIT_NO_GATE exists for the
# suite itself, whose install fixtures call this installer — gating would recurse.
if [ "$DRY" -eq 0 ] && [ -z "${CLAUDE_SESSION_KIT_NO_GATE:-}" ] && [ -f "$ROOT/tests/run.sh" ]; then
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

# The snippet ships with the kit so an installed copy can unwire itself, and so
# the manual paste path names a real file instead of a block in the README.
run cp "$ROOT/settings.snippet.json" "$DEST_LIB/settings.snippet.json"

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

# --- hooks -------------------------------------------------------------------
#
# Deliberately the LAST thing the installer does. Everything above writes only
# inside the kit's own directories; this step is the one that edits a file the
# user shares with every other tool, so it happens only once the tree is fully
# installed and has been shown to load. A run that breaks earlier leaves
# settings.json exactly as it found it.

echo "wiring hooks"
hooks_wire

echo
echo "done. /rename-session, /session-note and /handoff are available in new sessions."
echo "timing knobs (drift cadence, pickup window) live in $DEST_LIB/config —"
echo "  uncomment a line to change one; upgrades never overwrite your edits."
echo "the libraries are usable directly too:"
echo "  . $DEST_LIB/core/sessions.sh && cs_list"
echo "if Claude Code updates and the kit warns that internals may have moved:"
echo "  bash $DEST_LIB/tests/smoke.sh"
echo
echo "four hooks are now wired in $SETTINGS:"
echo "  version-check   re-tests the kit after a Claude Code update"
echo "  session-note    hands a reopened session its own note back"
echo "  session-guard   points a split session at where the topic went"
echo "  session-drift   notices a stale title or a message in the wrong tab"
echo "they take effect in NEW sessions. To drop one, delete its line from"
echo "settings.json; ./install.sh --uninstall removes all four."
