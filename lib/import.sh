#!/usr/bin/env bash
# `tack import` -- take over what is already on this machine, resolving copies.
#
# The first time you use tack, your skills already exist -- often the same skill
# in three harness directories, copied there months apart and edited in one place
# but not the others. Adopting them naively would either pick a version at random
# or push three near-identical copies to your remote.
#
# So: find every real (non-symlinked) entry across every harness, group them by
# name, hash the contents, and only ask about the ones that actually disagree.
# Identical copies collapse silently -- there is no decision to make. Divergent
# ones are shown with a diff, and you choose.
#
# This is also what to run on a second machine that already had its own setup
# before you cloned your config onto it.

# --- content identity ---------------------------------------------------------
# One hash per entry, whether it is a single file or a directory tree. Paths are
# included so a moved file counts as a change; mtimes are not, so a copy made by
# `cp` still matches its source.
_entry_hash() {
  local p="$1"
  if [[ -f "$p" ]]; then
    sha256sum < "$p" | cut -d' ' -f1
  elif [[ -d "$p" ]]; then
    ( cd "$p" 2>/dev/null || exit
      find . -type f -print0 2>/dev/null | LC_ALL=C sort -z \
        | xargs -0 -r sha256sum 2>/dev/null | sha256sum
    ) | cut -d' ' -f1
  else
    echo missing
  fi
}

_entry_when() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown"; }

_entry_size() {
  local n
  n="$(du -sh "$1" 2>/dev/null | cut -f1)"
  printf '%s' "${n:-?}"
}

# Show what actually differs between two entries.
_entry_diff() {
  local a="$1" b="$2" opts=(-u)
  [[ -d "$a" || -d "$b" ]] && opts=(-ru)
  if command -v diff >/dev/null 2>&1; then
    diff "${opts[@]}" "$a" "$b" 2>/dev/null | head -80 | sed 's/^/    /'
  else
    say "    (diff not available)"
  fi
}

# --- collecting ---------------------------------------------------------------
# Every real entry sitting in a destination any plugin links into. Symlinks we
# already own are skipped -- those are managed, not candidates.
#
# Emits: <core-subdir>|<name>|<path>|<harness>
_collect_candidates() {
  local f pair sub dest entry name
  while IFS= read -r f; do
    h_reset
    source "$f" 2>/dev/null || continue
    [[ -n "$H_NAME" ]] || H_NAME="$(basename "$f" .sh)"

    case "$H_PROBE_KIND" in
      cmd)  command -v "$H_PROBE" >/dev/null 2>&1 || continue ;;
      path) [[ -e "$(h_expand "$H_PROBE")" ]]     || continue ;;
    esac

    for pair in "${H_LINK_DIRS[@]}"; do
      sub="${pair%%|*}"; dest="${pair#*|}"
      [[ -d "$dest" ]] || continue
      shopt -s nullglob
      for entry in "$dest"/*; do
        name="$(basename "$entry")"
        [[ -L "$entry" ]] && continue          # already managed, or someone else's link
        ignored "$name" && continue            # the harness's own, e.g. codex .system
        printf '%s|%s|%s|%s\n' "$sub" "$name" "$entry" "$H_NAME"
      done
      shopt -u nullglob
    done
  done < <(resolve_plugins)
}

# --- resolving ----------------------------------------------------------------
# Adopt SRC into core/SUB as NAME, then point every location that held a copy at
# it. That last part is what makes the duplicates actually go away.
_adopt_as() {
  local src="$1" sub="$2" name="$3"; shift 3
  local locations=("$@") loc
  local target="$CORE/$sub/$name"

  ((DRY)) && { say "  would adopt $src -> core/$sub/$name"; return 0; }

  mkdir -p "$CORE/$sub"
  if [[ -e "$target" ]]; then
    rm -rf "$target"
  fi
  cp -R "$src" "$target"

  for loc in "${locations[@]}"; do
    rm -rf "$loc"
    ln -s "$target" "$loc"
  done
  note "import" "core/$sub/$name  ${C_DIM}(${#locations[@]} location(s) linked)${C_0}"
}

cmd_import() {
  [[ -d "$CORE" ]] || die "no core/ at $CORE -- run 'tack init' first"

  local rows; rows="$(_collect_candidates)"
  [[ -n "$rows" ]] || { say "${C_OK}nothing to import${C_0} -- no unmanaged files in any harness directory"; return 0; }

  # Group by subdir + name.
  local -A group_paths=() group_harnesses=()
  local row sub name path harness key
  while IFS='|' read -r sub name path harness; do
    [[ -n "$name" ]] || continue
    key="$sub|$name"
    group_paths[$key]+="$path"$'\n'
    group_harnesses[$key]+="$harness "
  done <<< "$rows"

  say "${C_B}Importing what is already on this machine${C_0}"
  say "${C_DIM}Copies with identical content are merged without asking. Only entries whose"
  say "contents actually differ need a decision.${C_0}"
  say ""

  local resolved=0 skipped=0
  for key in "${!group_paths[@]}"; do
    sub="${key%%|*}"; name="${key#*|}"

    # Variants: distinct content hashes, each with the paths that have it.
    local -a paths=()
    while IFS= read -r path; do [[ -n "$path" ]] && paths+=("$path"); done <<< "${group_paths[$key]}"

    local -A by_hash=()
    local -a hashes=()
    local p h
    for p in "${paths[@]}"; do
      h="$(_entry_hash "$p")"
      [[ -v by_hash[$h] ]] || hashes+=("$h")
      by_hash[$h]+="$p"$'\n'
    done

    # The version already in your config counts as a variant too.
    local core_entry="$CORE/$sub/$name" core_hash=""
    if [[ -e "$core_entry" ]]; then
      core_hash="$(_entry_hash "$core_entry")"
      [[ -v by_hash[$core_hash] ]] || { hashes+=("$core_hash"); by_hash[$core_hash]=""; }
    fi

    # One version everywhere: nothing to decide.
    if ((${#hashes[@]} == 1)); then
      if [[ -n "$core_hash" ]]; then
        # already in config and identical -- just replace the copies with links
        _adopt_as "$core_entry" "$sub" "$name" "${paths[@]}"
      else
        _adopt_as "${paths[0]}" "$sub" "$name" "${paths[@]}"
      fi
      ((resolved++))
      continue
    fi

    # --- they disagree ---------------------------------------------------------
    say ""
    say "${C_WARN}⚠${C_0}  ${C_B}$sub/$name${C_0} exists in more than one version:"
    say ""

    local -a variant_src=() variant_locs=()
    local i=0 v_paths label
    for h in "${hashes[@]}"; do
      ((i++))
      local -a locs=()
      while IFS= read -r p; do [[ -n "$p" ]] && locs+=("$p"); done <<< "${by_hash[$h]}"

      local src_path="" where=""
      if [[ "$h" == "$core_hash" && ${#locs[@]} -eq 0 ]]; then
        src_path="$core_entry"; where="your config (core/$sub/$name)"
      else
        src_path="${locs[0]}"
        where="$(printf '%s\n' "${locs[@]}" | sed "s|^$HOME|~|" | paste -sd', ')"
        [[ "$h" == "$core_hash" ]] && where="$where, and matches your config"
      fi

      variant_src+=("$src_path")
      variant_locs+=("$(printf '%s\n' "${locs[@]+"${locs[@]}"}" | paste -sd'|')")

      printf '  %s[%d]%s %s\n' "$C_B" "$i" "$C_0" "$where"
      printf '      %smodified %s, %s%s\n' "$C_DIM" "$(_entry_when "$src_path")" "$(_entry_size "$src_path")" "$C_0"
    done

    say ""
    local choice
    while :; do
      ask choice "  Keep which? [1-$i], (d)iff, (s)kip" "1"
      case "$choice" in
        d|diff)
          say ""
          say "  ${C_DIM}[1] vs [2]:${C_0}"
          _entry_diff "${variant_src[0]}" "${variant_src[1]}"
          say ""
          continue
          ;;
        s|skip)
          warn "skipped $sub/$name -- copies left as they are"
          ((skipped++)); choice=""; break
          ;;
        [0-9]*)
          ((choice >= 1 && choice <= i)) && break
          warn "pick 1-$i, d, or s"
          ;;
        *) warn "pick 1-$i, d, or s" ;;
      esac
    done
    [[ -z "$choice" ]] && continue

    _adopt_as "${variant_src[$((choice-1))]}" "$sub" "$name" "${paths[@]}"
    ((resolved++))
  done

  say ""
  say "${C_OK}$resolved imported${C_0}$( ((skipped)) && printf ', %s%d skipped%s' "$C_WARN" "$skipped" "$C_0")"
  if ((resolved)); then
    say ""
    say "  Everything now lives in ${C_B}$CORE${C_0} and is linked back where it came from."
    say "  Next: ${C_B}tack sync${C_0}, then ${C_B}tack push${C_0} to share it."
  fi
}

# Are there unmanaged copies lying around? Used by sync and doctor to point at
# import rather than leaving the user with an unexplained skip.
import_pending() {
  local rows; rows="$(_collect_candidates 2>/dev/null)"
  [[ -n "$rows" ]] && printf '%s' "$(wc -l <<< "$rows")"
}
