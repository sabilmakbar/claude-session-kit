# claude-session-kit

Tools for managing Claude Code **sessions** across machines — a sibling to
[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit), which does the
same for memory.

**Status: naming works, handoff is still design.** Start with [BACKLOG.md](BACKLOG.md),
then the two design docs.

```bash
./install.sh            # idempotent; --dry-run to preview, --uninstall to remove
```

Installs the libraries to `~/.claude/session-kit/` and the `/rename-session` skill to
`~/.claude/skills/`. It runs the test suite first and refuses to install if it fails.
From a checkout, the scripts also work in place:

```bash
. core/sessions.sh
cs_list                                  # every session, live flag, best-known name
cs_resolve_name "$CLAUDE_CODE_SESSION_ID"
cs_find "memory review"                  # UUID, short-id prefix, or name substring

. naming/rename.sh
rename_apply "A new title"               # the session you are in, and only that one

bash tests/run.sh
```

## The two problems it solves

1. **Session identity** ([docs/DESIGN-naming.md](docs/DESIGN-naming.md)) — a session has
   three names in three places (VS Code tab title, CLI registration name, transcript
   UUID), none of them synced. Titles drift from what the session is actually about,
   and generic derived names ("documents-2d") make past work unfindable.
2. **Session handoff** ([docs/DESIGN-handoff.md](docs/DESIGN-handoff.md)) — moving
   sessions between machines is manual today: tar the transcripts, carry a WIP note,
   rename files to UUIDs by hand on the other side, and lose the titles on the way.

## Layout

```
core/       built    read-only resolver over the transcript and pid-file layers
naming/     built    rename helpers (drift detection still to come)
skills/     built    rename-session
tests/      built    self-contained suite, same style as claude-memory-kit
install.sh  built    idempotent installer, same contract as claude-memory-kit
handoff/    planned  export / import scripts + manifest format
```

`core/` reads two layers, the transcript and the pid-file. VS Code's `state.vscdb` is
deliberately excluded: it only caches the rendered tab, and the tab resolves from the
transcript anyway. See [docs/DESIGN-naming.md](docs/DESIGN-naming.md).

## Shells

**bash and zsh.** Both are tested by running the *whole* suite under each, not by
checking that the library loads. An earlier version only checked loading, and passed
while `cs_find`, `cs_list` and `cs_pid_file` were all broken under zsh — the two shells
differ both in how a sourced file learns its own path (`BASH_SOURCE` vs `$0`) and in
what an unmatched glob does (literal vs fatal).

Other shells fail at parse time (`dash: Syntax error: redirection unexpected`), which is
a deliberate, loud failure rather than a silent misbehaviour. If you need to source the
library from somewhere that cannot report the sourced file's path, set
`CLAUDE_SESSION_KIT_ROOT` to the kit root; a wrong or missing root produces an error
naming that variable rather than a confusing path.

Design rule carried over from the memory kit: plain files, plain bash, no server, no
telemetry; every behavior covered by the test suite; installers idempotent.
