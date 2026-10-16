#!/usr/bin/env bash
# os-tools.sh — install the OS-level tools Claude Code (and its plugins/hooks) need.
#
# Two tiers:
#   required   the tools Claude Code itself and its installed plugins call:
#              ripgrep, git, curl, nodejs, npm, python3, ca-certificates,
#              openssh-client, unzip, xz-utils, build-essential, tmux
#   recommended the tools agent workflows actually reach for: jq, pip, venv,
#              python3-yaml, fd, shellcheck, tree, htop, pkg-config, cmake,
#              zip, gnupg, libsecret-tools, dbus-x11
#
# Distro packages are preferred (they get security updates). Only the apt path is
# exercised by the author — dnf/pacman/apk mappings are best-effort.
#
# When sudo is unavailable the script does NOT hang: it prints the exact command
# to run and (unless --no-user-fallback) installs user-space binaries for the
# tools that ship official static releases (ripgrep, fd, shellcheck) into
# ~/.local/bin.
#
# Usage: ./os-tools.sh [--required-only] [--dry-run] [--no-user-fallback] [-h]
set -euo pipefail

ONLY_REQUIRED=0
DRY_RUN=0
USER_FALLBACK=1

if [ -t 1 ]; then R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; RED=$'\033[0;31m'
  GR=$'\033[0;32m'; YE=$'\033[0;33m'; BL=$'\033[0;34m'; CY=$'\033[0;36m'
else R=; B=; D=; RED=; GR=; YE=; BL=; CY=; fi
ok()   { echo "  ${GR}+${R} $*"; }
skip() { echo "  ${YE}-${R} ${D}$*${R}"; }
warn() { echo "  ${YE}!${R} $*"; }
fail() { echo "  ${RED}x${R} $*" >&2; }
info() { echo "  ${BL}>${R} $*"; }
step() { echo; echo "${B}${CY}$*${R}"; printf '%s\n' "${D}────────────────────────────────────────────────────${R}"; }
run()  { if [ "$DRY_RUN" = 1 ]; then echo "  ${D}[dry-run] $*${R}"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --required-only) ONLY_REQUIRED=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-user-fallback) USER_FALLBACK=0; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) fail "unknown option: $1"; exit 2 ;;
  esac
done

REQUIRED=(ripgrep git curl nodejs npm python3 ca-certificates openssh-client unzip xz-utils build-essential tmux)
RECOMMENDED=(jq python3-pip python3-venv python3-yaml fd-find shellcheck tree htop pkg-config cmake zip gnupg libsecret-tools dbus-x11)

# package-name translation per distro family (only entries that differ are listed)
translate() {  # translate <canonical> <family>
  local p="$1" f="$2"
  case "$f:$p" in
    dnf:build-essential)     echo "@development-tools" ;;
    dnf:fd-find)             echo "fd" ;;
    dnf:python3-yaml)        echo "python3-pyyaml" ;;
    dnf:openssh-client)      echo "openssh-clients" ;;
    dnf:pkg-config)          echo "pkgconf" ;;
    dnf:dbus-x11)            echo "dbus-x11" ;;
    pacman:build-essential)  echo "base-devel" ;;
    pacman:fd-find)          echo "fd" ;;
    pacman:python3-yaml)     echo "python-yaml" ;;
    pacman:openssh-client)   echo "openssh" ;;
    pacman:pkg-config)       echo "pkgconf" ;;
    pacman:ca-certificates)  echo "ca-certificates-utils" ;;
    apk:xz-utils)            echo "xz" ;;
    apk:build-essential)     echo "build-base" ;;
    apk:fd-find)             echo "fd" ;;
    apk:python3-yaml)        echo "py3-yaml" ;;
    apk:openssh-client)      echo "openssh-client" ;;
    apk:pkg-config)          echo "pkgconf" ;;
    *) echo "$p" ;;
  esac
}

# ── detect the package manager ────────────────────────────────────────────────
step "Environment"
if   command -v apt-get >/dev/null 2>&1; then FAMILY=apt;    INSTALL_CMD="apt-get install -y"; UPDATE_CMD="apt-get update"
elif command -v dnf     >/dev/null 2>&1; then FAMILY=dnf;    INSTALL_CMD="dnf install -y";     UPDATE_CMD="dnf check-update || true"
elif command -v pacman  >/dev/null 2>&1; then FAMILY=pacman; INSTALL_CMD="pacman -S --noconfirm --needed"; UPDATE_CMD="pacman -Sy"
elif command -v apk     >/dev/null 2>&1; then FAMILY=apk;    INSTALL_CMD="apk add";            UPDATE_CMD="apk update"
else FAMILY=unknown; fi
info "package manager: $FAMILY"
if [ "$FAMILY" != "apt" ] && [ "$FAMILY" != "unknown" ]; then
  warn "$FAMILY mapping is best-effort — only the apt path is tested by the author"
fi

SUDO=""
if [ "$(id -u)" = 0 ]; then SUDO=""
elif sudo -n true 2>/dev/null; then SUDO="sudo"; info "sudo: passwordless"
else info "sudo: password required (running as $(id -un))"; fi

if [ "$ONLY_REQUIRED" = 1 ]; then WANT=("${REQUIRED[@]}"); else WANT=("${REQUIRED[@]}" "${RECOMMENDED[@]}"); fi

pkg_installed() {  # pkg_installed <apt-name>
  case "$FAMILY" in
    apt)    dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf)    rpm -q "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    apk)    apk info -e "$1" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

# ── what is missing ───────────────────────────────────────────────────────────
step "Package status"
MISSING_REQ=(); MISSING_REC=(); MISSING_PKGS=()
for p in "${WANT[@]}"; do
  tp="$(translate "$p" "$FAMILY")"
  if pkg_installed "$tp"; then skip "$p"
  else
    case " ${REQUIRED[*]} " in *" $p "*) MISSING_REQ+=("$p") ;; esac
    case " ${RECOMMENDED[*]} " in *" $p "*) MISSING_REC+=("$p") ;; esac
    MISSING_PKGS+=("$tp")
    warn "$p missing  ${D}(package: $tp)${R}"
  fi
done
[ ${#MISSING_PKGS[@]} -eq 0 ] && { echo; ok "nothing to do — every package in scope is installed"; exit 0; }

# ── install ───────────────────────────────────────────────────────────────────
step "Install (${#MISSING_PKGS[@]} packages)"
if [ "$FAMILY" = unknown ]; then
  fail "no supported package manager — install manually: ${MISSING_PKGS[*]}"
elif [ -n "$SUDO" ] || [ "$(id -u)" = 0 ]; then
  run $SUDO sh -c "$UPDATE_CMD" || warn "package index update failed — continuing"
  run $SUDO sh -c "$INSTALL_CMD ${MISSING_PKGS[*]}" || fail "install command failed"
else
  echo "  ${B}Run this and the OS packages are done:${R}"
  echo
  echo "    sudo $UPDATE_CMD"
  echo "    sudo $INSTALL_CMD ${MISSING_PKGS[*]}"
  echo
fi

# ── user-space fallback for the tools that ship static releases ───────────────
if [ "$USER_FALLBACK" = 1 ] && { [ -z "$SUDO" ] && [ "$(id -u)" != 0 ] || [ "$DRY_RUN" = 1 ]; }; then
  step "User-space fallback (no sudo) → ~/.local/bin"
  BIN="$HOME/.local/bin"
  resolve_tag() {  # resolve_tag <owner/repo> <pinned>
    if command -v gh >/dev/null 2>&1; then
      timeout 30 gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null || echo "$2"
    else echo "$2"; fi
  }
  install_static() {  # install_static <name> <url> <strip-pattern> <binary>
    local name="$1" url="$2" member="$3" bin="$4" tmp
    if command -v "$bin" >/dev/null 2>&1 && [ "${bin}" != "rg" ]; then skip "$bin already on PATH"; return 0; fi
    if [ -x "$BIN/$bin" ]; then skip "$BIN/$bin already installed"; return 0; fi
    tmp="$(mktemp -d)"
    info "downloading $name"
    if ! run curl -fsSL "$url" -o "$tmp/pkg"; then warn "download failed: $name"; rm -rf "$tmp"; return 1; fi
    if ! run tar -xf "$tmp/pkg" -C "$tmp"; then warn "extract failed (missing xz?): $name"; rm -rf "$tmp"; return 1; fi
    local src
    src="$(find "$tmp" -type f -name "$member" -perm -u+x | head -1)"
    [ -n "$src" ] || { warn "binary $member not found in archive: $name"; rm -rf "$tmp"; return 1; }
    run mkdir -p "$BIN"
    run install -m 0755 "$src" "$BIN/$bin"
    rm -rf "$tmp"
    ok "$BIN/$bin  ${D}($($BIN/$bin --version 2>/dev/null | head -1))${R}"
  }
  RG_TAG="$(resolve_tag BurntSushi/ripgrep 15.2.0)"; RG_V="${RG_TAG#v}"
  FD_TAG="$(resolve_tag sharkdp/fd v10.5.0)"
  SC_TAG="$(resolve_tag koalaman/shellcheck v0.11.0)"
  install_static ripgrep \
    "https://github.com/BurntSushi/ripgrep/releases/download/${RG_TAG}/ripgrep-${RG_V}-x86_64-unknown-linux-musl.tar.gz" rg rg
  install_static fd \
    "https://github.com/sharkdp/fd/releases/download/${FD_TAG}/fd-${FD_TAG}-x86_64-unknown-linux-musl.tar.gz" fd fd
  install_static shellcheck \
    "https://github.com/koalaman/shellcheck/releases/download/${SC_TAG}/shellcheck-${SC_TAG}.linux.x86_64.tar.gz" shellcheck shellcheck
  echo
  echo "  ${D}$BIN comes before /usr/bin on most setups. If you later install the distro"
  echo "  package, remove the local copy so updates come from the package manager:"
  echo "    rm -f $BIN/rg $BIN/fd $BIN/shellcheck${R}"
fi

# ── verify ────────────────────────────────────────────────────────────────────
step "Result"
# canonical package -> binary that proves the tool actually works
bin_of() {
  case "$1" in
    ripgrep) echo rg ;; fd-find) echo fd ;; nodejs) echo node ;; python3-pip) echo pip3 ;;
    python3-venv) echo "" ;; python3-yaml) echo "" ;; xz-utils) echo xz ;;
    build-essential) echo gcc ;; ca-certificates) echo "" ;; openssh-client) echo ssh ;;
    gnupg) echo gpg ;; libsecret-tools) echo secret-tool ;; dbus-x11) echo dbus-launch ;;
    *) echo "$1" ;;
  esac
}
still=0
for p in "${WANT[@]}"; do
  tp="$(translate "$p" "$FAMILY")"
  bin="$(bin_of "$p")"
  have_bin=0
  [ -n "$bin" ] && command -v "$bin" >/dev/null 2>&1 && have_bin=1
  if pkg_installed "$tp"; then
    printf '  %-20s %s\n' "$p" "installed  ${D}(package)${R}"
  elif [ "$have_bin" = 1 ]; then
    printf '  %-20s %s\n' "$p" "${YE}binary works, package missing${R}  ${D}($(command -v "$bin"))${R}"
    case " ${REQUIRED[*]} " in *" $p "*) warn "$p is provided by a user-space binary — distro package still recommended" ;; esac
  else
    case " ${REQUIRED[*]} " in *" $p "*) printf '  %-20s %s\n' "$p" "${RED}MISSING (required)${R}"; still=1 ;;
      *) printf '  %-20s %s\n' "$p" "${YE}missing (recommended)${R}" ;;
    esac
  fi
done
echo
echo "  rg $(command -v rg >/dev/null && rg --version | head -1 || echo '–') | tmux $(command -v tmux >/dev/null && tmux -V || echo '– (apt only: no static release)')"
echo "  node $(command -v node >/dev/null && node --version || echo '–') | python3 $(command -v python3 >/dev/null && python3 --version || echo '–')"
[ "$still" = 0 ] || { echo; warn "required tools still missing — run the sudo command above, then re-run this script"; exit 1; }
echo
ok "all required OS tools are present and working"
