# claude-session-kit

Tools for managing Claude Code **sessions** across machines — a sibling to
[claude-memory-kit](https://github.com/sabilmakbar/claude-memory-kit), which does the
same for memory.

**Status: design phase.** Nothing here is installable yet. Start with
[BACKLOG.md](BACKLOG.md), then the two design docs.

## The two problems it solves

1. **Session identity** ([docs/DESIGN-naming.md](docs/DESIGN-naming.md)) — a session has
   three names in three places (VS Code tab title, CLI registration name, transcript
   UUID), none of them synced. Titles drift from what the session is actually about,
   and generic derived names ("documents-2d") make past work unfindable.
2. **Session handoff** ([docs/DESIGN-handoff.md](docs/DESIGN-handoff.md)) — moving
   sessions between machines is manual today: tar the transcripts, carry a WIP note,
   rename files to UUIDs by hand on the other side, and lose the titles on the way.

## Layout (planned)

```
core/       shared backbone: locate + read/write the session store (all three layers)
naming/     drift detection, rename helpers
handoff/    export / import scripts + manifest format
skills/     Claude Code skills wrapping the above
tests/      self-contained suite, same style as claude-memory-kit
install.sh  idempotent installer, same contract as claude-memory-kit
```

Design rule carried over from the memory kit: plain files, plain bash, no server, no
telemetry; every behavior covered by the test suite; installers idempotent.
