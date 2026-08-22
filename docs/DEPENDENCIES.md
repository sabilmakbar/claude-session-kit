# Dependencies

Tools the kit expects. `install.sh` checks the hard requirement and refuses politely
when it is missing; everything else degrades to a clear error at the point of use.

## Required
- **jq 1.5 or newer**. Parses transcripts, pid files, and hook input, and builds every
  JSON line the kit writes. Without it, the resolver reports "no data" and `rename`,
  `note`, and `handoff` refuse with a message. Nothing guesses. The 1.5 floor is the
  regex functions (`capture`, `gsub`, named captures); nothing here needs 1.6 or later,
  so any `jq` you are likely to already have will do. Developed against 1.7.

  If `jq` disappears after a working install, which a package cleanup or a PATH change
  can do, the hooks cannot complain the way a command can: they have to exit quietly or
  they would break the session. So the kit says it once a day in your session instead,
  and `tests/smoke.sh` refuses with an error rather than reporting a clean run. Nothing
  needs re-installing; everything picks up again as soon as `jq` is back.

## Required for the other half of the install

- **the `claude` CLI**, to install the plugin that carries the skills. `install.sh` gives you
  the hooks and the libraries; the skills come from `claude plugin marketplace add` and
  `claude plugin install`, and neither half works alone. Nothing at runtime needs the CLI: it
  is an install-time requirement only, and `install.sh` reports which half is missing rather
  than assuming.

  If the CLI is not on `PATH` it ships inside the VS Code extension, at
  `~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude`.

## Used when you use the feature
- **tar**, and **shasum** or **sha256sum** (one of the two, both stock on macOS and
  Linux). Only for cross-machine handoff bundles. Export and import refuse up front
  when no sha tool is present, rather than producing a bundle nothing can verify.
- **git**. Only in a development checkout, for two hooks wired through the same
  `core.hooksPath`. The commit guardrail is a pre-commit
  hook that blocks staged home paths, emails, em-dashes in the reader-facing docs,
  and any private terms you list in `guardrail/denylist.local` (seeded from the
  example at install; the `CLAUDE_CONFIG_DENYLIST` env var works too). The deploy-drift
  check is a post-merge, post-checkout and post-rewrite hook that says when the deployed
  tree no longer matches the checkout. An installed copy never calls git.

## Platform
- **bash or zsh.** The full test suite runs under both. Other shells fail loudly at
  parse time instead of misbehaving quietly.
- **macOS and Linux** with their stock userland. The scripts stick to portable
  calls; no Homebrew coreutils needed. CI runs the suite on `ubuntu` and `macos`,
  under both shells.
- **Claude Code** itself. The kit reads its undocumented internals, verified
  against the versions listed in `core/sessions.sh`. A version-check hook re-tests
  after every Claude Code update and warns if something moved.

## Never used
No network calls, no package installs, no daemons, no telemetry. The kit is files
reading files.
