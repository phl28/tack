# pi -- https://pi.dev
harness pi
probe   pi
root    "$HOME/.pi"

# Redundant with shared.sh: pi reads ~/.agents/skills natively.
# Keep one or the other, not both.
link_dir  skills     "$root/agent/skills"
link_dir  commands   "$root/agent/commands"
link_dir  extensions "$root/agent/extensions"
link_file AGENTS.md  "$root/AGENTS.md"
