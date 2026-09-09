# tack

One set of skills, prompts and tools — every agent harness.

Horse *tack* is the gear you put on a harness. Claude Code, Codex, opencode, pi
and whatever ships next month are just harnesses: different system prompts,
different subscriptions, different models. Your actual tooling should not be
duplicated five times to suit them — nor rewritten when one of them is retired
and replaced.

```
$ tack sync
profile personal   config ~/.config/tack
==> claude
  link   ~/.claude/skills/fetch-plane
  render ~/.claude/settings.json
==> codex
  link   ~/.codex/skills/fetch-plane
  render ~/.codex/config.toml
==> pi
  link   ~/.pi/agent/skills/fetch-plane
  link   ~/.pi/AGENTS.md
```

## Why not just symlink the whole directory

Because every harness *writes into its own config directory*. `~/.claude` holds
`sessions/`, `projects/`, `history.jsonl` and credentials; `~/.codex` holds six
SQLite databases and a `.system/` directory nested inside `skills/` that it owns.
Replacing those directories with a symlink to your dotfiles loses the harness's
state, and no two harnesses lay them out the same way.

tack applies two rules instead:

**Link per entry, never per directory.** Each skill, command and agent is
symlinked individually into the destination. The harness keeps ownership of the
directory and everything it writes there. Editing
`~/.claude/skills/foo/SKILL.md` edits the file in your repo, because it is the
same file.

**Render configs, don't link them.** `settings.json`, `config.toml` and
`opencode.json` express the same ideas in different formats and key names, so a
symlink cannot serve all three. One canonical `settings.json` + `mcp.json` is
projected into each harness's own shape. Keys the harness writes back itself
(codex's per-project trust levels) are carried through untouched.

## tack supports no agent tool

Not "supports many" — *none*. There is no built-in list, no registry, and nothing
to upstream. A harness is a file **you** put in your own config directory, and one
tack has never heard of works exactly as well as one it has.

A plugin is a small bash file calling a DSL. This is a complete integration:

```bash
harness claude
probe   claude
root    "$HOME/.claude"

link_dir  skills    "$root/skills"
link_dir  agents    "$root/agents"
link_dir  commands  "$root/commands"
link_file AGENTS.md "$root/CLAUDE.md"

config     "$root/settings.json" json
config_mcp mcpServers
config_map theme theme
```

Awkward tools stay awkward *in the plugin*; the engine learns nothing:

```bash
harness codex
probe   codex
root    "$HOME/.codex"

link_dir  skills   "$root/skills"
link_dir  commands "$root/prompts"      # it calls them prompts
ignore    .system                       # a directory codex owns inside skills/

config          "$root/config.toml" toml   # TOML, not JSON
config_mcp      mcp_servers                # different key
config_preserve projects                   # codex writes this back itself
```

Because plugins are ordinary bash, a harness that needs something no declaration
covers can define `pre_sync()` / `post_sync()` and do it directly.

`tack add` copies a starting point out of `examples/harnesses/` (or a path, or a
URL) into your config, where it becomes yours to edit — tack will never update or
second-guess it. Those examples are unmaintained templates that were accurate
when written, **not supported integrations**. When a tool changes its layout you
fix your own plugin instead of waiting on a release.

Full DSL reference: [docs/harness-plugins.md](docs/harness-plugins.md).

## The two halves

| | What it is | Where it lives |
|---|---|---|
| **The tool** | this repo — engine, DSL, example plugins | installed once per machine |
| **Your config** | `tack.conf`, `core/`, your harness plugins | `~/.config/tack`, a repo *you* own |

Nothing personal lives in the tool, and no tool code lives in your config. You
fork or install this repo, then point it at your own directory.

## Install

```sh
git clone https://github.com/you/tack ~/.local/share/tack
ln -s ~/.local/share/tack/tack ~/.local/bin/tack
tack init          # scaffolds ~/.config/tack
tack add           # list example plugins; `tack add codex` copies one in
tack sync
```

`tack init` creates the directory you commit and clone onto your other machines:

```
~/.config/tack/
  tack.conf           profile, core path, secrets path
  core/
    skills/           linked into every harness that supports skills
    commands/
    agents/
    bin/              scripts on $PATH — see below
    hooks/
    AGENTS.md         one prose file, linked as CLAUDE.md / GEMINI.md / AGENTS.md
    settings.json     canonical config, projected per harness
    mcp.json          MCP servers, declared once
  harnesses/          your harness plugins — tack ships none
  local/              gitignored: secrets.env, profile, machine-only plugins
```

## Profiles: one branch on every machine

A work laptop should not get your personal MCP servers, but maintaining a
divergent branch for it is misery. Entries declare their audience in frontmatter:

```yaml
---
name: internal-deploy
profiles: [work]
---
```

`profiles: [work]` links only under the `work` profile. No declaration means
everywhere. Everything stays committed on one branch — **the filter is applied at
link time**, not at commit time — and switching profiles removes what no longer
applies, it doesn't just add:

```sh
tack sync -p work        # links work-only entries
tack sync -p personal    # and unlinks them again
```

Set the machine's default once in `local/profile` (gitignored, so each machine
keeps its own).

Content that genuinely cannot be committed goes in `local/` instead, including
`local/harnesses/` for machine-only plugins.

## Secrets

Nothing in `core/` should contain a key. Reference them instead:

```json
{ "context7": { "command": "npx",
                "args": ["-y", "@upstash/context7-mcp", "--api-key", "${CONTEXT7_API_KEY}"] } }
```

Values come from `local/secrets.env` (`KEY=value`, gitignored) at render time, so
the repo stays safe to keep on a host your work machine can actually reach.
`tack doctor` greps `core/` for anything that looks like a leaked key.

## Check first whether you need a plugin at all

Some harnesses already read the same directory. `~/.agents/skills/` is read
natively by **Codex, opencode and pi**, so one `link_dir` into it serves all
three — no plugin per tool, no duplication:

```bash
harness shared
probe   --always
link_dir skills "$HOME/.agents/skills"
```

Claude Code is the holdout: its skill paths are hardcoded to `.claude/skills/`
and even `CLAUDE_CONFIG_DIR` is ignored for skills lookup, so it needs its own
links — it does follow symlinks placed there, which is the seam tack uses.

`AGENTS.md` is in better shape: standardised and read by 30+ agents, with Claude
Code again the exception (`CLAUDE.md`).

The full table, with sources and caveats, is in
[docs/shared-directories.md](docs/shared-directories.md). Where tools agree, link
once and stop; where they do not, the difference is a few lines in a plugin you
control.

## The highest-leverage part

Put real capability in `core/bin/` and put it on `$PATH`. Every harness can run a
shell command, so a script there works identically in all of them with **zero**
adapter code — no plugin API, no per-harness port. Skills then become thin
markdown that says when to reach for the tool, and the logic lives outside any
harness entirely.

Same idea for prose: write it once in `core/AGENTS.md` and let the plugins link
it to `CLAUDE.md`, `GEMINI.md`, `AGENTS.md`.

## Commands

```
tack sync                    link core/ into each installed harness, render configs
tack status                  what each harness has linked
tack doctor                  dangling links, leaked secrets, missing local config
tack init                    scaffold a config directory you can commit
tack adopt <path> [subdir]   move an existing file/dir into core/ and link it back
tack add [name|path|url]     copy a harness plugin into your config
tack harnesses               list the plugins you have, and where each was found

  -n, --dry-run     show what would change, touch nothing
  -p, --profile P   override profile
  -H, --harness H   restrict to one harness
  -v, --verbose     show unchanged and profile-skipped entries
```

`tack adopt ~/.claude/skills/my-skill` moves an existing skill into `core/` and
symlinks it back — the migration path off a setup you already have.

Requires bash 4+, python3, and coreutils. Nothing else.
