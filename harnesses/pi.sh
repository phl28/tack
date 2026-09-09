# pi
harness pi
probe   pi
root    "$HOME/.pi"

link_dir  skills     "$root/agent/skills"
link_dir  commands   "$root/agent/commands"
link_dir  extensions "$root/agent/extensions"
link_file AGENTS.md  "$root/AGENTS.md"
