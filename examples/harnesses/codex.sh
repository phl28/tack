# Codex CLI -- https://github.com/openai/codex
#
# The awkward one, and a good demonstration that awkwardness belongs in the
# plugin rather than the engine: TOML instead of JSON, a different key for MCP
# servers, prompts instead of commands, and it writes back into its own config
# file (per-project trust levels) which rendering must not destroy.
harness codex
probe   codex
root    "$HOME/.codex"

# Redundant with shared.sh: this tool reads ~/.agents/skills natively.
# Keep one or the other, not both.
link_dir  skills    "$root/skills"
link_dir  commands  "$root/prompts"
link_file AGENTS.md "$root/AGENTS.md"

# Codex creates a .system/ dir inside skills/ that it owns -- leave it alone.
ignore .system

config           "$root/config.toml" toml
config_mcp       mcp_servers
config_map       web_search tools.web_search
config_preserve  projects
