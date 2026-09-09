# opencode -- https://opencode.ai
harness opencode
probe   opencode
root    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

# Redundant with shared.sh: this tool reads ~/.agents/skills natively.
# Keep one or the other, not both.
link_dir  skills    "$root/skills"
link_dir  commands  "$root/command"
link_dir  agents    "$root/agent"
link_file AGENTS.md "$root/AGENTS.md"

config     "$root/opencode.json" json
config_mcp mcp
