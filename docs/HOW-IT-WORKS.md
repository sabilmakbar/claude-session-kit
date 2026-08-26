# How it works

The idea in one sentence: sessions have seams. You open them, reopen them, outgrow
them, move them. This kit puts the right information into your hands at each
seam, staying silent the rest of the time.

Everything below happens through ordinary Claude Code hooks and plain files. The
hooks never judge anything by themselves; they hand a question to the Claude
instance inside your session, which answers it silently because it has actually
read the conversation. If a hook hits any problem, it does nothing at all.

## When you reopen a session

**Your last note greets you.** If the session ever saved a note (decided / done /
next), your first message brings it back, stamped with how old it is: "written 340
entries ago". Claude treats an old note with suspicion instead of confidence, which
is the point of the stamp.

**A wrong-tab check runs on every message.** If a message clearly belongs to different
work than this session is about, Claude says so before answering, because answering
would pollute a clean session. You get the session that work already lives in, a fresh
one, or carrying on here if you say so. It never refuses. If the message fits, you
never hear about the check.

It used to run only on the first message after reopening. That sounded reasonable and
was not, because an off-topic question does not politely arrive first.

## While you work

Every two hundred entries or so, Claude silently asks itself whether the session
still matches its title. Three outcomes:

- It matches. You hear nothing.
- The same work evolved past the title. Claude offers a rename.
- A second topic is growing. Claude offers to split it into a fresh session.

A session that never got a real name gets a gentler nudge: want to name this?

Both of those numbers, how much history a session needs before the checks start and
how often they run, are settings rather than constants. They live in a small config
file the install seeds at `~/.claude/session-kit/config`, and the choices are
explained inside it. [FLOWS.md](FLOWS.md) gives the values and the rules.

## When a session outgrows itself

A split moves a topic to a fresh session without moving any files:

1. Claude drafts a handoff note from the conversation: context, decisions, open
   threads, what to pick up first. You review it.
2. The note lands in a folder, and the old session is marked "handed off, pending".
3. You open a fresh session and type anything. It notices the pending handoff,
   claims it, and starts from the note.
4. The old session keeps a small signpost: this topic now lives over there. History
   questions still work; the old transcript is the only place the full story lives.

If nobody claims the handoff within two days, the nudging stops and the old session's
signpost changes to say so, with three ways out: claim it manually (that never
expires), re-split with a fresh note, or release the topic back. The note's folder is
never deleted either way; it is the record of why the split happened.

A split passes through four states, and which sessions hear about it differs in each.
[FLOWS.md](FLOWS.md) has both as a diagram and a table if you want the full picture.

## When you change machines

`export.sh` packs chosen sessions, your note, and any loose files into one archive
with checksums. You carry it however you like. On the other machine, `import.sh`
verifies everything before writing anything: a damaged archive or a session that
diverged between machines refuses the whole import and leaves the machine untouched.
Session titles travel inside the archive, so moved sessions keep their names in the
new machine's picker.

## When Claude Code updates

The kit reads Claude Code's undocumented internals, so any update might move
something. A startup hook notices a version it has not cleared before and runs the
kit's real-data test suite once, in the background. If everything still works, you
never hear about it.

If something moved, you get one line a day saying so, until it passes again. The same
line is how you find out the kit has stopped working for any other reason, which
matters because a broken kit and a healthy one are both silent otherwise. A redacted
failure report sits ready to paste into an issue: versions and check names only,
never your titles or paths.

Each version it passes against is remembered, so going back to an older session you
still have open is not treated as news.

## What it never does

- Never rewrites a transcript. Every write is a single appended line, and undo is
  another append.
- Never touches VS Code's own database.
- Never touches a hook in `settings.json` that it did not write. It knows its own by
  where they live, under `session-kit/hooks/`, so another tool using the same filename
  is reported and left alone rather than claimed. It adds its four when you install,
  takes them back out when you uninstall, and backs the file up before either.
- Never deletes your notes or handoff folders, not even on uninstall.
- Never sends anything anywhere. There is no network code in the kit.

## When it talks first

The kit stays quiet unless something needs a decision or a fix. You will see a message
without asking in a few cases: a failed self-check after a Claude Code update, a note that
the deployed kit and the plugin are on different releases, and, in a development checkout, a
note that a pull changed files the installer deploys. Each names the command that resolves
it, at most once a day. [FLOWS.md](FLOWS.md) lists them all.
