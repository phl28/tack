#!/usr/bin/env bash
# tack installer.
#
#   curl -fsSL https://raw.githubusercontent.com/phl28/tack/main/install.sh | bash
#
# Downloads a release tarball into ~/.local/share/tack and links the `tack`
# entry point into ~/.local/bin. No git, no build step, nothing outside those
# two paths. Re-running it upgrades in place and never touches your config.
#
# Environment:
#   TACK_INSTALL_DIR   where the tool goes      (default ~/.local/share/tack)
#   TACK_BIN_DIR       where the symlink goes   (default ~/.local/bin)
#   TACK_REF           branch or tag to install (default main)
#   TACK_REPO          source repo              (default phl28/tack)
set -euo pipefail

REPO="${TACK_REPO:-phl28/tack}"
REF="${TACK_REF:-main}"
INSTALL_DIR="${TACK_INSTALL_DIR:-$HOME/.local/share/tack}"
BIN_DIR="${TACK_BIN_DIR:-$HOME/.local/bin}"

if [[ -t 1 ]]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; R=$'\033[31m'; N=$'\033[0m'
else B=; G=; Y=; D=; R=; N=; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s%s%s %s\n' "$G" "✓" "$N" "$*"; }
warn() { printf '  %swarn%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# --- requirements -------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"; }
need curl
need tar
need python3

# bash 4+ for associative arrays; macOS ships 3.2 as /bin/bash.
bash_major="$(bash -c 'echo ${BASH_VERSINFO[0]}')"
if ((bash_major < 4)); then
  die "tack needs bash 4 or newer (found $bash_major).
  On macOS: brew install bash -- the installed tack runs under /usr/bin/env bash,
  so a newer bash earlier in \$PATH is enough; you do not need to change shells."
fi

say ""
say "${B}Installing tack${N} ${D}($REPO@$REF)${N}"
say ""

# --- download -----------------------------------------------------------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tack-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

url="https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF"
curl -fsSL --proto '=https' --max-time 60 "$url" -o "$tmp/tack.tar.gz" \
  || curl -fsSL --proto '=https' --max-time 60 \
       "https://codeload.github.com/$REPO/tar.gz/refs/tags/$REF" -o "$tmp/tack.tar.gz" \
  || die "could not download $REPO@$REF"
ok "downloaded"

mkdir -p "$tmp/x"
tar -xzf "$tmp/tack.tar.gz" -C "$tmp/x" --strip-components=1
[[ -f "$tmp/x/tack" && -d "$tmp/x/lib" ]] || die "archive does not look like tack"

# Sanity-check what we are about to install rather than trusting the tarball.
bash -n "$tmp/x/tack" || die "downloaded tack does not parse"
for f in "$tmp/x"/lib/*.sh; do bash -n "$f" || die "downloaded $f does not parse"; done
ok "verified"

# --- install ------------------------------------------------------------------
upgrade=0
[[ -e "$INSTALL_DIR/tack" ]] && upgrade=1

mkdir -p "$INSTALL_DIR"
# Replace only what the tool owns. A user who put anything else in here keeps it.
for item in tack lib examples docs README.md; do
  [[ -e "$tmp/x/$item" ]] || continue
  rm -rf "${INSTALL_DIR:?}/$item"
  cp -R "$tmp/x/$item" "$INSTALL_DIR/$item"
done
chmod +x "$INSTALL_DIR/tack"
ok "$( ((upgrade)) && echo upgraded || echo installed ) $INSTALL_DIR"

mkdir -p "$BIN_DIR"
if [[ -e "$BIN_DIR/tack" && ! -L "$BIN_DIR/tack" ]]; then
  warn "$BIN_DIR/tack exists and is not a symlink -- leaving it alone"
  warn "run tack as $INSTALL_DIR/tack, or remove that file and re-run this"
else
  ln -sfn "$INSTALL_DIR/tack" "$BIN_DIR/tack"
  ok "linked $BIN_DIR/tack"
fi

# --- next steps ---------------------------------------------------------------
say ""
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    warn "$BIN_DIR is not on your \$PATH. Add it:"
    say ""
    say "    ${B}export PATH=\"\$PATH:$BIN_DIR\"${N}   ${D}# in ~/.bashrc, ~/.zshrc or config.fish${N}"
    say ""
    ;;
esac

if ((upgrade)); then
  say "${G}Upgraded.${N} Your config in ${B}${TACK_HOME:-~/.config/tack}${N} is untouched."
  say ""
  say "  ${B}tack status${N}    what each harness has linked"
  say "  ${B}tack sync${N}      re-link after the upgrade"
else
  say "${G}Installed.${N} Next:"
  say ""
  say "  ${B}tack init${N}      create ~/.config/tack -- the directory you commit and share"
  say "  ${B}tack new${N}       teach it about an agent tool by answering a few questions"
  say "  ${B}tack sync${N}      link your skills and prompts into every tool you have"
  say ""
  say "${D}tack supports no agent tool out of the box. A harness is a plugin you write"
  say "(about six lines) or copy with 'tack add' -- so a tool it has never heard of"
  say "works exactly as well as one it has.${N}"
fi
say ""
