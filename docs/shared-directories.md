# Do harnesses already share a directory?

Before writing a plugin, check whether the tool reads a path another tool already
reads. Where they do, you need no plugin for it — or a much smaller one.

Checked September 2026. Verify against the tool's own docs before relying on any
of it — layouts change, and tools get retired and replaced.

## Skills: `~/.agents/skills/` is real, and most tools read it

| Tool | Reads `~/.agents/skills/` | Own global path |
|---|---|---|
| **Codex CLI** | **yes** | `~/.codex/skills/` |
| **opencode** | **yes** (also `~/.claude/skills/`) | `~/.config/opencode/skills/` |
| **pi** | **yes** | `~/.pi/agent/skills/` |
| **Claude Code** | **no** | `~/.claude/skills/` |

So for Codex, opencode and pi, one directory genuinely serves all three. Point
your skills at `~/.agents/skills/` and they are done — no linking, no
duplication, no plugin per tool.

Claude Code is the holdout: its skill paths are hardcoded to `.claude/skills/`,
and even `CLAUDE_CONFIG_DIR` does not move skills lookup.

It does, however, **follow symlinks** placed in its skills directory, and
deduplicates when several paths resolve to the same target. That is the seam.

### What this means for your config

A minimal setup is one real directory plus one symlink:

```bash
# harnesses/shared.sh -- serves codex, opencode and pi at once
harness shared
probe   --always
link_dir skills "$HOME/.agents/skills"
```

```bash
# harnesses/claude.sh -- the one tool that needs its own copy of the links
harness claude
probe   claude
link_dir skills "$HOME/.claude/skills"
```

Two plugins, several tools. If Claude Code ships a configurable skills path,
delete the second one.

## AGENTS.md: solved, except for Claude Code

`AGENTS.md` was standardised in August 2025 and donated to the Linux Foundation's
Agentic AI Foundation in December 2025. 30+ agents read it, Codex, opencode and
pi among them.

Claude Code still loads `CLAUDE.md`. Two ways around it, both fine:

- symlink it — `link_file AGENTS.md "$HOME/.claude/CLAUDE.md"`
- or put `@AGENTS.md` on the first line of `CLAUDE.md` and let it import

## Relocating a whole config directory

Several tools let you move their entire home, which sounds like a solution and
is not:

| Tool | Variable |
|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` (but skills lookup ignores it — see above) |
| Codex | `CODEX_HOME` |
| opencode | `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR` |

These **relocate**, they do not **merge**. Pointing two harnesses at one directory
collides their session state, credentials and databases in a single tree. They
are useful for isolating a work profile from a personal one, not for sharing.

## MCP servers

No shared location and no cross-tool standard. Every harness declares servers in
its own file under its own key — `mcpServers` for Claude Code, `mcp_servers` for
Codex, `mcp` for opencode — in JSON or TOML depending on the tool. Some keep them
in a separate file from their settings entirely. This is the case rendering
exists for.

## Reading the table honestly

The Agent Skills specification defines *what a skill directory contains* — the
`SKILL.md` format, frontmatter fields, `scripts/` and `references/` conventions.
It deliberately says nothing about **where** those directories live. Every path
above is vendor convention, not standard, and can change in a point release.

Which is the argument for a linking tool rather than betting everything on the
convention: where tools agree, link once into the shared path and stop; where
they do not, the difference is a few lines in a plugin you control.

