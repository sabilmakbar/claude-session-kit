# Contributing

The short version: read [docs/INTERNALS.md](docs/INTERNALS.md) first, then the decision
record for the area you are touching. Both exist so that a change knows what it would be
overturning.

## Start with what is observed, not with what we decided

This kit reads files Claude Code owns, and Claude Code documents none of them.
[docs/INTERNALS.md](docs/INTERNALS.md) is the record of what was actually observed: fifteen
entries, each with the date and version it was seen on, the surface it was read from, how it
was checked, and what you need to re-run the check yourself.

Read it before proposing a design, because **three of those fifteen replaced an earlier
belief within a day or two of being recorded.** They are marked `Supersedes`. A design
resting on one of those deserves more doubt than one resting on an entry confirmed across
three versions.

Four of the fifteen carry `Checkable: manual`, and not all for the same reason. Two need a
live VS Code session, because a headless run has no tab to observe. One is deduced from
another observation rather than read directly, and one is a behaviour whose handler you can
read in the extension bundle but whose effect you cannot.

## Then the decision record

The `docs/DESIGN-*.md` files hold what we chose and why. They cite observations by
number rather than restating them, so a fact has one home and cannot drift between files.

Each record opens with its status, when it was last revised, and the Claude Code version
behind it. [docs/DESIGN-naming.md](docs/DESIGN-naming.md) comes first if you are reading
more than one; the other two assume its model.

**Dates belong in two different places, and it is deliberate.** A date recording when
something about Claude Code was observed goes in `INTERNALS.md`, in that entry's
`First observed` field. A date marking when we changed our minds stays in the prose of the
decision record, beside the position it retired.

The second kind looks like a work journal and is not one. "This rule changed five times on
2026-08-05" tells you the design was tested hard and kept breaking within a single day.
Five changes across six months would tell you something else entirely: churn, or a question
nobody could settle. Same table underneath, different meaning, and the date is the only
thing carrying it. Do not tidy those into the header. The header holds one revision date,
and a record may retire several positions on several days.

## Proposing something different

That is the point of these files, so it is welcome. What helps:

- **Name the observation you are relying on.** If it is not in `INTERNALS.md`, say how you
  checked it, on which version, and how someone else would re-run it. An observation with
  no method behind it is a guess, and this kit has been wrong that way before.
- **Name the decision you would overturn.** The records say why each rule exists, including
  the ones that look arbitrary. If a reason no longer holds, say which one and why.
- **Say what would reopen your own proposal.** Every decision here that has been reversed
  was reversed because someone wrote down the condition that would break it.

## Before you open a pull request

GitHub fills the description with
[the pull request template](.github/PULL_REQUEST_TEMPLATE.md). Answer every section it asks for.
It carries the questions only, and this file carries the reasons behind them, so nothing is
written down twice and the two cannot drift apart.

Keep the sections as they are. Dropping one is fine when it genuinely does not apply, such as
"what would reopen this" on a typo fix, but say so in the description rather than deleting it
silently. A section removed without a word reads the same as a question nobody answered.

```bash
bash tests/run.sh      # the fixture suite; install.sh refuses to deploy a tree it rejects
bash tests/smoke.sh    # the real-data suite, against your own ~/.claude
```

`run.sh` is the gate. `smoke.sh` passes or skips depending on the machine it runs on, which
is the point, so it is never a required check.

Point the commit guardrail at your checkout too. It adds one house rule on top of the leak
checks: no em-dashes on lines added to `README.md` or `docs/*.md`.

```bash
git -C . config core.hooksPath guardrail
```

One thing the fixture suite cannot do: notice that Claude Code changed. Fixtures encode what
we believe the format to be, so they pass forever against a stale belief. That is what
`smoke.sh` and `INTERNALS.md` are for, and why re-verification is a manual pass rather than
a green check.
