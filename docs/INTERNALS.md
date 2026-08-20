# Claude Code internals, as observed

> **This file is about Claude Code, not about this kit.** It records what was observed
> about undocumented behaviour the kit depends on. The decisions those observations drove
> live in the `DESIGN-*.md` records, which cite these by number. For how the kit behaves,
> read [FLOWS.md](FLOWS.md).

    Observed against:   Claude Code 2.1.220, 2.1.221, 2.1.222 · 2.1.234 (O16–O22) · 2.1.237 (O23)
    Platform:           macOS, VS Code extension
    Last re-verified:   2026-08-12 · 2026-08-19 (O16–O20) · 2026-08-20 (O21–O23)
    Needs to re-run:    jq, a live VS Code session, read access to the extension bundle

Nothing here is promised by Claude Code. Every entry is an observation with a date, a
version, the surface it was read from, and how it was checked, so it can be re-run rather
than believed.

**Four of the twenty-three replaced an earlier belief, and each did so within a day or two of
being recorded**: O2, O11 and O13, marked `Supersedes`. Two further reversals landed on
decisions rather than observations and are recorded in
[DESIGN-naming.md](DESIGN-naming.md). That rate is what reverse-engineering undocumented
software looks like, and it is why a decision resting on a superseded entry deserves more
scepticism than one resting on an entry confirmed across three versions.

Every entry says per line whether it can be checked by a machine, so nothing here has to be
believed on the strength of a sentence in this introduction:

```bash
# which observations a script could re-check, and which need a person
awk '/^### O/{o=$2} /Checkable: +automated/{print o}' docs/INTERNALS.md

# every version any entry has been seen on
grep -hoE '2\.1\.[0-9]+' docs/INTERNALS.md | sort -u

# which decisions rest on a given observation, before you amend it
grep -rn '\bO8\b' docs/DESIGN-*.md
```

Eighteen are automated. Five are manual: four because a headless run has no tab to observe or
the live behaviour is not readable in the bundle, and O18 because it takes a live session to see
a plugin-declared hook fire. Nothing automated will ever cover those.

Eleven of the twenty-three are cited by at least one decision. **O2, O9, O11, O15 and the plugin
entries O16-O23 are cited by none**, which does not make them dead: each is either the evidence a neighbouring entry was
derived from, or, in O15's case, a property the code relies on without any decision record
naming it. Amending one changes what its neighbours rest on even though nothing cites it.
Check both directions before editing, using the third command above.

**Numbers run in discovery order, positions run by surface**, so an entry can sit between two
lower-numbered neighbours. O15 appearing among the transcript entries is the convention
working, not a slip: it was found last and belongs to that surface. Numbers are never reused,
so a citation stays valid however the file is later reorganised.

## The surfaces

| Surface | Path | Written by | Lifetime |
|---|---|---|---|
| Transcript | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, with subagent transcripts two levels deeper (O15) | Claude Code, append-only | permanent |
| pid-file | `~/.claude/sessions/<pid>.json` | Claude Code CLI at session start | one process; pruned |
| Extension bundle | the VS Code extension's `package.json` and `extension.js` | Anthropic, per release | per release |
| CLI binary | ships a compiled regex that scrapes titles | Anthropic, per release | per release |
| `state.vscdb` | VS Code's own store | VS Code | never read or written by this kit |

## The three identities

### O1. One session has three identities, joined by the session UUID

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            all three, compared side by side
    How:                read a live session's transcript, pid-file, and rendered tab together
    Needs:              jq
    Checkable:          automated

| Layer | Example | Where it lives | Who writes it |
|---|---|---|---|
| Display title | "Review memories and feedbacks" | the transcript, as `ai-title` / `custom-title` lines | `ai-title` by Claude Code from the opening message; `custom-title` by `/rename` or by this kit |
| CLI registration name | `documents-2d` | `~/.claude/sessions/<pid>.json` (`name`, `nameSource`) | Claude Code CLI at session start; wiped back to derived on restart |
| Transcript identity | `0d15803a-…` | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | Claude Code, one file per session |

The transcript filename *is* the id, and the pid-file carries it in a `sessionId` field.
Identity was never ambiguous; only the human-readable label was.

## The transcript

### O2. Transcripts carry title entries as their own line types

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            transcript, and the CLI binary
    How:                read raw JSONL; found the CLI's compiled regex "customTitle":"([^"]+)"
    Needs:              jq
    Checkable:          automated
    Supersedes:         "transcripts carry no title/summary entries", wrong, corrected the same day

`{"type":"ai-title","aiTitle":…}` from the opening message, and
`{"type":"custom-title","customTitle":…}` appended by the built-in `/rename`. The CLI
scrapes `customTitle` straight out of the raw JSONL, alongside a title record of
`firstPrompt` / `agentName` / `customTitle` / `aiTitle` / `summary`. **The display title is
file-backed and addressable**, not locked inside VS Code's sqlite.

### O3. `ai-title` is set from the opening message and never revised

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            transcript
    How:                18 byte-identical ai-title lines in one 75-turn session
    Needs:              jq
    Checkable:          automated

So any session that outgrows its first question carries a stale title. The title as a
whole is revisable via `custom-title`; it is the automatic one that never moves.

### O4. `ai-title` is re-emitted immediately after every `custom-title`

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            transcript
    How:                exact repeating pairs at lines 275/276, 295/296, 307/308 of one transcript
    Needs:              jq
    Checkable:          automated

In any active session the last title line is almost always an `ai-title`. **A resolver
that tails the file for "the most recent title" discards the user's rename every time**,
and would pass a casual test, because the clobbering `ai-title` only lands once another
message is sent.

This is the sharpest trap in this file. See the naming record for what the kit does about
it.

### O15. Subagent transcripts exist, nested below the session that spawned them

    First observed:     2026-08-12 · 2.1.222
    Re-verified:        2.1.222
    Surface:            transcript directory
    How:                counted on one machine: 24 session transcripts at depth 2, and 16
                        more at `<encoded-cwd>/<session-uuid>/subagents/agent-<hex>.jsonl`.
                        Every `<session-uuid>` directory had a real session transcript beside
                        it at depth 2. A sibling `tool-results/` holds `.txt`, not `.jsonl`
    Needs:              find
    Checkable:          automated

A session transcript is named for its session id and sits at depth 2. A subagent transcript
is named `agent-<hex>` and sits two levels deeper, under the parent session's own uuid.

**A recursive `*.jsonl` glob over `projects/` therefore returns 40 files where 24 are
sessions.** Depth bounds are what separate them: `find -mindepth 2 -maxdepth 2` yields
sessions only, because the subagent files are at depth 4. Filtering on the uuid shape rejects
them a second way, since `agent-<hex>` is not a uuid.

This one was load-bearing in both kits before it was written down anywhere, which is the
argument for this file existing. It survived only as a depth bound and a regex inside one
`find` command, so a later simplification of that command would have started reading subagent
transcripts as sessions and nothing would have failed.

## The pid-file

### O5. The pid-file is per process, and only for sessions that ran on this machine

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            pid-file
    How:                keyed by pid; carries procStart / startedAt for the live process only
    Needs:              jq
    Checkable:          automated

Imported transcripts have no registration at all.

### O6. Derived names are not unique

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            pid-file
    How:                two concurrent sessions (99f81837, 280dbe52) both held documents-7c
    Needs:              jq
    Checkable:          automated

Any resolve-by-name path must handle ambiguity explicitly rather than assume one hit.

### O7. `nameSource` is absent on explicitly-named sessions

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            pid-file
    How:                8 live pid-files compared: 7 × documents-XX with derived, 1 named with no nameSource
    Needs:              jq
    Checkable:          automated

Absence is the "a human named this" marker, not a missing field to default in.

### O8. An explicit name does not survive a process restart at the pid layer

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            pid-file, against the transcript
    How:                observed live: pid 26094 to 45158 turned detector-heuristic-testing into
                        documents-41 with nameSource derived; the transcript's custom-title for the
                        same session was untouched. pid-file count also fell from 10 to 3 in a day
    Needs:              jq
    Checkable:          automated

The pid layer is not merely ephemeral, it is **actively destructive of names**, and Claude
Code prunes pid-files.

## The tab

### O9. The tab title is a runtime property of the live webview panel

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            extension bundle
    How:                jq '.contributes.commands[]' package.json: 23 commands, none renames.
                        extension.js handles request.type === "rename_tab", whose handler does
                        this.panelTab.title = request.title and swaps the tab icon
    Needs:              jq, read access to the extension bundle
    Checkable:          manual (the handler is readable in the bundle; the live behaviour is not)

Set by the running CLI over its existing extension channel, through the sanctioned VS Code
API. There is no palette entry and nothing invocable from outside.

### O10. `state.vscdb` only caches the rendered tab, after the fact

    First observed:     2026-08-04 · 2.1.221
    Re-verified:        2.1.222
    Surface:            inferred from O9; the file itself was never read
    How:                deduction from the runtime-property finding
    Needs:              none (a deduction, so there is nothing to run)
    Checkable:          manual (deduced from O9; the file itself is never read)

An offline write would be both an unsupported write to a file VS Code holds open, and
pointless for any live session, whose panel would overwrite it.

### O11. The built-in `/rename` writes both layers, and does not refresh a live tab

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            pid-file and transcript
    How:                live experiment. Ran /rename in a live VS Code session. All three pid-file
                        fields changed as predicted: `name` from documents-07 to the new title,
                        `nameSource` from derived to absent, `updatedAt` from null to an
                        epoch-millisecond integer. The tab title did not change
    Needs:              a live VS Code session, jq
    Checkable:          manual (a headless run has no tab)
    Supersedes:         "the tab is unreachable", claimed and retracted 2026-08-05

The tab title is not the session `name`; they are separate values with separate storage.
What does not happen is a **live refresh** of an already-open tab.

### O12. The tab reads `custom-title`, and refreshes on reopen

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            transcript, against the pid-file
    How:                live experiment. Ran /rename, closed the tab, reopened the session, and the
                        tab showed the new name
    Needs:              a live VS Code session
    Checkable:          manual (a headless run has no tab)

The deduction that this comes from `custom-title` and not the pid-file: reopening starts a
new process, which writes a fresh pid-file with a **derived** name, verified separately
when a restart turned `detector-heuristic-testing` into `documents-41`. A tab reading the
pid-file would show `documents-41`. It shows the custom name, so the transcript entry is
the source.

Consequence: **the tab is reachable for any session given a `custom-title`**, not only via
`/rename`. Appending one to a dead or imported session gives it a correct tab title the
next time it opens. The only thing still impossible is retitling a tab that is currently
open, in place.

## Resolving a display name

### O13. Precedence for a resolved display name, highest first

    First observed:     2026-08-05 · 2.1.221
    Re-verified:        2.1.222
    Surface:            transcript and pid-file
    How:                derived from O2, O7, O8 and O12, then confirmed by the reopen experiment
    Needs:              jq
    Checkable:          automated
    Supersedes:         an earlier ordering that put the pid-file first, corrected 2026-08-05

1. transcript last **`custom-title`**: durable; survives restarts and import, and the only
   explicit record for a dead or imported session
2. pid-file `name` with `nameSource` absent: explicit, but ephemeral
3. transcript last **`ai-title`**
4. `firstPrompt` / first user message
5. pid-file `name` with `nameSource` of `derived` or `auto`: `documents-41`, which tells
   you nothing and collides across concurrent sessions
6. short id

The earlier ordering assumed the two always agree, because `/rename` writes both at once.
That broke once `custom-title` could be written on its own: the transcript entry is then
the *newer* value, and ranking the pid-file above it would let a stale name shadow a
rename the tab is already displaying.

**Precedence is by entry type, never by file order**, because of O4. Select by type first,
then take the last of that type.

## Version behaviour

### O14. Version skew between layers is the normal state

    First observed:     2026-08-04 · 2.1.220 and 2.1.221 together
    Re-verified:        2.1.222
    Surface:            pid-file and extension bundle
    How:                all pid-files reported 2.1.220 while the installed extension was already
                        2.1.221, because running processes predate the update
    Needs:              jq
    Checkable:          automated

Not an anomaly. Accessors must tolerate skew rather than assert a single version.

## The plugin surface

### O16. A marketplace is a registry entry; a remote source is cloned, a path is not

    First observed:     2026-08-19 · 2.1.234
    Surface:            ~/.claude/plugins/marketplaces/<name>/
    How:                `git -C ~/.claude/plugins/marketplaces/session-kit remote get-url origin`
                        returns this repo; the directory holds `.claude-plugin/marketplace.json`
    Needs:              git
    Checkable:          automated

`plugin marketplace add` records the source in `extraKnownMarketplaces` and reads which plugins
it offers. It is a registry pointing at sources, not a store and not an updater.

**How it is stored depends on the source.** `add <owner>/<repo>` clones into
`~/.claude/plugins/marketplaces/<name>/`, which is a second copy of the repo: `/plugin update`
refreshes that clone and never touches your checkout, and `git pull` in your checkout never
touches the plugin. Two stale states, unrelated. `add <path>` creates no clone at all and
references the directory in place, so there the "second copy" reasoning does not apply and the
marketplace tracks whatever that working tree currently holds, including an unmerged branch.
An earlier version of this entry claimed the clone unconditionally; it was written from a
GitHub-sourced install and only checked against one.

### O17. The plugin cache is keyed by the version in plugin.json

    First observed:     2026-08-18 · 2.1.234
    Surface:            ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
    How:                ponytail cached as `4.8.4` and dev-pipeline as `0.1.0`, both declaring a
                        version; caveman cached as `0d95a81d35a9`, and its plugin.json has no
                        version field
    Needs:              nothing
    Checkable:          automated

Omit `version` and the cache is keyed by commit SHA instead, which makes "which version is
installed" unanswerable and gives `/plugin update` no version change to react to.

### O18. Nothing runs at plugin install; hooks are the only execution surface

    First observed:     2026-08-18 · 2.1.234
    Surface:            plugin install, and plugin-declared hooks
    How:                installing a plugin clones and reads the manifest, with no shell step;
                        a plugin that declares `hooks` has its commands run on session events,
                        which is how caveman and ponytail activate
    Needs:              nothing
    Checkable:          needs a live session

A plugin can execute arbitrary commands, but only on a hook event, never during install. So a
plugin cannot run an installer for the half it does not ship. `plugin install --help` refers to
"a plugin installed by running a marketplace-declared command", so some install-command path
exists; the `$schema` URL in marketplace.json returns a 404 page, none of the five marketplaces
installed here declare such a field, and its shape is unverified.

### O19. Removing a marketplace disables its plugin and orphans the cache

    First observed:     2026-08-19 · 2.1.234
    Surface:            settings.json and the plugin cache
    How:                in a sandbox HOME: after install, one marketplace and one enabled plugin;
                        `plugin uninstall` left the marketplace (mkt=1 plugin=0); `plugin
                        marketplace remove` left neither (mkt=0 plugin=0) with the cache directory
                        still on disk
    Needs:              jq
    Checkable:          automated

So "plugin installed without its marketplace" is not a reachable state, which is why the
installer's state check treats `enabledPlugins` as authoritative and reads the marketplace only
to tell "nothing installed" from "one command left". An orphaned cache directory is not evidence
of an installed plugin.

### O20. `plugin install` cannot pin a version or ref

    First observed:     2026-08-18 · 2.1.234
    Surface:            plugin install, plugin marketplace add
    How:                `--help` on both: install takes `--config`, `--scope`, `--yes`; marketplace
                        add takes `--scope`, `--sparse`. Neither accepts a ref, tag or version
    Needs:              nothing
    Checkable:          automated

The marketplace clone tracks the repo's default branch, so a release tag cannot change what the
plugin path delivers. `plugin tag` creates a `<name>--v<version>` tag and validates that
plugin.json agrees with the marketplace entry, but nothing on the install side consumes that tag.

### O21. `marketplace add` and `plugin install` are a lookup, not a chain

    First observed:     2026-08-20 · 2.1.234
    Surface:            plugin marketplace add, plugin install
    How:                in a sandbox HOME, `marketplace add <path>` alone left
                        `extraKnownMarketplaces` at 1 with `enabledPlugins` at 0 and no cache
                        directory; `plugin install session-kit@session-kit` with no marketplace
                        added failed with "not found in marketplace"; `plugin install <path>`
                        failed with "not found in any configured marketplace"
    Needs:              jq
    Checkable:          automated

Neither command runs the other. `add` writes the registry and installs nothing; `install` only
resolves names inside registries already configured, and will not take a repo or path to
bootstrap itself. `plugin@marketplace` is a lookup key, not a source. That is why both commands
appear in every install instruction, and why the installer distinguishes "nothing installed" from
"one command left".

Refreshing has two rungs, and they are separate commands: `marketplace update [name]` re-fetches
the registry clone, so a newly published plugin becomes visible, while `plugin update
<plugin>@<marketplace>` moves an installed plugin to what that clone now offers. For a
single-plugin marketplace the first rarely matters, because the plugin list never changes. The
failure message for a missing plugin points at `marketplace update`, not at `add`.

### O22. Nothing removes a plugin's cache, and removal order decides whether you can

    First observed:     2026-08-20 · 2.1.234
    Surface:            plugins/cache, plugin uninstall, marketplace remove, plugin prune
    How:                in a sandbox HOME: after install, cache=1. `plugin uninstall` left
                        cache=1. `plugin marketplace remove` left cache=1. `plugin prune`
                        answered "Nothing to prune (no auto-installed plugins at user scope)".
                        Removing the marketplace first made `plugin uninstall` fail with
                        "Plugin not found", leaving the cache with no command able to remove it
    Needs:              jq
    Checkable:          automated

Two consequences. Cache directories accumulate and are only ever cleaned by hand; `prune` is for
auto-installed dependencies, not for orphans. And uninstall has a required order: take the plugin
out before the marketplace, because `uninstall` resolves the plugin through the registry and
cannot find it once the registry entry is gone. Reversing the order is not recoverable through
the CLI.

### O23. The VS Code extension installs plugins by command and URI, not by a slash command

    First observed:     2026-08-20 · extension 2.1.237
    Surface:            the extension manifest and bundle
    How:                `claude-vscode.installPlugin` is one of the 23 declared commands, titled
                        "Claude Code: Install Plugin" and gated on `claude-vscode.updateSupported`.
                        The bundle registers a URI handler whose `/install-plugin` path reads
                        `plugin` and `marketplace` query parameters and defaults the marketplace to
                        `anthropics/claude-plugins-official`. Typing `/plugin` in a session here
                        answers "isn't available in this environment", and that string is not in
                        the extension bundle, so it comes from the CLI layer
    Needs:              jq
    Checkable:          automated

So `/plugin` is not a safe instruction to publish: this host does not have it, and which hosts do
was not established. The CLI form works wherever the binary does, which is why the docs lead with
it. `/install-plugin` is a deep-link path, not a chat command, and the two are easy to conflate
from a grep alone.

## Evidence summary

| Claim | How it was checked |
|---|---|
| No rename command exists | `jq '.contributes.commands[]' package.json` on the 2.1.221 extension: 23 commands, none rename |
| Title set at runtime by CLI | `rename_tab` handler in `extension.js` assigns `panelTab.title` |
| `nameSource` absent when named | 8 live pid-files in `~/.claude/sessions/` compared |
| pid-file is ephemeral | keyed by pid; contains `procStart` / `startedAt` for the live process only |
| Titles are file-backed | the CLI ships a compiled regex, `"customTitle":"([^"]+)"` |

## Not verified

The internal layout of `state.vscdb`. Reading it was blocked by a permission guard, and
O10 makes it moot: the kit never reads or writes it.
