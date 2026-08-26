# FAQ

Questions about how the kit behaves. Something broken rather than unclear is
[TROUBLESHOOTING.md](TROUBLESHOOTING.md), which works by symptom.

**Why doesn't the tab title change right after a rename?**
The tab reads its title when it opens. Close and reopen the tab to see the new
name; the session picker shows it immediately.

**Can it rename a session other than the one I'm in?**
No, on purpose. A title should be written by the session that can actually see the
conversation. The one exception is import, which titles the sessions it just
installed from a bundle. The reasoning lives in the naming design doc.

**Does it fight Claude Code's built-in `/rename`?**
No. The kit writes the same kind of title entry `/rename` writes, one appended
line. The newest title wins, cleanly, whichever tool wrote it.

**Do I need all four hooks?**
No. The installer wires all four, but each works alone, so delete the lines you do not
want from `settings.json`. Re-running the installer puts them back, so use
`./install.sh --uninstall` if you want them gone for good. The skills work with no hooks
at all; you just lose the automatic reminders. They do still need `install.sh`, for the
libraries they source.

**Does anything leave my machine?**
No. There is no network code. Even the failure report is written locally and
redacted, for you to paste somewhere only if you choose to.

**What happens when Claude Code updates?**
A startup hook notices and re-tests the kit against your real data, once, in the
background. Silence means everything still works. If something moved, the kit
warns you until it is looked at.

