#!/usr/bin/env bash
# Claude Code statusLine command — one bar for every plugin badge.
#
#                                    [PONYTAIL:FULL] [CAVEMAN]     ← rata kanan
#   (kosong)                                                     badges off → baris disembunyikan
#
# Installed by claude-setup. Toggle:  ~/.claude/bin/claude-statsbar on|off|toggle|status
# State:                              <CLAUDE_CONFIG_DIR>/stats-bar/badges  (on|off)
#
# Segmen info (ctx terpakai + token sesi) datang dari status-bar/statusline-info.py.
# CLAUDE_STATSBAR_INFO=off menyembunyikannya, CLAUDE_STATSBAR_ALIGN=left mematikan rata kanan.
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

# 3. Segmen info: context terpakai + token sesi (opsional, lihat statusline-info.py).
#    Helper mengembalikan tiga varian (full/ringkas/mini) dipisah TAB; wrapper memilih
#    yang masih muat di lebar baris supaya tidak membungkus ke baris kedua.
info_full=""; info_short=""; info_mini=""
info_py="$CFG/stats-bar/statusline-info.py"
if [ "${CLAUDE_STATSBAR_INFO:-on}" != off ] && [ -f "$info_py" ]; then
  info_raw="$(printf '%s' "$payload" | python3 "$info_py" "$CFG/stats-bar" 2>/dev/null)"
  info_full="${info_raw%%$'\t'*}"
  rest="${info_raw#*$'\t'}"
  info_short="${rest%%$'\t'*}"
  info_mini="${rest#*$'\t'}"
fi

# 4. Badges, left to right.
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

modes="$(badge "$pony")"
c="$(badge "$cave")"

# Badge plugin → ikon, biar hemat ruang. Hanya mode yang umum dipetakan; mode yang
# tidak dikenal dibiarkan apa adanya (mode baru dari plugin tidak pernah hilang).
#   ● ponytail(full)  ●- lite  ●+ ultra  ●* review
#   ▲ caveman         ▲+ ultracave       ▲++ megacave
# CLAUDE_STATSBAR_ICONS=off mematikan penggantian ini (mis. kalau font terminal lain
# tidak punya glyph-nya).
iconify() {
  [ "${CLAUDE_STATSBAR_ICONS:-on}" = off ] && { printf '%s' "$1"; return 0; }
  printf '%s' "$1" | sed \
    -e 's/\[PONYTAIL:LITE\]/●-/g' \
    -e 's/\[PONYTAIL:FULL\]/●/g' \
    -e 's/\[PONYTAIL:ULTRA\]/●+/g' \
    -e 's/\[PONYTAIL:REVIEW\]/●*/g' \
    -e 's/\[PONYTAIL\]/●/g' \
    -e 's/\[ULTRACAVE\]/▲+/g' \
    -e 's/\[MEGACAVE\]/▲++/g' \
    -e 's/\[CAVEMAN\]/▲/g'
}
modes="$(iconify "$modes")"
c="$(iconify "$c")"
[ -n "$c" ] && modes="${modes:+$modes }$c"

# gabungkan mode + info; spasi pemisah hanya kalau keduanya ada
join() { if [ -n "$1" ] && [ -n "$2" ]; then printf '%s  %s' "$1" "$2"; else printf '%s%s' "$1" "$2"; fi; }
out="$(join "$modes" "$info_full")"
[ -n "$out" ] || exit 0     # tanpa badge: jangan cetak spasi saja (baris kosong)

# Rata kanan. Claude Code MENANGKAP stdout script ini (tidak dihubungkan ke terminal),
# jadi `tput cols`/`stty` tidak bisa membaca lebar terminal; yang tersedia adalah
# COLUMNS/LINES yang Claude Code set ke env script statusLine. Kalau COLUMNS tidak ada
# (host lain) badge tetap tercetak rata kiri.
#   CLAUDE_STATSBAR_ALIGN=left    — matikan rata kanan
#   CLAUDE_STATSBAR_MARGIN=<n>    — sisa kolom di kanan (default 0; pakai 2 kalau membungkus)
#   CLAUDE_STATSBAR_INFO=off      — sembunyikan segmen ctx/tok
#   CLAUDE_STATSBAR_ICONS=off     — kembalikan badge plugin jadi teks ([PONYTAIL]/[CAVEMAN])
cols="${COLUMNS:-}"
case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
margin="${CLAUDE_STATSBAR_MARGIN:-0}"
case "$margin" in ''|*[!0-9]*) margin=0 ;; esac

visible_len() { # jumlah KARAKTER (glyph ikon multibyte), bukan byte
  printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C.UTF-8 wc -m | tr -d ' '
}

if [ "$cols" -gt 1 ]; then
  # mengecil bertahap: info penuh -> info ringkas -> ctx saja -> badge saja,
  # supaya baris tidak pernah membungkus ke baris kedua
  for candidate in "$out" "$(join "$modes" "$info_short")" "$(join "$modes" "$info_mini")" "$modes"; do
    [ -n "$candidate" ] || continue
    len="$(visible_len "$candidate")"
    if [ "$(( len + margin ))" -le "$cols" ]; then out="$candidate"; break; fi
  done
fi

if [ "${CLAUDE_STATSBAR_ALIGN:-right}" = right ] && [ "$cols" -gt 1 ]; then
  len="$(visible_len "$out")"
  pad=$(( cols - len - margin ))
  if [ "$pad" -gt 0 ]; then
    printf '%*s%s' "$pad" '' "$out"
    exit 0
  fi
fi
printf '%s' "$out"
