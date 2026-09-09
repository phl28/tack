# ~/.agents/skills -- one directory read natively by Codex, opencode and pi.
#
# Where harnesses already agree on a path, you do not need a plugin per tool:
# link into the shared path once and every tool that reads it is served. Verified
# September 2026; see docs/shared-directories.md for the table and caveats.
#
# probe --always because this is a convention, not a program: there is nothing
# on $PATH to test for. The directory is useful the moment any tool reading it
# is installed, and harmless when none is.
harness shared
probe   --always

link_dir skills "$HOME/.agents/skills"
