#!/usr/bin/env bash
# `tack new` -- interactive harness plugin generator.
#
# Writing a plugin is six lines, but only once you know which six. This asks the
# questions in the order the DSL wants them, defaults everything it can, checks
# the answers against what is actually on disk, and writes a commented file you
# own outright.
#
# It generates a starting point, not a finished integration: the paths it
# suggests are conventions, and only the tool's own docs can confirm them.

# --- prompting ----------------------------------------------------------------
# Input comes from the terminal rather than stdin, so the wizard still works when
# stdout is piped. It is opened ONCE on fd 3 -- reopening per question would
# re-read the first answer forever when the source is a file. $TACK_TTY overrides
# the source, which is how the tests feed it answers.
#
# Prompts go to the terminal too, so `tack new > plugin.sh` would still be
# usable; the questions do not end up in the redirect.
# A failed redirection on `exec` kills a non-interactive shell outright, and `||`
# does not catch it -- so probe each end in a subshell before committing to it.
# /dev/tty can exist and still not be openable when there is no controlling
# terminal, which is exactly the case a bare `-w` test gets wrong.
open_tty() {
  local src="${TACK_TTY:-/dev/tty}"
  ( exec 3< "$src" ) 2>/dev/null || return 1
  exec 3< "$src"
  if ( exec 4> /dev/tty ) 2>/dev/null; then exec 4> /dev/tty; else exec 4>&2; fi
}

# The local scratch variable is deliberately obscure: `ask ans ...` is a natural
# call, and a local named `ans` here would shadow the caller's variable so
# printf -v wrote to the wrong one.
ask() {  # ask VAR "question" "default"
  local __var="$1" __q="$2" __def="${3:-}" __ans
  if [[ -n "$__def" ]]; then
    printf '%s%s%s [%s%s%s]: ' "$C_B" "$__q" "$C_0" "$C_OK" "$__def" "$C_0" >&4
  else
    printf '%s%s%s: ' "$C_B" "$__q" "$C_0" >&4
  fi
  IFS= read -r -u 3 __ans || __ans=""
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

confirm() {  # confirm "question" [y|n]
  local q="$1" def="${2:-y}" ans hint
  [[ "$def" == y ]] && hint="Y/n" || hint="y/N"
  printf '%s%s%s [%s]: ' "$C_B" "$q" "$C_0" "$hint" >&4
  IFS= read -r -u 3 ans || ans=""
  ans="${ans:-$def}"
  [[ "${ans,,}" == y* ]]
}

# Narration shares the prompts' destination, so a redirect captures only the
# generated plugin.
w_say() { printf '%s\n' "$*" >&4; }
w_hdr() { printf '%s%s%s\n' "$C_B" "$*" "$C_0" >&4; }

# Mark a path so the user can see whether their guess matches reality.
mark() {
  if   [[ -d "$1" ]]; then printf '%s(exists)%s' "$C_OK" "$C_0"
  elif [[ -e "$1" ]]; then printf '%s(exists, not a directory)%s' "$C_WARN" "$C_0"
  else printf '%s(does not exist yet)%s' "$C_DIM" "$C_0"
  fi
}

# --- the wizard ---------------------------------------------------------------
cmd_new() {
  open_tty || die "tack new needs a terminal -- copy an example with 'tack add' instead"

  local name="" probe_kind="" probe="" root="" dest="" file="" fmt="" \
        mcp_key="" preserve="" ans=""
  local -a links=() files=() maps=() preserves=()

  w_say ""
  w_hdr "New harness plugin"
  w_say "${C_DIM}Answer what you know; press enter to take the default. Nothing is written"
  w_say "until you confirm at the end, and the file is yours to edit afterwards.${C_0}"
  w_say ""

  # 1. identity ----------------------------------------------------------------
  while :; do
    ask name "Name of the harness (lowercase, e.g. claude, codex, mytool)" "${1:-}"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { warn "letters, digits, - and _ only"; continue; }
    [[ -e "$TACK_HOME/harnesses/$name.sh" ]] \
      && { warn "$TACK_HOME/harnesses/$name.sh already exists"; confirm "Overwrite it?" n || continue; }
    break
  done

  w_say ""
  w_say "${C_DIM}How should tack tell whether this tool is installed on a machine? Harnesses"
  w_say "that fail this check are skipped, which is what lets one config serve"
  w_say "machines with different tools on them.${C_0}"
  ask ans "Command on \$PATH, a /path to test for, or 'always'" "$name"
  case "$ans" in
    always|--always) probe_kind=always; probe="" ;;
    /*|~*|\$*)       probe_kind=path;   probe="$ans" ;;
    *)               probe_kind=cmd;    probe="$ans" ;;
  esac
  if [[ "$probe_kind" == cmd ]] && ! command -v "$probe" >/dev/null 2>&1; then
    warn "'$probe' is not on \$PATH here -- fine if you are writing this for another machine"
  fi

  # 2. root --------------------------------------------------------------------
  w_say ""
  local root_guess="\$HOME/.$name"
  for c in "$HOME/.$name" "${XDG_CONFIG_HOME:-$HOME/.config}/$name"; do
    [[ -d "$c" ]] && { root_guess="${c/#$HOME/\$HOME}"; break; }
  done
  ask root "Config directory for this tool" "$root_guess"
  local root_real="${root/#\$HOME/$HOME}"
  w_say "  $(mark "$root_real") $root_real"

  # 3. what to link ------------------------------------------------------------
  w_say ""
  w_hdr "What should tack link into it?"
  w_say "${C_DIM}Each entry in a core/ directory is symlinked individually, so the tool keeps"
  w_say "ownership of the destination and whatever state it writes there."
  w_say "Enter accepts the suggestion; type ${C_0}-${C_DIM} to skip a category.${C_0}"
  w_say ""

  local sub subs=()
  shopt -s nullglob
  for sub in "$CORE"/*/; do subs+=("$(basename "$sub")"); done
  shopt -u nullglob
  ((${#subs[@]})) || subs=(skills commands agents hooks)

  for sub in "${subs[@]}"; do
    [[ "$sub" == bin ]] && continue   # bin belongs on $PATH, not in a harness dir
    local guess="\$root/$sub"
    [[ -d "$root_real/$sub" ]] || guess=""
    # a few tools rename these; offer the real directory if we can see one
    if [[ -z "$guess" ]]; then
      case "$sub" in
        commands) [[ -d "$root_real/prompts" ]] && guess="\$root/prompts" ;;
        agents)   [[ -d "$root_real/agent"   ]] && guess="\$root/agent"   ;;
      esac
    fi
    [[ -z "$guess" ]] && guess="-"      # nothing on disk suggests it; skip by default
    ask dest "  core/$sub  ->" "$guess"
    [[ -n "$dest" && "$dest" != - && "$dest" != none ]] && links+=("$sub|$dest")
  done

  # 4. AGENTS.md ---------------------------------------------------------------
  w_say ""
  w_say "${C_DIM}One prose file linked wherever this tool looks for its instructions."
  w_say "Most read AGENTS.md; Claude Code reads CLAUDE.md. ${C_0}-${C_DIM} to skip.${C_0}"
  ask dest "  core/AGENTS.md  ->" "\$root/AGENTS.md"
  [[ -n "$dest" && "$dest" != - && "$dest" != none ]] && files+=("AGENTS.md|$dest")

  # 5. config ------------------------------------------------------------------
  w_say ""
  if confirm "Does this tool have a config file tack should generate?" y; then
    local cfg_guess=""
    for c in settings.json config.toml config.json "$name.json" config.yaml; do
      [[ -f "$root_real/$c" ]] && { cfg_guess="\$root/$c"; break; }
    done
    ask file "  Config file path" "${cfg_guess:-\$root/settings.json}"

    case "$file" in
      *.toml) fmt=toml ;; *.yaml|*.yml) fmt=yaml ;; *.jsonc) fmt=jsonc ;; *) fmt=json ;;
    esac
    ask fmt "  Format (json, jsonc, toml, yaml)" "$fmt"

    w_say ""
    w_say "${C_DIM}  MCP servers are declared once in core/mcp.json and written into each"
    w_say "  tool's own key. Claude Code uses mcpServers, Codex mcp_servers, opencode"
    w_say "  mcp. Dotted paths work, e.g. tools.mcp. Blank if it has no MCP support.${C_0}"
    ask mcp_key "  MCP key" "mcpServers"
    [[ "$mcp_key" == - || "$mcp_key" == none ]] && mcp_key=""

    w_say ""
    w_say "${C_DIM}  Keys this tool writes back into its own config -- project trust levels,"
    w_say "  onboarding flags, cached tokens. Naming them keeps rendering from"
    w_say "  destroying them. Space-separated, blank for none.${C_0}"
    ask preserve "  Keys to preserve" ""
    for ans in $preserve; do preserves+=("$ans"); done

    if confirm "  Map a shared knob from core/settings.json into this config?" n; then
      w_say "${C_DIM}  e.g. 'theme theme', or 'theme ui.colorScheme' if it calls it something else."
      w_say "  Blank line to finish.${C_0}"
      while :; do
        ask ans "    from to" ""
        [[ -z "$ans" ]] && break
        maps+=("${ans%% *}|${ans#* }")
      done
    fi
  fi

  # 6. write -------------------------------------------------------------------
  local out; out="$(new_render)"
  w_say ""
  w_hdr "harnesses/$name.sh"
  w_say "$C_DIM$(sed 's/^/  /' <<< "$out")$C_0"
  w_say ""

  ((DRY)) && { say "${C_WARN}dry run -- not written${C_0}"; return 0; }
  confirm "Write this to $TACK_HOME/harnesses/$name.sh?" y || { say "nothing written"; return 0; }

  mkdir -p "$TACK_HOME/harnesses"
  printf '%s\n' "$out" > "$TACK_HOME/harnesses/$name.sh"
  note "new" "$TACK_HOME/harnesses/$name.sh"
  w_say ""
  w_say "  Preview what it would do:  ${C_B}tack sync -n -H $name${C_0}"
  w_say "  Then, for real:            ${C_B}tack sync -H $name${C_0}"
  w_say ""
  w_say "${C_DIM}  The file is yours -- tack will never update or second-guess it."
  w_say "  Verbs and escape hatches: docs/harness-plugins.md${C_0}"
}

# Build the plugin text from what the wizard collected. Aligned like the
# examples, because the file is meant to be read and edited by hand.
new_render() {
  local pair w=0 k
  for pair in "${links[@]}" "${files[@]}"; do
    k="${pair%%|*}"; ((${#k} > w)) && w=${#k}
  done
  ((w < 9)) && w=9   # 'AGENTS.md'

  printf '# %s -- written by `tack new`. Yours to edit.\n' "$name"
  printf '#\n'
  printf '# Paths here are a starting point, not verified fact. Check them against the\n'
  printf "# tool's own docs, and see docs/harness-plugins.md for the full DSL.\n"
  printf '\n'
  printf 'harness %s\n' "$name"
  case "$probe_kind" in
    cmd)    printf 'probe   %s\n' "$probe" ;;
    path)   printf 'probe   --path "%s"\n' "$probe" ;;
    always) printf 'probe   --always\n' ;;
  esac
  [[ -n "$root" ]] && printf 'root    "%s"\n' "$root"

  if ((${#links[@]} || ${#files[@]})); then
    printf '\n'
    for pair in "${links[@]}"; do
      printf 'link_dir  %-*s "%s"\n' "$w" "${pair%%|*}" "${pair#*|}"
    done
    for pair in "${files[@]}"; do
      printf 'link_file %-*s "%s"\n' "$w" "${pair%%|*}" "${pair#*|}"
    done
  fi

  if [[ -n "${file:-}" ]]; then
    printf '\n'
    printf 'config          "%s" %s\n' "$file" "$fmt"
    [[ -n "${mcp_key:-}" ]] && printf 'config_mcp      %s\n' "$mcp_key"
    for pair in "${maps[@]}"; do
      printf 'config_map      %s %s\n' "${pair%%|*}" "${pair#*|}"
    done
    for k in "${preserves[@]}"; do
      printf 'config_preserve %s\n' "$k"
    done
  fi
}
