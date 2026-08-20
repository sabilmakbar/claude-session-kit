#!/usr/bin/env bash
# SessionStart hook, declared by the PLUGIN, not wired into settings.json by install.sh.
#
# It exists for the one state install.sh cannot report: the plugin is installed and the kit
# is not. install.sh only speaks while it runs, and in that state it has never run. Running
# from the plugin cache means this fires exactly when the plugin is present, which is exactly
# when the question is worth asking.
#
# Depends on nothing but test and printf. No jq, no kit file, no node. It is reporting that
# the kit's files are absent, so it cannot need one of them to say so — the same rule
# memory-kit's health hook follows.
#
# The message is a fixed string with nothing interpolated into it. A path spliced into JSON
# is how a quote in a home directory turns a notice into a parse error.
set -u
KIT="${CLAUDE_SESSION_KIT_PREFIX:-$HOME/.claude}/session-kit"
[ -r "$KIT/core/sessions.sh" ] && exit 0
printf '%s' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The session-kit plugin is installed but the kit itself is not: ~/.claude/session-kit/core/sessions.sh is missing. The plugin ships the skills; install.sh ships the libraries those skills run. Every session-kit skill will fail until install.sh has been run from the claude-session-kit checkout, then a new session started. Tell the user this at the start of the reply."}}'
