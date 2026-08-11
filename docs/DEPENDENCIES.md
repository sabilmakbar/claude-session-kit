# Dependencies

Tools the kit expects. `install.sh` checks the hard requirement and refuses politely
when it is missing; everything else degrades to a clear error at the point of use.

## Required
- **jq**. Parses transcripts, pid files, and hook input, and builds every JSON line
  the kit writes. Without it, the resolver reports "no data" and `rename`, `note`,
  and `handoff` refuse with a message. Nothing guesses.

## Used when you use the feature
- **tar**, and **shasum** or **sha256sum** (one of the two, both stock on macOS and
  Linux). Only for cross-machine handoff bundles. Export and import refuse up front
  when no sha tool is present, rather than producing a bundle nothing can verify.
- **git**. Only for the commit guardrail in a development checkout: a pre-commit
  hook that blocks staged home paths, emails, em-dashes in the reader-facing docs,
  and any private terms you list in `guardrail/denylist.local` (seeded from the
  example at install; the `CLAUDE_CONFIG_DENYLIST` env var works too). An installed
  copy never calls git.

## Platform
- **bash or zsh.** The full test suite runs under both. Other shells fail loudly at
  parse time instead of misbehaving quietly.
- **macOS and Linux** with their stock userland. The scripts stick to portable
  calls; no Homebrew coreutils needed. CI runs the suite on both.
- **Claude Code** itself. The kit reads its undocumented internals, verified
  against the versions listed in `core/sessions.sh`. A version-check hook re-tests
  after every Claude Code update and warns if something moved.

## Never used
No network calls, no package installs, no daemons, no telemetry. The kit is files
reading files.
