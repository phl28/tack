# Gemini CLI -- https://github.com/google-gemini/gemini-cli
harness gemini
probe   gemini
root    "$HOME/.gemini"

link_dir  commands  "$root/commands"
link_file AGENTS.md "$root/GEMINI.md"

config     "$root/settings.json" json
config_mcp mcpServers
