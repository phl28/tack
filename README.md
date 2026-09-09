# tack

Your agent setup, on every machine, in every tool.

Write a skill once. It shows up in Claude Code, Codex, opencode, pi and whatever
ships next month — on your desktop, your laptop, and your work machine — and it
stays in step as you change it.

Horse *tack* is the gear you put on a harness. The agent CLIs are just harnesses:
different system prompts, different subscriptions, different models. Your actual
tooling should not be duplicated five times to suit them.

```sh
curl -fsSL https://raw.githubusercontent.com/phl28/tack/main/install.sh | bash
```

---

## Getting started

### On the machine you already use

Set up the directory that holds everything:

```sh
tack init
```

That creates `~/.config/tack` — the thing you will share between machines. It is
empty except for a skeleton, so bring in what you already have:

```sh
tack adopt ~/.claude/skills/my-skill      # moves it in, symlinks it back
tack adopt ~/.codex/prompts/review.md commands
```

`adopt` **moves** the file into your config and leaves a symlink behind, so the
tool you took it from carries on working — same file, new home.

Now teach tack about the agent tools you use. It ships with support for none of
them on purpose (more on that below), so this is how it learns:

```sh
tack new          # asks a few questions, writes the plugin for you
```

Then link everything into everything:

```sh
tack sync
```

```
profile personal   config ~/.config/tack
==> claude
  link   ~/.claude/skills/my-skill
  link   ~/.claude/CLAUDE.md
  render ~/.claude/settings.json
==> codex
  link   ~/.codex/skills/my-skill
  render ~/.codex/config.toml
```

That is the local half done. **Editing `~/.claude/skills/my-skill/SKILL.md` now
edits the file in your config directory** — they are the same file, so there is
never a copy to keep in step.

### Share it

Create an **empty private repo** on GitHub — call it `tack-config` — then:

```sh
tack remote git@github.com:you/tack-config.git
tack push
```

Private, because this holds your prompts and your harness config. Secrets are
kept out of it by design (see below), but the rest is still yours.

tack keeps no credentials and no git identity of its own. It uses whatever git
and your credential helper are already set up with on that machine.

### On your next machine

Install tack, clone your config into place, and link it:

```sh
curl -fsSL https://raw.githubusercontent.com/phl28/tack/main/install.sh | bash
git clone git@github.com:you/tack-config.git ~/.config/tack
tack sync
```

No `tack init` — the clone *is* the setup. Every skill, prompt and harness plugin
you had is now wired into every agent tool on the new machine.

### Keeping in step

```sh
tack push          # commit everything here and send it
tack pull          # take your other machines' changes, then re-link
tack status        # what is linked, and whether you are ahead or behind
```

`tack pull` runs `sync` for you, because pulling changes what should be linked.

```
$ tack status
profile:  personal
config:   ~/.config/tack
remote:   git@github.com:you/tack-config.git  [2 to push]

  claude     7 linked   cfg: json
  codex      7 linked   cfg: toml
  pi         not installed
```

## The work laptop problem

Your work machine should not get your personal MCP servers, and maintaining a
separate branch for it is misery. Instead, entries say who they are for:

```yaml
---
name: internal-deploy
profiles: [work]
---
```

`profiles: [work]` links only on machines running the `work` profile. Anything
that says nothing links everywhere. **One repo, one branch, every machine** — the
filter is applied when linking, not when committing, and switching profiles takes
things away as well as adding them:

```sh
tack sync -p work        # links work-only entries
tack sync -p personal    # and unlinks them again
```

Set each machine's default once in `local/profile`. `local/` is gitignored, so
it never travels — it is also where anything you genuinely cannot commit goes,
including machine-only harness plugins in `local/harnesses/`.

## Secrets

Nothing in your config should contain a key. Reference it instead:

```json
{ "context7": { "command": "npx",
                "args": ["-y", "@upstash/context7-mcp", "--api-key", "${CONTEXT7_API_KEY}"] } }
```

The value lives in `local/secrets.env` (`KEY=value`, never committed) and is
filled in when configs are rendered. `tack push` refuses to publish anything in
your config that looks like a credential, and `tack doctor` checks the same thing
on demand.

This is what makes a private GitHub repo a safe place to keep this, which matters
when one of your machines cannot reach your homelab.

---

## How it works

Two rules, and they are the whole design.

**Link per entry, never per directory.** Every harness *writes into its own
config directory* — `~/.claude` holds `sessions/`, `projects/`, `history.jsonl`
and credentials; `~/.codex` holds SQLite databases and a `.system/` directory
nested inside `skills/` that it owns. Replacing those directories with a symlink
to your dotfiles destroys that state, and no two harnesses lay them out the same
way. So each skill, command and agent is symlinked *individually* into the
destination: the harness keeps its directory, your content sits alongside, and
editing through the link edits the original.

**Render configs, don't link them.** `settings.json`, `config.toml` and
`opencode.json` express the same ideas in different formats and key names, so one
symlink cannot serve them all. One canonical `settings.json` + `mcp.json` is
projected into each harness's own shape. Keys a harness writes back itself —
codex's per-project trust levels — are carried through untouched.

### tack supports no agent tool

Not "supports many" — *none*. There is no built-in list, no registry, and nothing
to upstream. A harness is a file **you** put in your own config directory, and one
tack has never heard of works exactly as well as one it has.

A plugin is a small bash file. This is a complete integration:

```bash
harness claude
probe   claude
root    "$HOME/.claude"

link_dir  skills    "$root/skills"
link_dir  commands  "$root/commands"
link_file AGENTS.md "$root/CLAUDE.md"

config     "$root/settings.json" json
config_mcp mcpServers
```

Awkward tools stay awkward *in the plugin*; the engine learns nothing:

```bash
harness codex
probe   codex
root    "$HOME/.codex"

link_dir  commands "$root/prompts"      # it calls them prompts
ignore    .system                       # a directory codex owns inside skills/

config          "$root/config.toml" toml   # TOML, not JSON
config_mcp      mcp_servers                # different key
config_preserve projects                   # codex writes this back itself
```

`tack new` writes one of these for you by asking questions. `tack add` copies an
existing one — from the bundled examples, a path, or a URL. Either way it lands
in your config as *yours*: tack never updates or second-guesses it, so when a
tool changes its layout you fix your own file instead of waiting on a release.

Because plugins are ordinary bash, anything the verbs do not cover can be done in
a `pre_sync()` / `post_sync()` function. Full reference:
[docs/harness-plugins.md](docs/harness-plugins.md).

### Installing a plugin is a decision to run it

`tack sync` sources every plugin, so adding one from a URL is as dangerous as
`curl | bash`. `tack add` fetches to a temp file, inspects it, prints it in full,
and classifies it before anything reaches your config:

- **declarative** — every line is a tack verb; the file cannot execute anything
  on its own. Installs without ceremony.
- **contains shell code** — defines `pre_sync`/`post_sync` or uses shell
  constructs. Legal, but it runs as you on every sync, so you confirm first.
- **suspicious** — network calls, `eval`, `rm -rf`, credential paths. Flagged
  line by line, and confirmation defaults to no.

With no terminal to confirm at, anything past *declarative* is refused rather
than installed silently. It is a review aid, not a sandbox: it makes you look at
the code, it does not make the code safe.

### Check whether you need a plugin at all

Some tools already read the same directory. `~/.agents/skills/` is read natively
by **Codex, opencode and pi**, so one `link_dir` into it serves all three:

```bash
harness shared
probe   --always
link_dir skills "$HOME/.agents/skills"
```

Claude Code is the holdout — its skill paths are hardcoded — but it does follow
symlinks placed there, which is the seam tack uses. Details and caveats:
[docs/shared-directories.md](docs/shared-directories.md).

### Put real capability in `core/bin`

The highest-leverage thing here is not config sync. Every harness can run a shell
command, so a script in `core/bin` on your `$PATH` works identically in all of
them with **zero** adapter code — no plugin API, no per-harness port. Skills then
become thin markdown saying when to reach for the tool, and the logic lives
outside any harness entirely.

Same for prose: write it once in `core/AGENTS.md` and let your plugins link it
wherever each tool looks for it.

---

## Layout

```
~/.config/tack/          <- the repo you share between machines
  tack.conf              profile, core path, secrets path
  core/
    skills/              linked into every harness that takes skills
    commands/
    agents/
    bin/                 scripts on $PATH
    AGENTS.md            one prose file, linked wherever each tool wants it
    settings.json        canonical config, projected per harness
    mcp.json             MCP servers, declared once
  harnesses/             your harness plugins — tack ships none
  local/                 gitignored: secrets.env, profile, machine-only plugins
```

The tool itself installs to `~/.local/share/tack` and holds nothing personal.
Your config directory holds no tool code. Upgrading one never touches the other.

## Commands

```
tack init                    create your config directory
tack sync                    link everything into every installed harness
tack status                  what is linked, and your remote's state
tack doctor                  dangling links, leaked secrets, missing config

tack push [message]          commit and publish to your remote
tack pull                    take other machines' changes, then re-link
tack remote [url]            show or set where your config is shared

tack new [name]              write a harness plugin by answering questions
tack add [name|path|url]     copy a harness plugin in (no args lists examples)
tack adopt <path> [subdir]   move an existing file into core/ and link it back
tack harnesses               list your plugins and where each came from

  -n, --dry-run     show what would change, touch nothing
  -p, --profile P   override profile for this run
  -H, --harness H   restrict to one harness
  -v, --verbose     show unchanged and profile-skipped entries
```

## Installing

```sh
curl -fsSL https://raw.githubusercontent.com/phl28/tack/main/install.sh | bash
```

Goes into `~/.local/share/tack`, links `tack` into `~/.local/bin`. Re-run to
upgrade; your config is never touched. Needs bash 4+, python3, curl and tar.

Rather read it first:

```sh
curl -fsSLO https://raw.githubusercontent.com/phl28/tack/main/install.sh
less install.sh && bash install.sh
```
