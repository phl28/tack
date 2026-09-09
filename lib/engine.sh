#!/usr/bin/env bash
# Engine: profile gating, per-entry linking, plugin execution.
# Knows nothing about any specific harness.

# --- profile gating -----------------------------------------------------------
# An entry declares its audience in YAML frontmatter:  profiles: [work, personal]
# Undeclared means "common" -- present everywhere.
entry_profiles() {
  local entry="$1" f=""
  for c in SKILL.md AGENT.md COMMAND.md README.md; do
    [[ -f "$entry/$c" ]] && { f="$entry/$c"; break; }
  done
  [[ -z "$f" && -f "$entry" ]] && f="$entry"
  [[ -n "$f" ]] || { echo common; return; }
  local line
  line="$(awk 'NR==1 && $0!="---"{exit} NR>1{ if($0=="---") exit; print }' "$f" 2>/dev/null \
          | grep -m1 -E '^profiles:' || true)"
  [[ -n "$line" ]] || { echo common; return; }
  printf '%s' "$line" | sed -E 's/^profiles:[[:space:]]*//; s/[][,"'"'"']/ /g' | tr -s ' '
}

wanted() {
  local p
  for p in $(entry_profiles "$1"); do
    [[ "$p" == common || "$p" == all || "$p" == "$PROFILE" ]] && return 0
  done
  return 1
}

ignored() {
  local name="$1" g
  for g in "${H_IGNORE[@]}"; do [[ "$name" == $g ]] && return 0; done
  return 1
}

# --- linking ------------------------------------------------------------------
# Link ONE entry. Idempotent, and refuses to clobber anything that is not
# already a link of ours. This per-entry rule is the whole trick: the harness
# keeps ownership of the destination directory and everything it writes there.
link_entry() {
  local src="$1" target="$2" cur
  if [[ -L "$target" ]]; then
    cur="$(readlink "$target")"
    [[ "$(readlink -f "$target" 2>/dev/null)" == "$(readlink -f "$src")" ]] && return 0
    if [[ "$cur" == "$TACK_HOME"/* || "$cur" == "$CORE"/* || ! -e "$target" ]]; then
      ((DRY)) || { rm -f "$target"; mkdir -p "$(dirname "$target")"; ln -s "$src" "$target"; }
      note "relink" "$target"; return 0
    fi
    warn "skip $target -> points outside your config ($cur)"; return 1
  fi
  if [[ -e "$target" ]]; then
    warn "skip $target -> a real file is already there ('tack import' takes it over)"; return 1
  fi
  ((DRY)) || { mkdir -p "$(dirname "$target")"; ln -s "$src" "$target"; }
  note "link" "$target"
}

# Remove links we own that the current profile no longer selects, so switching
# profiles actually takes things away instead of only adding.
prune_dir() {
  local dest="$1" t cur
  [[ -d "$dest" ]] || return 0
  shopt -s nullglob
  for t in "$dest"/*; do
    [[ -L "$t" ]] || continue
    cur="$(readlink "$t")"
    [[ "$cur" == "$CORE"/* ]] || continue
    [[ -e "$t" ]] && wanted "$(readlink -f "$t")" && ! ignored "$(basename "$t")" && continue
    ((DRY)) || rm -f "$t"
    note "unlink" "$t"
  done
  shopt -u nullglob
}

# --- running one plugin -------------------------------------------------------
run_harness() {
  local file="$1" pair sub dest src name

  h_reset
  # shellcheck disable=SC1090
  source "$file" || { warn "plugin failed to load: $file"; return 1; }
  [[ -n "$H_NAME" ]] || H_NAME="$(basename "$file" .sh)"

  [[ -n "$ONLY" && "$ONLY" != "$H_NAME" ]] && return 0

  case "$H_PROBE_KIND" in
    cmd)    command -v "$H_PROBE" >/dev/null 2>&1 || { dim "==> $H_NAME (not installed)"; return 0; };;
    path)   [[ -e "$(h_expand "$H_PROBE")" ]]     || { dim "==> $H_NAME (not installed)"; return 0; };;
    always) ;;
  esac

  hdr "==> $H_NAME"
  declare -F pre_sync >/dev/null && pre_sync

  for pair in "${H_LINK_DIRS[@]}"; do
    sub="${pair%%|*}"; dest="${pair#*|}"
    [[ -d "$CORE/$sub" ]] || continue
    prune_dir "$dest"
    shopt -s nullglob
    for src in "$CORE/$sub"/*; do
      name="$(basename "$src")"
      ignored "$name" && continue
      wanted "$src"   || { ((VERBOSE)) && dim "  --     $name (profile)"; continue; }
      link_entry "$src" "$dest/$name"
    done
    shopt -u nullglob
  done

  for pair in "${H_LINK_FILES[@]}"; do
    src="$CORE/${pair%%|*}"; dest="${pair#*|}"
    [[ -e "$src" ]] || continue
    link_entry "$src" "$dest"
  done

  [[ -n "$H_CFG_PATH" ]] && render_config

  declare -F post_sync >/dev/null && post_sync
  return 0
}

# --- config rendering ---------------------------------------------------------
# Configs are GENERATED, not linked -- they differ in format per harness, so one
# canonical source is projected into each. This is the one place where editing
# the destination does not flow back; edit $CORE/settings.json instead.
render_config() {
  local map_args=() preserve_args=() p
  for p in "${H_CFG_MAP[@]}";      do map_args+=(--map "$p"); done
  for p in "${H_CFG_PRESERVE[@]}"; do preserve_args+=(--preserve "$p"); done

  TACK_DRY="$DRY" python3 "$LIB/render.py" \
    --settings "$CORE/settings.json" \
    --mcp      "$CORE/mcp.json" \
    --profile  "$PROFILE" \
    --harness  "$H_NAME" \
    --out      "$H_CFG_PATH" \
    --format   "$H_CFG_FMT" \
    ${H_CFG_MCP:+--mcp-key "$H_CFG_MCP"} \
    "${map_args[@]}" "${preserve_args[@]}" \
    ${SECRETS_FILE:+--secrets "$SECRETS_FILE"}
}
