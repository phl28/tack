#!/usr/bin/env bash
# Inspect a harness plugin before it is installed.
#
# A plugin is bash, and `tack sync` sources it. Fetching one from a URL is
# therefore exactly as dangerous as `curl | bash`, and nothing here changes that:
# this is a review aid, not a sandbox. What it does is refuse to install
# silently, so you see what you are about to run and say yes to it.
#
# The check has three levels:
#
#   declarative  every line is a DSL verb, a comment, or blank. Nothing in the
#                file can execute anything on its own.
#   code         it defines pre_sync/post_sync, or uses shell constructs. Legal
#                and sometimes necessary -- but it is a program, so read it.
#   suspicious   it contains something that has no business in a plugin:
#                network calls, eval, rm -rf, credential paths, base64 decode.
#
# Local files you point at yourself are checked too, but only a remote fetch
# demands confirmation -- copying a file you already have is not a new trust
# decision.

# Verbs the DSL defines. Anything else is not declarative.
_TACK_VERBS='harness|probe|root|link_dir|link_file|ignore|config|config_mcp|config_map|config_preserve'

# Patterns that are never appropriate in a plugin. Deliberately blunt: a false
# positive costs one glance, a false negative costs a machine.
_tack_suspicious_patterns() {
  cat <<'PAT'
curl |fetching from the network
wget |fetching from the network
/dev/tcp|opening a network socket
\bnc \b|opening a network socket
\bssh \b|connecting to another host
\beval\b|evaluating constructed code
\bexec\b|replacing the shell process
base64 *-{1,2}d|decoding hidden content
\bxxd\b|decoding hidden content
rm +-[rRf]|deleting files recursively
\bsudo\b|escalating privileges
\bchmod +[0-7]*7|making something world-writable or setuid
\bchown\b|changing file ownership
crontab|installing a scheduled job
systemctl|changing system services
\.ssh/|touching SSH keys
\.aws/|touching cloud credentials
\.netrc|touching stored credentials
credentials|touching stored credentials
history -c|clearing shell history
>/dev/null 2>&1 *&|backgrounding hidden work
PAT
}

# Classify a file. Echoes "declarative", "code" or "suspicious", and prints
# findings to stderr. Returns 0 unless the file is not a plausible plugin at all.
tack_verify_plugin() {
  local f="$1" verdict=declarative
  local line n=0 stripped

  [[ -s "$f" ]] || { warn "empty file"; return 1; }

  if ! bash -n "$f" 2>/dev/null; then
    warn "does not parse as bash -- refusing"
    return 1
  fi

  grep -qE "^[[:space:]]*harness[[:space:]]|^[[:space:]]*(link_dir|link_file|config|probe)[[:space:]]" "$f" \
    || { warn "no harness/link_dir/config lines -- this does not look like a plugin"; return 1; }

  # Level 2: is any line something other than a verb or a comment?
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((n++))
    stripped="${line%%#*}"
    [[ -z "${stripped// }" ]] && continue
    [[ "$stripped" =~ ^[[:space:]]*($_TACK_VERBS)([[:space:]]|$) ]] && continue
    verdict=code
    break
  done < "$f"

  # Level 3: anything actively alarming, verb line or not.
  local pat desc hits=0
  while IFS='|' read -r pat desc; do
    [[ -n "$pat" ]] || continue
    if grep -qE "$pat" "$f"; then
      warn "$desc  ${C_DIM}(matched /$pat/)${C_0}"
      hits=1
    fi
  done < <(_tack_suspicious_patterns)
  ((hits)) && verdict=suspicious

  printf '%s' "$verdict"
}

# Show the file and make the user commit to it. $2 is where it came from.
tack_review_plugin() {
  local f="$1" origin="$2" verdict
  verdict="$(tack_verify_plugin "$f")" || return 1

  case "$verdict" in
    declarative)
      say "  ${C_OK}declarative${C_0} -- every line is a tack verb; the file cannot run anything itself"
      ;;
    code)
      say "  ${C_WARN}contains shell code${C_0} -- legal (pre_sync/post_sync are a feature), but it is a"
      say "  program that will run as you on every ${C_B}tack sync${C_0}. Read it."
      ;;
    suspicious)
      say "  ${C_ERR}suspicious${C_0} -- see the findings above. A harness plugin has no legitimate"
      say "  reason to do these things."
      ;;
  esac

  say ""
  say "${C_DIM}--- $origin ---${C_0}"
  sed 's/^/  /' "$f"
  say "${C_DIM}--- end ---${C_0}"
  say ""

  [[ "$verdict" == declarative ]] && return 0

  # Anything beyond declarative needs a real yes. With no terminal to ask at --
  # a pipeline, a script, CI -- the answer is no. Refusing is the safe default;
  # a plugin the user genuinely wants is one `tack add` away interactively.
  if open_tty 2>/dev/null; then
    confirm "Install it anyway?" n && return 0
    return 1
  fi
  warn "no terminal to confirm at -- not installing code unreviewed"
  return 1
}
