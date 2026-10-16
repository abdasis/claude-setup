#!/usr/bin/env bash
# Claude Code statusLine command — one bar for every plugin badge.
#
#                                    [PONYTAIL:FULL] [CAVEMAN]     ← rata kanan
#   (kosong)                                                     badges off → baris disembunyikan
#
# Installed by claude-setup. Toggle:  ~/.claude/bin/claude-statsbar on|off|toggle|status
# State:                              <CLAUDE_CONFIG_DIR>/stats-bar/badges  (on|off)
#
# Each badge is rendered by the plugin's own statusline script, so a plugin update
# keeps their look. Scripts are resolved as the newest of:
#   1. the stable copy in the config dir (ponytail refreshes its own every session)
#   2. any copy inside the plugin cache
# A missing script simply renders no badge — never an error.
#
# Orca: its managed ~/.orca/agent-hooks/claude-statusline.sh is no longer the
# statusLine command (this script is), so the payload is forwarded to it — Orca
# keeps reporting Claude usage/quota in its own status bar. Orca classifies a
# non-managed statusLine as "user" and leaves it alone.

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
payload="$(cat)"

# 1. Forward to Orca's hook (background: its curl must never stall the bar).
orca="$HOME/.orca/agent-hooks/claude-statusline.sh"
if [ -x "$orca" ]; then
  printf '%s' "$payload" | "$orca" >/dev/null 2>&1 &
fi

# 2. Badge toggle.
case "$(head -n1 "$CFG/stats-bar/badges" 2>/dev/null | tr -d '[:space:]')" in
  off) exit 0 ;;
esac

# 3. Badges, left to right.
newest() {  # newest <candidate...> -> newest existing file, or empty
  local best="" f
  for f in "$@"; do
    [ -f "$f" ] || continue
    [ -z "$best" ] || [ "$f" -nt "$best" ] && best="$f"
  done
  printf '%s' "$best"
}
badge() {  # badge <script>
  [ -n "$1" ] || return 0
  printf '%s' "$payload" | bash "$1" 2>/dev/null
}

pony="$(newest \
  "$CFG/ponytail-statusline.sh" \
  "$CFG"/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh)"
cave="$(newest \
  "$CFG/hooks/caveman-statusline.sh" \
  "$CFG"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh)"

out="$(badge "$pony")"
c="$(badge "$cave")"
[ -n "$c" ] && out="${out:+$out }$c"
[ -n "$out" ] || exit 0     # tanpa badge: jangan cetak spasi saja (baris kosong)

# Rata kanan. Claude Code MENANGKAP stdout script ini (tidak dihubungkan ke terminal),
# jadi `tput cols`/`stty` tidak bisa membaca lebar terminal; yang tersedia adalah
# COLUMNS/LINES yang Claude Code set ke env script statusLine. Kalau COLUMNS tidak ada
# (host lain) badge tetap tercetak rata kiri.
#   CLAUDE_STATSBAR_ALIGN=left    — matikan rata kanan
#   CLAUDE_STATSBAR_MARGIN=<n>    — sisa kolom di kanan (default 0; pakai 2 kalau membungkus)
if [ "${CLAUDE_STATSBAR_ALIGN:-right}" = right ]; then
  cols="${COLUMNS:-}"
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  margin="${CLAUDE_STATSBAR_MARGIN:-0}"
  case "$margin" in ''|*[!0-9]*) margin=0 ;; esac
  if [ "$cols" -gt 1 ]; then
    visible="$(printf '%s' "$out" | sed $'s/\033\\[[0-9;]*m//g')"
    pad=$(( cols - ${#visible} - margin ))
    if [ "$pad" -gt 0 ]; then
      printf '%*s%s' "$pad" '' "$out"
      exit 0
    fi
  fi
fi
printf '%s' "$out"
