# Agent instructions

One file, every harness. Your plugins link this wherever each tool looks for it
-- `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.pi/AGENTS.md` -- so the prose
you write here is what every agent reads.

## Conventions

- Prefer scripts in `core/bin` over harness-specific plugin systems: every
  harness can run a shell command, so a tool that lives on `$PATH` works
  everywhere with no adapter code at all.
- Skills should be thin: describe when to use the tool and what the arguments
  mean; keep the logic in `core/bin`.
