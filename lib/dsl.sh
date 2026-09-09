#!/usr/bin/env bash
# The harness DSL.
#
# The engine knows nothing about any specific agent tool. Every harness -- claude,
# codex, pi, whatever you add tomorrow -- is a plugin file in harnesses/ (or
# local/harnesses/ for machine-only ones) that calls the verbs below.
#
# The common case is six declarative lines. When a harness does something no
# declaration can express, the plugin is still just bash: define pre_sync() or
# post_sync(), or call link_entry / emit / run directly. Nothing is privileged.
#
#   harness NAME                 identify the plugin (defaults to the filename)
#   probe CMD|--path P|--always  when is this harness considered present here
#   root PATH                    sets $root, used by later paths
#
#   link_dir  CORE_SUB DEST      link each entry of core/CORE_SUB into DEST,
#                                individually -- DEST itself is never replaced
#   link_file CORE_PATH DEST     link one file from core/ to DEST
#   ignore    GLOB               never link entries matching GLOB
#
#   config PATH FORMAT           render a config file (json|toml|jsonc|yaml)
#   config_mcp KEYPATH           dotted key the MCP registry is written to
#   config_map FROM TO           map a core/settings.json "common" knob to a
#                                dotted key path in this harness's config
#   config_preserve KEY          top-level key the harness writes itself and
#                                that rendering must carry through untouched
#
#   pre_sync() / post_sync()     optional functions, run around the above
#
# Everything a plugin sets lives in plugin-scoped variables that the engine
# resets between harnesses, so plugins cannot leak into each other.

h_reset() {
  H_NAME=""; H_PROBE=""; H_PROBE_KIND="cmd"; H_ROOT=""
  H_LINK_DIRS=(); H_LINK_FILES=(); H_IGNORE=()
  H_CFG_PATH=""; H_CFG_FMT=""; H_CFG_MCP=""; H_CFG_MAP=(); H_CFG_PRESERVE=()
  unset -f pre_sync post_sync 2>/dev/null || true
  root=""
}

harness() { H_NAME="$1"; }

probe() {
  case "$1" in
    --path)   H_PROBE_KIND=path;   H_PROBE="$2" ;;
    --always) H_PROBE_KIND=always; H_PROBE="" ;;
    *)        H_PROBE_KIND=cmd;    H_PROBE="$1" ;;
  esac
}

root() { H_ROOT="$(h_expand "$1")"; root="$H_ROOT"; }

link_dir()  { H_LINK_DIRS+=("$1|$(h_expand "$2")"); }
link_file() { H_LINK_FILES+=("$1|$(h_expand "$2")"); }
ignore()    { H_IGNORE+=("$1"); }

config()          { H_CFG_PATH="$(h_expand "$1")"; H_CFG_FMT="${2:-json}"; }
config_mcp()      { H_CFG_MCP="$1"; }
config_map()      { H_CFG_MAP+=("$1|$2"); }
config_preserve() { H_CFG_PRESERVE+=("$1"); }

# $root and $HOME expansion without eval'ing arbitrary plugin text.
h_expand() {
  local s="$1"
  s="${s//\$root/$H_ROOT}"; s="${s//\$\{root\}/$H_ROOT}"
  s="${s//\$HOME/$HOME}";   s="${s//\$\{HOME\}/$HOME}"
  printf '%s' "$s"
}
