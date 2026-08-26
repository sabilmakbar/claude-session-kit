# Design: installing and upgrading

> **This is a decision record, not a user guide.** It is dense on purpose: it exists so that
> future changes know what they would be overturning. For how the kit behaves day to day, read
> [FLOWS.md](FLOWS.md). For setup, the README.

    Status:            Implemented
    Last revised:      2026-08-26
    Verified against:  Claude Code 2.1.246

The kit ships in two halves that version independently, and this file is about keeping them
honest about which version they are. It starts with one decision because that is the first
install question anyone here had to answer with evidence; earlier install choices are recorded
where their subject lives, and D8 in [DESIGN-naming.md](DESIGN-naming.md) is the version floor.

## D1. The documented install pins both halves to a release tag

`install.sh` deploys the hooks and libraries; `claude plugin install` delivers the skills. Both
halves carry a version and both default to tracking the default branch. Unpinned, the plugin
cache directory is named from the version `plugin.json` declares on that branch, which is the
next release's number for the whole of a development cycle, so the number on disk names a build
that never shipped. Measured, not argued: the `0.3.1` cache directory on the machine this was
written on predates the `v0.3.1` tag by four hours and differs from it in six files (O27).

So the README carries the tag twice, once per half: `git clone --branch` for the tree, and
`marketplace add <owner>/<repo>@<tag>` for the skills. Pinning is possible because the ref rides
in the marketplace source string (O26), which is a thing an earlier record got wrong by reading
`--help` and stopping there.

**Bumping `plugin.json` only at release was considered and rejected.** It looks like the obvious
fix, since the open number is what leaks. But the marketplace serves a branch either way, so the
label still lies; it would just name an already-published version instead of an unpublished one,
and two machines could then hold different content under one released number. Any static label
inside a moving branch is wrong somewhere. Moving the source is the fix, not moving the bump.

**Having `install.sh` write the pin itself was considered, then measured closed.** It was the
plan while the CLI appeared unable to express a ref. Once `marketplace add <owner>/<repo>@<tag>`
was shown to work, the feature reduced to saving one tag the user already types on the clone
line above. Then the mechanism itself failed: a `ref` written into `settings.json` on an
already-materialised entry is ignored, because `plugins/known_marketplaces.json` keeps the old
source and every update follows that file (O26). The only writer of that file is `marketplace
add`, so there is nothing for the installer to write that would take effect. What would reopen
this is a CLI surface that scripts a pin, not a cheaper way to edit JSON.

**What the installer does instead is report.** A pin that disagrees with the checkout's tag is
named along with the `marketplace add` command that agrees them, and a pin on a checkout that is
not on a tag is called out explicitly, because that is the one case nothing else catches: a
development version has no number the health hook can compare, so its daily notice stays silent.
Reporting rather than rewriting keeps the pin the property of whoever set it.

**Failure posture.** An unpinned install still works and still mislabels; nothing here forces
anyone to pin. A pin below a version already in the cache has no effect, because the newest
cached directory is the one that loads (O17) and nothing ever removes one (O22): the installer
names the blocking directory and the two remedies rather than deleting another tool's state, and
the README's rule is pin forward, not back. The residual is deliberate: `marketplace add <owner>/<repo>` with no tag will
always serve the branch, and documentation can only offer the better form, not impose it. A
README tag left behind by a release would send every new reader to an old version, so a test
holds it to the newest released changelog heading and fails both on a drifted tag and on a README
with no pin at all.

## What would reopen this

- **D1, if a mistyped tag ever puts the two halves on different releases in practice.** The
  installer reports that today rather than preventing it, on the grounds that one user typing two
  tags is a small target. One real occurrence is the evidence that would move the pin write from
  deferred to done.
- **D1, if Claude Code ever clears or refreshes the plugin cache on install.** The backward-pin
  dead end and the reinstall-to-refresh development loop both exist because nothing upstream
  removes or rewrites a cache directory unasked; either behaviour appearing dissolves them.
- **D1, if the marketplace source ever stops accepting a ref.** The whole pinned install rests on
  O26, which is a platform behaviour with no promise behind it. If it goes, the fallback is
  bumping `plugin.json` at release and accepting the weaker label, because there would be nothing
  left to pin.
