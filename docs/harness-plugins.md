# Writing a harness plugin

tack does not support any agent tool. It supports *plugins*, and a plugin is how
you teach it about a tool you use. There is no built-in list, no registry, and
nothing to upstream — a harness tack has never heard of works exactly as well as
one it has, because they go through the same six verbs.

Plugins live in `$TACK_HOME/harnesses/*.sh` (committed, shared between your
machines) and `$TACK_HOME/local/harnesses/*.sh` (gitignored, this machine only).
Later wins, so a local file shadows a committed one of the same name.

## The whole of a simple plugin

```bash
harness mytool
probe   mytool
root    "$HOME/.mytool"

link_dir  skills    "$root/skills"
link_file AGENTS.md "$root/AGENTS.md"
```

That is a complete, working integration. `tack sync` will now link every skill in
your `core/skills/` into `~/.mytool/skills/`, one symlink per skill, and link your
one `AGENTS.md` to where that tool looks for it.

## Verbs

### Identity

| | |
|---|---|
| `harness NAME` | what this harness is called in output and `-H`. Defaults to the filename. |
| `probe CMD` | the harness counts as installed if `CMD` is on `$PATH`. |
| `probe --path P` | …if the path `P` exists instead. Use for tools with no CLI. |
| `probe --always` | always run this plugin. |
| `root PATH` | sets `$root` for later lines. Purely a convenience. |

Harnesses that fail their probe are skipped silently, which is what lets one
config directory serve machines with different tools installed.

### Linking

| | |
|---|---|
| `link_dir CORE_SUB DEST` | link each entry of `core/CORE_SUB` **individually** into `DEST` |
| `link_file CORE_PATH DEST` | link one file from `core/` to `DEST` |
| `ignore GLOB` | never link entries matching `GLOB` |

`link_dir` is the important one, and the per-entry rule is the reason tack exists.
It does **not** replace `DEST` with a symlink to your directory; it creates one
symlink per skill inside it. Harnesses write their own state into these
directories — sessions, databases, credentials, generated subdirectories — and
replacing the directory destroys that. Linking per entry leaves the harness
owning its directory while your content sits alongside.

Editing through the link edits the file in your repo. They are the same file.

`CORE_SUB` is any directory name you like under `core/`. `link_dir prompts` works
if you make a `core/prompts`; nothing is hardcoded.

### Config

| | |
|---|---|
| `config PATH FORMAT` | render a config file. Format: `json`, `jsonc`, `toml`, `yaml`. |
| `config_mcp KEYPATH` | dotted key your MCP registry is written to |
| `config_map FROM TO` | map a `common` knob to a dotted key path in this config |
| `config_preserve KEY` | a top-level key the harness writes itself; carried through untouched |

Configs are **generated**, not linked, because harnesses express the same ideas
in different formats and key names and one symlink cannot serve them all. Your
`core/settings.json` holds the truth:

```json
{
  "common":  { "theme": "dark", "web_search": true },
  "harness": { "mytool": { "model": "some-model" } }
}
```

`harness.mytool` is passed through verbatim. `common` is projected wherever
`config_map` says it goes, so one `theme` setting reaches a tool that calls it
`theme` and one that calls it `ui.colorScheme`:

```bash
config_map theme theme
config_map theme ui.colorScheme     # in a different plugin
```

`config_preserve` matters more than it looks. Some harnesses write back into
their own config file — per-project trust levels, onboarding flags, cached
tokens. Naming those keys keeps rendering from destroying them.

Anything already at the destination that tack did not generate is backed up to
`*.pre-tack.bak` before the first write.

### Escape hatch

Plugins are bash. If a harness needs something no verb covers, define a function:

```bash
post_sync() {
  # runs after linking and rendering for this harness
  mytool cache rebuild >/dev/null 2>&1
}
```

`pre_sync()` runs before. Both have `$CORE`, `$PROFILE`, `$root` and `$DRY` in
scope, and can call `link_entry SRC DEST` directly. Respect `$DRY`:

```bash
post_sync() { ((DRY)) || mytool reload; }
```

## A harder plugin

Everything awkward belongs in the plugin. The engine never learns a special case:

```bash
harness codex
probe   codex
root    "$HOME/.codex"

link_dir  skills   "$root/skills"
link_dir  commands "$root/prompts"      # it calls them prompts
ignore    .system                       # a directory codex creates inside skills/

config          "$root/config.toml" toml   # TOML, not JSON
config_mcp      mcp_servers                # different key name
config_map      web_search tools.web_search
config_preserve projects                   # codex writes trust levels back here
```

## Getting started

The quickest way is to let tack ask:

```sh
tack new
```

It asks what the tool is called, how to tell whether it is installed, where its
config directory is and what it reads, checking each answer against what is
actually on disk, then writes a commented plugin for you to edit.

`tack add` copies an existing one instead — the examples bundled with the tool, a
path, or a URL:

```sh
tack add            # list them
tack add codex      # copy examples/harnesses/codex.sh into your harnesses/
tack add ./my.sh    # or from a path
tack add https://…  # or a URL
```

Those examples are unmaintained starting points that were accurate when written,
not supported integrations. Once copied, the file is yours — tack will never
update or second-guess it. When a tool changes its layout, you fix your own
plugin instead of waiting on anyone.

`tack sync` sources every plugin, so installing one is a decision to run its
code. `tack add` inspects a plugin before it lands: a file that is nothing but
tack verbs installs quietly, one that defines `pre_sync`/`post_sync` is shown to
you and needs confirming, and one that touches the network, `eval`, `rm -rf` or
credential paths is flagged line by line and defaults to no. With no terminal to
confirm at, anything past declarative is refused. It makes you read the code; it
does not make the code safe.

## Before you write one

Check whether the harness already reads a directory another one reads. Several
tools scan `~/.agents/skills/` natively, and for those a single `link_dir` into
that one path serves all of them at once — no plugin per tool. See
[shared-directories.md](shared-directories.md).
