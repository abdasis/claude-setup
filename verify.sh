#!/usr/bin/env bash
# verify.sh — check that claude-setup actually landed. Read-only; changes nothing.
# Usage: ./verify.sh [--smoke]
#   --smoke  also send one live `claude -p` request (costs tokens on your endpoint)
set -uo pipefail

SMOKE=0
[ "${1:-}" = "--smoke" ] && SMOKE=1

if [ -t 1 ]; then R=$'\033[0m'; GR=$'\033[0;32m'; RED=$'\033[0;31m'; YE=$'\033[0;33m'; B=$'\033[1m'
else R=; GR=; RED=; YE=; B=; fi

PASS=0; FAIL=0; WARN=0
pass() { echo "  ${GR}PASS${R}  $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ${RED}FAIL${R}  $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  ${YE}WARN${R}  $*"; WARN=$((WARN + 1)); }
head_() { echo; echo "${B}$*${R}"; }

AGENT_DIR="${AGENT_DIR:-$HOME/.claude}"
SETTINGS="$AGENT_DIR/settings.json"

head_ "binaries"
for bin in claude rtk codegraph node; do
  if command -v "$bin" >/dev/null 2>&1; then pass "$bin present"; else
    if [ "$bin" = rtk ] || [ "$bin" = codegraph ]; then bad "$bin missing"; else warn "$bin missing"; fi
  fi
done

head_ "settings.json ($SETTINGS)"
if [ -f "$SETTINGS" ]; then
  pass "file exists"
  py_out="$(python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
env = d.get("env", {})
for k in ("ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL", "CLAUDE_CODE_MAX_CONTEXT_TOKENS"):
    if env.get(k):
        print(f"  \033[0;32mPASS\033[0m  env.{k} = {env[k]}")
    else:
        print(f"  \033[0;31mFAIL\033[0m  env.{k} missing")
# Token bisa di salah satu dari dua header: ollama/deepseek pakai Bearer
# (ANTHROPIC_AUTH_TOKEN), relay Zen opencode membaca x-api-key (ANTHROPIC_API_KEY).
token_key = "ANTHROPIC_AUTH_TOKEN" if env.get("ANTHROPIC_AUTH_TOKEN") else (
    "ANTHROPIC_API_KEY" if env.get("ANTHROPIC_API_KEY") else None)
if token_key:
    print(f"  \033[0;32mPASS\033[0m  env.{token_key} (value hidden)")
else:
    print("  \033[0;31mFAIL\033[0m  no API token in env (ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY)")
base = env.get("ANTHROPIC_BASE_URL", "")
if base.rstrip("/").endswith("/v1"):
    print("  \033[0;33mWARN\033[0m  base URL ends with /v1 — Claude Code appends /v1/messages itself (expect 404)")
hooks = d.get("hooks", {})
if hooks:
    print(f"  \033[0;32mPASS\033[0m  {len(hooks)} hook events registered")
else:
    print("  \033[0;31mFAIL\033[0m  no hook events registered")
if "rtk hook claude" in json.dumps(hooks):
    print("  \033[0;32mPASS\033[0m  rtk PreToolUse hook present")
else:
    print("  \033[0;33mWARN\033[0m  rtk hook not found in settings.json hooks")
if "mcp__codegraph__*" in json.dumps(d.get("permissions", {})):
    print("  \033[0;32mPASS\033[0m  permission mcp__codegraph__* granted")
else:
    print("  \033[0;33mWARN\033[0m  permission mcp__codegraph__* not granted")
PY
)"
  printf '%s\n' "$py_out"
  PASS=$((PASS + $(printf '%s' "$py_out" | grep -c 'PASS')))
  FAIL=$((FAIL + $(printf '%s' "$py_out" | grep -c 'FAIL')))
  WARN=$((WARN + $(printf '%s' "$py_out" | grep -c 'WARN')))
else
  bad "settings.json missing — run install.sh"
fi

head_ "plugins"
plist="$(claude plugin list 2>/dev/null || true)"
for p in "ponytail@ponytail" "caveman@caveman" "superpowers@claude-plugins-official"; do
  if printf '%s' "$plist" | grep -q "$p"; then pass "$p installed"; else bad "$p not installed"; fi
done

head_ "rtk hook + awareness"
if command -v rtk >/dev/null 2>&1; then
  rtk_show="$(rtk init --show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
  if printf '%s' "$rtk_show" | grep -q '\[ok\] Hook'; then pass "hook registered (rtk init --show)"; else bad "hook not registered"; fi
  # @RTK.md resolves next to the REAL path of CLAUDE.md, not the symlink
  if [ -e "$AGENT_DIR/CLAUDE.md" ]; then
    real="$(python3 -c 'import os;print(os.path.realpath(os.path.expanduser("~/.claude/CLAUDE.md")))')"
    rdir="$(dirname "$real")"
    if grep -q '@RTK.md' "$real" 2>/dev/null; then
      if [ -r "$rdir/RTK.md" ]; then pass "RTK.md present where @RTK.md resolves ($rdir/RTK.md)"
      else bad "@RTK.md is referenced but $rdir/RTK.md is missing (dangling import)"; fi
    else
      warn "no '@RTK.md' line in $real — awareness file is not imported"
    fi
  fi
fi

head_ "codegraph MCP"
if python3 -c 'import json,os,sys;d=json.load(open(os.path.expanduser("~/.claude.json")));sys.exit(0 if "codegraph" in d.get("mcpServers",{}) else 1)' 2>/dev/null; then
  pass "registered in ~/.claude.json (user scope)"
  if claude mcp list 2>/dev/null | grep -q 'codegraph.*Connected'; then pass "server connects"
  else warn "server did not report Connected (may need a new shell for PATH)"; fi
else
  bad "codegraph MCP server not registered"
fi

head_ "model & provider (claude-model)"
CM="$AGENT_DIR/bin/claude-model"
if [ -x "$CM" ]; then pass "claude-model present"; else bad "$CM missing — run install.sh (step 2)"; fi
if command -v claude-model >/dev/null 2>&1; then pass "claude-model on PATH"
else warn "claude-model not on PATH (new shell, or call $CM directly)"; fi
if [ -x "$CM" ]; then
  mlist="$(CLAUDE_CONFIG_DIR="$AGENT_DIR" "$CM" list 2>/dev/null)"
  for p in ollama deepseek opencode; do
    if printf '%s' "$mlist" | grep -q " $p "; then pass "provider profil tersedia: $p"; else bad "provider $p tidak ada di profil claude-model"; fi
  done
  mstat="$(CLAUDE_CONFIG_DIR="$AGENT_DIR" "$CM" status 2>/dev/null)"
  prov="$(printf '%s' "$mstat" | sed -n 's/.*provider  *: *//p' | cut -d' ' -f1)"
  if [ -n "$prov" ] && [ "$prov" != "tidak" ]; then pass "provider aktif dikenali: $prov"
  else bad "ANTHROPIC_BASE_URL tidak cocok dengan profil mana pun ($prov)"; fi
  if printf '%s' "$mstat" | grep -q 'key *: *(kosong)'; then
    bad "ANTHROPIC_AUTH_TOKEN kosong di settings.json"
  elif printf '%s' "$mstat" | grep -q 'hanya di settings.json'; then
    warn "key hanya ada di settings.json — menyimpan ulang dengan: claude-model key $prov"
  else
    pass "key provider bisa di-resolve ulang ($(printf '%s' "$mstat" | sed -n 's/.*key *: *//p' | cut -c1-60))"
  fi
fi

head_ "status bar (ponytail + caveman badges)"
SB="$AGENT_DIR/stats-bar/statusbar.sh"
TOGGLE="$AGENT_DIR/bin/claude-statsbar"
if [ -x "$SB" ]; then pass "wrapper present ($SB)"; else bad "$SB missing — run install.sh (step 6)"; fi
if [ -x "$TOGGLE" ]; then pass "claude-statsbar present"; else warn "claude-statsbar missing or not executable"; fi
if command -v claude-statsbar >/dev/null 2>&1; then pass "claude-statsbar on PATH"
else warn "claude-statsbar not on PATH (new shell, or call $TOGGLE directly)"; fi
for s in "$AGENT_DIR/ponytail-statusline.sh" "$AGENT_DIR/hooks/caveman-statusline.sh"; do
  if [ -f "$s" ]; then pass "badge script $(basename "$s")"; else warn "badge script missing: $s"; fi
done
if python3 -c 'import json,os,sys;d=json.load(open(os.path.expanduser("~/.claude/settings.json")));sys.exit(0 if "stats-bar/statusbar.sh" in (d.get("statusLine") or {}).get("command","") else 1)' 2>/dev/null; then
  pass "settings.json statusLine points at the stats bar"
else
  bad "settings.json statusLine is not the stats bar — badges will not render"
fi
if [ -x "$SB" ]; then
  # CLAUDE_CONFIG_DIR is scoped to these two calls on purpose: the wrapper resolves
  # its badge scripts and toggle state from it, and exporting it for the whole script
  # would change how `claude mcp list` looks up servers.
  payload='{"session_id":"verify","cwd":"'"$PWD"'","rate_limits":{"five_hour":{"used_percentage":1}}}'
  out="$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$AGENT_DIR" "$SB" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" = 0 ]; then
    clean="$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')"
    pass "renders without error: ${clean:-<empty>} $([ -n "$clean" ] || echo '(badges off, or both plugins off)')"
  else
    bad "statusline wrapper exited $rc"
  fi
  # toggle check, restoring whatever was there before (verify.sh stays a no-op)
  BADGESTATE="$AGENT_DIR/stats-bar/badges"
  had=0; [ -f "$BADGESTATE" ] && had=1
  prev="$(head -n1 "$BADGESTATE" 2>/dev/null | tr -d '[:space:]')"
  printf 'off\n' >"$BADGESTATE" 2>/dev/null
  blank="$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$AGENT_DIR" "$SB" 2>/dev/null)"
  if [ "$had" = 1 ]; then printf '%s\n' "$prev" >"$BADGESTATE"; else rm -f "$BADGESTATE"; fi
  if [ -z "$blank" ]; then pass "badges off renders nothing (state restored: ${prev:-unset})"
  else bad "badges off still rendered output"; fi
fi

if [ "$SMOKE" = 1 ]; then
  head_ "live request"
  out="$(claude -p 'Reply with exactly: ok' --output-format json --max-turns 1 2>/dev/null | tail -1)"
  if printf '%s' "$out" | grep -q '"result":"ok"'; then
    pass "model answered: $(printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(list(d.get("modelUsage",{})), "ctx", [v.get("contextWindow") for v in d.get("modelUsage",{}).values()][:1])' 2>/dev/null)"
  else
    bad "no usable answer from the endpoint"
  fi
fi

echo
echo "${B}────────────────────────────────────────${R}"
echo "  ${GR}$PASS passed${R}   ${RED}$FAIL failed${R}   ${YE}$WARN warnings${R}"
[ "$FAIL" -eq 0 ] || exit 1
