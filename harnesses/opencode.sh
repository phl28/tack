# opencode -- https://opencode.ai
harness opencode
probe   opencode
root    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

link_dir  skills    "$root/skills"
link_dir  commands  "$root/command"
link_dir  agents    "$root/agent"
link_file AGENTS.md "$root/AGENTS.md"

config     "$root/opencode.json" json
config_mcp mcp
