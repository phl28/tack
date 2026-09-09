#!/usr/bin/env bash
# Sharing your config between machines.
#
# Your config directory is an ordinary git repository, and these are thin
# wrappers over git that know two things it does not:
#
#   - local/ must never be pushed. It holds secrets and per-machine state, and
#     it is gitignored from the moment `tack init` runs.
#   - a push is a publish. Everything in core/ is scanned for anything that
#     looks like a key before it leaves the machine.
#
# There is deliberately no credential handling here. Whatever git already uses
# on this machine -- SSH agent, credential helper, gh -- is what gets used, so
# there is nothing extra to configure and no token for tack to store.

_git() { git -C "$TACK_HOME" "$@"; }

_git_ready() {
  command -v git >/dev/null 2>&1 || die "git is not installed"
  [[ -d "$TACK_HOME/.git" ]] || die "$TACK_HOME is not a git repository yet -- run 'tack remote <url>'"
}

_git_remote_url() { _git remote get-url origin 2>/dev/null; }

_git_branch() { _git symbolic-ref --quiet --short HEAD 2>/dev/null || echo main; }

# tack stores no git identity of its own -- it uses whatever git is already
# configured to use on this machine. On a fresh machine there may be none, and
# git's own error for that is confusing, so say it plainly instead.
_git_identity() {
  local name email
  name="$(_git config user.name 2>/dev/null || true)"
  email="$(_git config user.email 2>/dev/null || true)"
  [[ -n "$name" && -n "$email" ]] && return 0
  say ""
  warn "git does not know who you are on this machine yet"
  say ""
  say "    ${C_B}git config --global user.name  \"Your Name\"${C_0}"
  say "    ${C_B}git config --global user.email \"you@example.com\"${C_0}"
  say ""
  say "  ${C_DIM}tack keeps no identity or credentials of its own; it uses whatever git"
  say "  and your credential helper are already set up with.${C_0}"
  return 1
}

# Refuse to publish anything that looks like a credential. core/ is shared;
# local/ is not scanned because it never leaves the machine.
_secret_scan() {
  local hits
  hits="$(grep -rIlE '(sk-[A-Za-z0-9]|ctx7sk-|ghp_|gho_|github_pat_|AIza|xox[baprs]-|-----BEGIN [A-Z ]*PRIVATE KEY)[A-Za-z0-9_-]*' \
          "$CORE" "$TACK_HOME/harnesses" 2>/dev/null || true)"
  [[ -z "$hits" ]] && return 0
  say ""
  warn "these files look like they contain a credential:"
  local f; while IFS= read -r f; do [[ -n "$f" ]] && say "    ${f#$TACK_HOME/}"; done <<< "$hits"
  say ""
  say "  ${C_DIM}Move the value into ${C_0}local/secrets.env${C_DIM} (never committed) and reference it"
  say "  as \${NAME} in core/mcp.json -- it is filled in when configs are rendered.${C_0}"
  say ""
  return 1
}

# --- tack remote --------------------------------------------------------------
cmd_remote() {
  local url="${1:-}"
  command -v git >/dev/null 2>&1 || die "git is not installed"

  if [[ -z "$url" ]]; then
    if [[ -d "$TACK_HOME/.git" ]] && url="$(_git_remote_url)" && [[ -n "$url" ]]; then
      say "$url"
      return 0
    fi
    say "No remote set. Create an empty ${C_B}private${C_0} repo on GitHub, then:"
    say ""
    say "    ${C_B}tack remote git@github.com:you/tack-config.git${C_0}"
    say ""
    say "${C_DIM}Private matters: this directory holds your prompts and your harness"
    say "config. Secrets stay out of it by design -- they live in local/, which is"
    say "gitignored -- but the rest is still yours, not the world's.${C_0}"
    return 0
  fi

  ((DRY)) && { say "would set origin to $url"; return 0; }

  if [[ ! -d "$TACK_HOME/.git" ]]; then
    _git init -q
    _git symbolic-ref HEAD refs/heads/main
    note "git" "initialised $TACK_HOME"
  fi

  # .gitignore is what keeps local/ out of the repo -- make sure it is there
  # before anything can be committed.
  if [[ ! -f "$TACK_HOME/.gitignore" ]]; then
    printf 'local/\n*.pre-tack.bak\n' > "$TACK_HOME/.gitignore"
    note "git" "wrote .gitignore (local/ is never pushed)"
  fi

  if _git remote get-url origin >/dev/null 2>&1; then
    _git remote set-url origin "$url"
    note "git" "origin -> $url"
  else
    _git remote add origin "$url"
    note "git" "origin = $url"
  fi
  say ""
  say "  Now: ${C_B}tack push${C_0}"
}

# --- tack push ----------------------------------------------------------------
cmd_push() {
  _git_ready
  local msg="${1:-}" url branch
  url="$(_git_remote_url)" || url=""
  [[ -n "$url" ]] || die "no remote set -- 'tack remote <url>' first"

  _secret_scan || die "not pushing (use 'git -C $TACK_HOME push' yourself if this is a false positive)"

  if [[ -z "$(_git status --porcelain)" ]] && _git diff --quiet "@{upstream}" 2>/dev/null; then
    say "nothing to push -- ${C_OK}up to date${C_0}"
    return 0
  fi

  say "${C_B}$TACK_HOME${C_0} ${C_DIM}-> $url${C_0}"
  _git -c color.status=always status --short | sed 's/^/  /'
  say ""
  ((DRY)) && { say "${C_WARN}dry run -- nothing committed or pushed${C_0}"; return 0; }

  _git_identity || return 1

  branch="$(_git_branch)"
  _git add -A
  if [[ -n "$(_git diff --cached --name-only)" ]]; then
    [[ -n "$msg" ]] || msg="tack: update from $(hostname -s 2>/dev/null || echo this machine)"
    _git commit -q -m "$msg" || die "commit failed"
    note "commit" "$msg"
  fi

  if _git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
    _git push -q origin "$branch" || die "push failed -- 'tack pull' first if the remote has moved on"
  else
    _git push -q -u origin "$branch" || die "push failed"
  fi
  note "push" "origin/$branch"
}

# --- tack pull ----------------------------------------------------------------
cmd_pull() {
  _git_ready
  local branch; branch="$(_git_branch)"
  [[ -n "$(_git_remote_url)" ]] || die "no remote set -- 'tack remote <url>' first"

  ((DRY)) && { say "would pull origin/$branch and re-sync"; return 0; }

  if [[ -n "$(_git status --porcelain)" ]]; then
    warn "you have uncommitted changes here -- 'tack push' them first, or stash them"
    _git status --short | sed 's/^/    /'
    return 1
  fi

  _git pull -q --rebase origin "$branch" || die "pull failed"
  note "pull" "origin/$branch"

  # Pulling changes what should be linked, so linking again is the point.
  say ""
  cmd_sync
}

# --- tack status, git half ----------------------------------------------------
# Printed by `tack status` so one command answers "am I in sync" in both senses.
git_status_line() {
  [[ -d "$TACK_HOME/.git" ]] || { say "remote:   ${C_DIM}not a git repo -- 'tack remote <url>' to share this${C_0}"; return; }
  local url branch ahead behind dirty=""
  url="$(_git_remote_url)" || url=""
  branch="$(_git_branch)"
  [[ -n "$(_git status --porcelain)" ]] && dirty=" ${C_WARN}(uncommitted changes)${C_0}"

  if [[ -z "$url" ]]; then
    say "remote:   ${C_DIM}none${C_0}$dirty"
    return
  fi
  _git fetch -q origin "$branch" 2>/dev/null || true
  ahead="$(_git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)"
  behind="$(_git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)"

  local state="${C_OK}in sync${C_0}"
  ((ahead))  && state="${C_WARN}$ahead to push${C_0}"
  ((behind)) && state="${C_WARN}$behind to pull${C_0}"
  ((ahead && behind)) && state="${C_WARN}$ahead to push, $behind to pull${C_0}"
  say "remote:   $url  [$state]$dirty"
}
