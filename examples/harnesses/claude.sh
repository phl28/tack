# Claude Code -- https://claude.com/claude-code
harness claude
probe   claude
root    "$HOME/.claude"

link_dir  skills    "$root/skills"
link_dir  agents    "$root/agents"
link_dir  commands  "$root/commands"
link_dir  hooks     "$root/hooks"
link_file AGENTS.md "$root/CLAUDE.md"

config           "$root/settings.json" json
config_mcp       mcpServers
config_map       theme theme
# settings.local.json is the harness's own per-machine file; we never touch it.
