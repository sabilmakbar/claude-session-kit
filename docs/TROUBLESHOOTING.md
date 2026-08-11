# Troubleshooting

Symptom, then check, then fix. If you are not sure anything is wrong, run the doctor first:
`bash ~/.claude/session-kit/tests/smoke.sh`. The README explains what its output means.

This file covers faults. Questions about behaviour that is working as intended live in the
README's FAQ, and one of them is listed at the bottom because it looks like a fault.

## Nothing happens: no note, no reminders, no drift check

**Check.** The installer wires the four hooks, so the usual cause is an install that did
not finish, or a session that was already open when it ran:

```bash
jq '.hooks | tostring | test("session-kit")' ~/.claude/settings.json
```

`false` means nothing is wired.

**Fix.** Re-run `./install.sh`, then start a new session. Hooks are read at session start,
so an already-open session will not pick them up.

The three skills work with no hooks at all. If `/rename-session` works but you never get a
note or a reminder, this is the reason.

## The doctor reports a failure after a Claude Code update

Expected, and it is what the check exists for. The kit reads undocumented internals, so an
update can move something.

**Check.** Read the failing check name. `smoke.sh` names what it expected and what it got.

**Fix.** There is usually nothing to fix locally: the kit degrades to a worse name or goes
quiet rather than doing damage. Report it with the redacted report, not your terminal:

```bash
bash ~/.claude/session-kit/tests/smoke.sh --report
```

That report carries versions, check names, and the first eight characters of a session id.
Your terminal output is deliberately not redacted, because seeing the offending title is
what makes a failure debuggable locally. Do not paste that.

The warning repeats until the suite passes again. It clears itself once it does.

## `export` or `import` refuses

Every refusal is deliberate: the kit stops rather than writing something it cannot verify.
Match your message.

| Message contains | Cause | Fix |
|---|---|---|
| `sha256sum or shasum is required` | no checksum tool on this machine | install either one; both are stock on macOS and Linux |
| `is ambiguous` | your reference matched more than one session | rerun with one of the listed ids |
| `no session matches` | the reference matched nothing | `cs_find <text>` to find the right one |
| `has N unparseable lines` | the transcript is damaged | nothing to fix in the kit; that session cannot be bundled |
| `checksum mismatch` | the bundle was edited or damaged in transit | re-export and re-transfer |
| `already exists here with diverged content` | that session exists on this machine and has different content | nothing is overwritten by design; rename or remove the local copy first if you want the bundled one |
| `refused` plus `nothing was installed` | some earlier check failed | scroll up; the real reason is above this line |

Importing the same bundle twice is safe and does nothing, so a retry after fixing the cause
is free.

## A split will not claim

**Check.** Claim runs from the **fresh** session, not the one that split. `claim: this IS the
session that split` means you ran it in the wrong place.

**Fix.** Open a new session and type anything; the pending handoff surfaces on the first
message. Manual claiming never expires, so a missed 48-hour window costs you the nudge, not
the handoff.

`claim: $DIR has no 'from' file` means the folder was not written by `split.sh`.

## Not a fault

**The tab title did not change after a rename.** Nothing is broken. See the README's FAQ.
