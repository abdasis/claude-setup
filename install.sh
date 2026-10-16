#!/usr/bin/env bash
# claude-setup — reproduces a complete Claude Code setup on a fresh machine.
#
# What it does, in order:
#   1. clone + install the personal config repo (~/.claude-config -> ~/.claude symlinks)
#   2. wire the model: Anthropic-compatible endpoint (Ollama Cloud) + 1M context
#   3. install Claude Code plugins: ponytail, caveman, superpowers
#   4. install rtk and register its PreToolUse rewrite hook (+ RTK.md awareness)
#   5. install codegraph and register its MCP server (+ auto-allow permission)
#   6. wire ONE statusLine that carries the ponytail/caveman badges, plus the
#      claude-statsbar toggle that also silences both plugins' workspace noise
#
# Safe to re-run: every step checks current state first and reports "already".
# Nothing secret is stored in this repo — the API key comes from the environment,
# from ~/.hermes/.env, or from a prompt.
#
# Usage: ./install.sh [--machine home|laptop|kantor] [--yes] [--dry-run] [options]
set -euo pipefail

VERSION="1.2.0"

# ── defaults (override via env) ───────────────────────────────────────────────
CONFIG_REPO="${CONFIG_REPO:-https://github.com/abdasis/claude-config.git}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.claude-config}"
AGENT_DIR="${AGENT_DIR:-$HOME/.claude}"
MODEL="${CLAUDE_MODEL:-deepseek-v4.1-flash}"
ENDPOINT="${CLAUDE_ENDPOINT:-https://ollama.com}"
CONTEXT_TOKENS="${CLAUDE_CONTEXT_TOKENS:-1000000}"
RTK_INSTALL_URL="${RTK_INSTALL_URL:-https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh}"
CODEGRAPH_INSTALL_URL="${CODEGRAPH_INSTALL_URL:-https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh}"
SUPERPOWERS_MARKETPLACE="claude-plugins-official"

MACHINE="laptop"
ASSUME_YES=0
DRY_RUN=0
DO_CONFIG=1
DO_MODEL=1
DO_PLUGINS=1
DO_RTK=1
DO_CODEGRAPH=1
DO_STATSBAR=1
SMOKE=0

# ── output helpers ────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; RED=$'\033[0;31m'
  GR=$'\033[0;32m'; YE=$'\033[0;33m'; BL=$'\033[0;34m'; CY=$'\033[0;36m'
else
  R=; B=; D=; RED=; GR=; YE=; BL=; CY=
fi
ok()   { echo "  ${GR}+${R} $*"; }
skip() { echo "  ${YE}-${R} ${D}$*${R}"; }
warn() { echo "  ${YE}!${R} $*"; }
fail() { echo "  ${RED}x${R} $*" >&2; }
info() { echo "  ${BL}>${R} $*"; }
step() { echo; echo "${B}${CY}$*${R}"; printf '%s\n' "${D}────────────────────────────────────────────────────${R}"; }
run()  { if [ "$DRY_RUN" = 1 ]; then echo "  ${D}[dry-run] $*${R}"; else "$@"; fi; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  cat <<EOF

Options
  --machine <name>   install.sh profile of the config repo: home|laptop|kantor (default: laptop)
  --yes              no prompts (telemetry stays at its default; key must be in env)
  --dry-run          print every mutating command instead of running it
  --no-config        skip step 1 (config repo)
  --no-model         skip step 2 (model/endpoint wiring)
  --no-plugins       skip step 3 (ponytail, caveman, superpowers)
  --no-rtk           skip step 4 (rtk)
  --no-codegraph     skip step 5 (codegraph)
  --no-statsbar      skip step 6 (status bar badges + claude-statsbar toggle)
  --smoke            also run a one-shot \`claude -p\` request at the end (costs tokens)
  -h, --help         this help

Environment
  OLLAMA_API_KEY     required for step 2. Falls back to ~/.hermes/.env, then prompts.
  CLAUDE_MODEL       model id (default: $MODEL)
  CLAUDE_ENDPOINT    Anthropic-compatible base URL (default: $ENDPOINT)
  CLAUDE_CONTEXT_TOKENS  context window to declare (default: $CONTEXT_TOKENS)
  CONFIG_REPO / CONFIG_DIR / AGENT_DIR  override paths and sources

Version $VERSION
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --machine) MACHINE="${2:-}"; shift 2 ;;
    --machine=*) MACHINE="${1#*=}"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-config) DO_CONFIG=0; shift ;;
    --no-model) DO_MODEL=0; shift ;;
    --no-plugins) DO_PLUGINS=0; shift ;;
    --no-rtk) DO_RTK=0; shift ;;
    --no-codegraph) DO_CODEGRAPH=0; shift ;;
    --no-statsbar) DO_STATSBAR=0; shift ;;
    --smoke) SMOKE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1"; echo; usage; exit 2 ;;
  esac
done

case "$MACHINE" in
  home|laptop|kantor) ;;
  *) fail "invalid --machine '$MACHINE' (home|laptop|kantor)"; exit 2 ;;
esac

# ── python helper for JSON merges (no jq dependency) ──────────────────────────
json_set() {  # json_set <file> <python-dict-literal-of-updates> [nested-key]
  local file="$1" updates="$2" nested="${3:-}"
  if [ "$DRY_RUN" = 1 ]; then
    echo "  ${D}[dry-run] would merge into $file${nested:+ -> $nested}:${R} $updates"
    return 0
  fi
  python3 - "$file" "$updates" "$nested" <<'PY'
import json, os, sys, datetime, shutil
path, updates, nested = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
try:
    data = json.load(open(path))
except FileNotFoundError:
    data = {}
target = data
if nested:
    target = data.setdefault(nested, {})
    if not isinstance(target, dict):
        sys.exit(f"refusing to overwrite non-object key '{nested}' in {path}")
changed = {k: v for k, v in updates.items() if target.get(k) != v}
if changed:
    bdir = os.path.join(os.path.dirname(path), "backups",
                        "pre-claude-setup-" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    os.makedirs(bdir, exist_ok=True)
    if os.path.exists(path):
        shutil.copy2(path, os.path.join(bdir, os.path.basename(path)))
    target.update(changed)
    tmp = path + ".tmp"
    json.dump(data, open(tmp, "w"), indent=2)
    os.replace(tmp, path)
    print("  backup: " + bdir)
    print("  updated: " + ", ".join(sorted(changed)))
else:
    print("  no change needed: " + ", ".join(sorted(updates)))
PY
}

json_has_key() {  # json_has_key <file> <dotted.path>
  python3 - "$1" "$2" <<'PY'
import json, sys
path, dotted = sys.argv[1], sys.argv[2]
try:
    cur = json.load(open(path))
except Exception:
    sys.exit(1)
for part in dotted.split("."):
    if not isinstance(cur, dict) or part not in cur:
        sys.exit(1)
    cur = cur[part]
PY
}

# ── preflight ─────────────────────────────────────────────────────────────────
step "Preflight"
missing=0
for bin in claude git curl python3; do
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin ${D}($(command -v "$bin"))${R}"
  else
    fail "$bin not found"; missing=1
  fi
done
if command -v node >/dev/null 2>&1; then ok "node ${D}($(node --version))${R} — needed by plugin hooks"
else warn "node not found — plugin hooks will print 'node: command not found' (skills still work)"; fi
[ "$missing" = 1 ] && {
  fail "install the missing tools first"
  [ -x "$(dirname "$0")/os-tools.sh" ] && info "run ./os-tools.sh — it installs ripgrep/node/python3/tmux + dev utilities for this distro"
  exit 1
}

echo
echo "${B}${CY}  claude-setup${R}  ${D}v$VERSION${R}"
echo "  ${D}machine profile:${R} ${CY}$MACHINE${R}   ${D}agent dir:${R} $AGENT_DIR"
[ "$DRY_RUN" = 1 ] && warn "dry-run: nothing will be written"

# ── 1. config repo ────────────────────────────────────────────────────────────
if [ "$DO_CONFIG" = 1 ]; then
  step "1/6  Config repo ($CONFIG_REPO)"
  if [ -d "$CONFIG_DIR/.git" ]; then
    skip "already cloned at $CONFIG_DIR"
    run git -C "$CONFIG_DIR" pull --ff-only --quiet || warn "could not pull (local changes?)"
  else
    run git clone --depth 1 "$CONFIG_REPO" "$CONFIG_DIR"
  fi
  if [ -x "$CONFIG_DIR/install.sh" ]; then
    info "running the repo installer (machine: $MACHINE)"
    run env PATH="$PATH" bash "$CONFIG_DIR/install.sh" "$MACHINE" || warn "repo installer reported an error"
  else
    warn "$CONFIG_DIR/install.sh not executable — skipping"
  fi
else
  step "1/6  Config repo"; skip "disabled (--no-config)"
fi

# ── 2. model / endpoint ───────────────────────────────────────────────────────
if [ "$DO_MODEL" = 1 ]; then
  step "2/6  Model wiring ($MODEL @ $ENDPOINT)"
  KEY="${OLLAMA_API_KEY:-}"
  if [ -z "$KEY" ] && [ -r "$HOME/.hermes/.env" ]; then
    KEY="$(sed -n 's/^OLLAMA_API_KEY=//p' "$HOME/.hermes/.env" | head -1 | tr -d '"'"'"'')"
    [ -n "$KEY" ] && info "key read from ~/.hermes/.env"
  fi
  if [ -z "$KEY" ]; then
    if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
      fail "OLLAMA_API_KEY is empty — export it, or add it to ~/.hermes/.env, or drop --yes"
      exit 1
    fi
    printf "  Ollama Cloud API key (https://ollama.com/settings) — hidden: "
    read -rs KEY; echo
    [ -z "$KEY" ] && { fail "empty key"; exit 1; }
  fi
  run mkdir -p "$AGENT_DIR"
  if [ ! -f "$AGENT_DIR/settings.json" ]; then run sh -c "echo '{}' > '$AGENT_DIR/settings.json'"; fi
  # endpoint has no /v1 suffix: Claude Code appends /v1/messages itself
  json_set "$AGENT_DIR/settings.json" "$(python3 - "$KEY" "$ENDPOINT" "$MODEL" "$CONTEXT_TOKENS" <<'PY'
import json, sys
key, endpoint, model, ctx = sys.argv[1:5]
print(json.dumps({
    "ANTHROPIC_BASE_URL": endpoint,
    "ANTHROPIC_AUTH_TOKEN": key,
    "ANTHROPIC_MODEL": model,
    "ANTHROPIC_SMALL_FAST_MODEL": model,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
    "CLAUDE_CODE_SUBAGENT_MODEL": model,
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": ctx,
}))
PY
)" env
  info "all model aliases point at $MODEL so Claude Code never asks for a claude-* model"
  info "context declared as $CONTEXT_TOKENS tokens (endpoint must actually serve that much)"
else
  step "2/6  Model wiring"; skip "disabled (--no-model)"
fi

# ── 3. plugins ────────────────────────────────────────────────────────────────
if [ "$DO_PLUGINS" = 1 ]; then
  step "3/6  Plugins"
  installed="$(claude plugin list 2>/dev/null || true)"
  mkts="$(claude plugin marketplace list 2>/dev/null || true)"

  add_marketplace() {  # add_marketplace <name> <source>
    if printf '%s' "$mkts" | grep -q "$1"; then skip "marketplace $1 already added"
    else info "adding marketplace $1"; run claude plugin marketplace add "$2" >/dev/null 2>&1 || warn "marketplace add failed: $1"; fi
  }
  install_plugin() {  # install_plugin <plugin@marketplace>
    if printf '%s' "$installed" | grep -q "^ *❯ *$1\|^ *$1$"; then skip "$1 already installed"
    else info "installing $1"; run claude plugin install "$1" -y --json >/dev/null 2>&1 || warn "install failed: $1"; fi
  }

  add_marketplace ponytail DietrichGebert/ponytail
  install_plugin  ponytail@ponytail
  add_marketplace caveman JuliusBrussee/caveman
  install_plugin  caveman@caveman
  # superpowers ships in Anthropic's built-in directory (pinned commit, no extra marketplace)
  install_plugin  "superpowers@$SUPERPOWERS_MARKETPLACE"

  # caveman userConfig: set explicitly so behaviour is not left to defaults
  if printf '%s' "$installed" | grep -q "caveman@caveman"; then
    printf '%s' '{"ledger":"true","webhookUrl":"","sendNames":"true"}' \
      | run claude plugin configure caveman@caveman --values-stdin >/dev/null 2>&1 \
      && ok "caveman userConfig: ledger=on, webhookUrl=empty (nothing leaves the machine)"
  fi
else
  step "3/6  Plugins"; skip "disabled (--no-plugins)"
fi

# ── 4. rtk ────────────────────────────────────────────────────────────────────
if [ "$DO_RTK" = 1 ]; then
  step "4/6  rtk (command-output token filter + PreToolUse hook)"
  if command -v rtk >/dev/null 2>&1; then
    skip "rtk present: $(rtk --version 2>/dev/null | head -1)"
  else
    tmp="$(mktemp -d)"
    info "downloading installer from $RTK_INSTALL_URL"
    if run curl -fsSL "$RTK_INSTALL_URL" -o "$tmp/rtk-install.sh"; then
      info "sha256: $(sha256sum "$tmp/rtk-install.sh" | cut -d' ' -f1)"
      run bash "$tmp/rtk-install.sh" || warn "rtk installer failed"
    fi
    rm -rf "$tmp"
  fi
  if command -v rtk >/dev/null 2>&1; then
    info "registering the global hook (rtk init -g --auto-patch)"
    run rtk init -g --auto-patch 2>&1 | grep -E 'RTK.md|hook|settings.json' || true

    # @RTK.md is resolved relative to the REAL path of ~/.claude/CLAUDE.md.
    # With the config repo symlinked in, that is <repo>/RTK.md — not ~/.claude/.
    real="$(python3 -c 'import os;print(os.path.realpath(os.path.expanduser("~/.claude/CLAUDE.md")))')"
    if [ "$real" != "$AGENT_DIR/CLAUDE.md" ]; then
      rdir="$(dirname "$real")"
      if [ -f "$AGENT_DIR/RTK.md" ] && [ ! -L "$AGENT_DIR/RTK.md" ] && [ ! -e "$rdir/RTK.md" ]; then
        run mv "$AGENT_DIR/RTK.md" "$rdir/RTK.md"
        run ln -sfn "$rdir/RTK.md" "$AGENT_DIR/RTK.md"
        ok "RTK.md placed at $rdir/RTK.md (where @RTK.md actually resolves) and symlinked back"
      elif [ -e "$rdir/RTK.md" ]; then
        skip "RTK.md already at $rdir/RTK.md"
      fi
    fi
    if [ -f "$real" ] && ! grep -q '@RTK.md' "$real" 2>/dev/null; then
      warn "$real has no '@RTK.md' line — add it so the awareness file is imported"
    fi
  else
    warn "rtk not on PATH after install — open a new shell, then: rtk init -g --auto-patch"
  fi
else
  step "4/6  rtk"; skip "disabled (--no-rtk)"
fi

# ── 5. codegraph ──────────────────────────────────────────────────────────────
if [ "$DO_CODEGRAPH" = 1 ]; then
  step "5/6  codegraph (code index + MCP server)"
  if command -v codegraph >/dev/null 2>&1; then
    skip "codegraph present: v$(codegraph --version 2>/dev/null | head -1)"
  else
    tmp="$(mktemp -d)"
    info "downloading installer from $CODEGRAPH_INSTALL_URL"
    if run curl -fsSL "$CODEGRAPH_INSTALL_URL" -o "$tmp/cg-install.sh"; then
      info "sha256: $(sha256sum "$tmp/cg-install.sh" | cut -d' ' -f1)"
      run bash "$tmp/cg-install.sh" || warn "codegraph installer failed"
    fi
    rm -rf "$tmp"
  fi
  if command -v codegraph >/dev/null 2>&1; then
    # MCP registration (user scope). alwaysLoad matters: without it Claude Code hides
    # MCP tools behind a tool-search step, so a fresh session only sees the name.
    if json_has_key "$HOME/.claude.json" "mcpServers.codegraph" 2>/dev/null; then
      skip "MCP server 'codegraph' already registered"
    else
      run claude mcp add-json codegraph \
        '{"type":"stdio","command":"codegraph","args":["serve","--mcp"],"alwaysLoad":true}' \
        -s user >/dev/null 2>&1 && ok "MCP server registered (user scope, alwaysLoad)"
    fi
    # auto-allow its tools
    tmpjson="$(python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
allow = d.setdefault("permissions", {}).setdefault("allow", [])
print(json.dumps({"allow": sorted(set(allow) | {"mcp__codegraph__*"})}))
PY
)"
    json_set "$AGENT_DIR/settings.json" "$tmpjson" permissions
    info "telemetry is ON by default — 'codegraph telemetry off' or DO_NOT_TRACK=1 to disable"
    info "indexing is per project and deliberate: cd <project> && codegraph init"
  else
    warn "codegraph not on PATH after install — open a new shell and re-run this step"
  fi
else
  step "5/6  codegraph"; skip "disabled (--no-codegraph)"
fi

# ── 6. status bar ──────────────────────────────────────────────────────────────
if [ "$DO_STATSBAR" = 1 ]; then
  step "6/6  Status bar (ponytail + caveman badges, one toggle)"
  SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/stats-bar"
  SETTINGS="$AGENT_DIR/settings.json"
  if [ ! -f "$SRC/statusbar.sh" ]; then
    warn "stats-bar/ not found next to install.sh — skipped (a curl|bash install has no clone)"
  else
    run mkdir -p "$AGENT_DIR/stats-bar" "$AGENT_DIR/hooks" "$AGENT_DIR/bin" "$HOME/.local/bin"
    run install -m 0755 "$SRC/statusbar.sh"    "$AGENT_DIR/stats-bar/statusbar.sh"
    run install -m 0755 "$SRC/claude-statsbar" "$AGENT_DIR/bin/claude-statsbar"
    run ln -sfn "$AGENT_DIR/bin/claude-statsbar" "$HOME/.local/bin/claude-statsbar"
    ok "wrapper + toggle installed ($AGENT_DIR/bin/claude-statsbar, symlinked into ~/.local/bin)"

    # Stable copies of the plugins' OWN badge scripts: the plugin cache is
    # version-pinned (…/caveman/caveman/4.0.1/) and pruned on update. The wrapper
    # always prefers the newest of the stable copy and the cache, so a plugin
    # update still wins; the copy only keeps the badge alive if the plugin goes.
    newest_plugin_script() {  # newest_plugin_script <glob...>
      local best="" f
      for f in "$@"; do
        [ -f "$f" ] || continue
        { [ -z "$best" ] || [ "$f" -nt "$best" ]; } && best="$f"
      done
      printf '%s' "$best"
    }
    pony_src="$(newest_plugin_script "$AGENT_DIR"/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh)"
    cave_src="$(newest_plugin_script "$AGENT_DIR"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh)"
    if [ -n "$pony_src" ]; then
      run install -m 0755 "$pony_src" "$AGENT_DIR/ponytail-statusline.sh"
      ok "ponytail badge script -> $AGENT_DIR/ponytail-statusline.sh (ponytail refreshes it itself)"
    else
      warn "ponytail badge script not in the plugin cache — install the plugin, then re-run"
    fi
    if [ -n "$cave_src" ]; then
      run install -m 0755 "$cave_src" "$AGENT_DIR/hooks/caveman-statusline.sh"
      ok "caveman badge script -> $AGENT_DIR/hooks/caveman-statusline.sh"
    else
      warn "caveman badge script not in the plugin cache — install the plugin, then re-run"
    fi

    # statusLine → the wrapper. The caveman path is passed as an inert extra
    # argument on purpose: caveman only keeps <config-dir>/hooks/caveman-statusline.sh
    # current while the statusLine command still names that script, and that check
    # needs an absolute path (a ~/$HOME form reads as unresolvable and skips the refresh).
    CMD="bash \"$AGENT_DIR/stats-bar/statusbar.sh\" \"$AGENT_DIR/hooks/caveman-statusline.sh\""
    if [ "$DRY_RUN" = 0 ] && [ -f "$SETTINGS" ]; then
      python3 - "$SETTINGS" "$AGENT_DIR/stats-bar/previous-statusline.txt" <<'PY'
import json, os, sys
# Keep the replaced command recoverable: a non-managed statusLine is "user" to
# Orca (it leaves it alone), but a hand-written one would otherwise be lost.
settings, keep = sys.argv[1], sys.argv[2]
try:
    cmd = (json.load(open(settings)).get("statusLine") or {}).get("command") or ""
except Exception:
    cmd = ""
if cmd and "stats-bar/statusbar.sh" not in cmd and not os.path.exists(keep):
    os.makedirs(os.path.dirname(keep), exist_ok=True)
    open(keep, "w").write(cmd + "\n")
    print("  saved the previous statusLine command to " + keep)
PY
    fi
    json_set "$SETTINGS" "{\"type\": \"command\", \"command\": $(
      python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$CMD"
    )}" statusLine

    # Badge state: defaults to on, never overwritten once the user chose.
    if [ -f "$AGENT_DIR/stats-bar/badges" ]; then
      skip "badge toggle already set: $(head -n1 "$AGENT_DIR/stats-bar/badges" 2>/dev/null) ($AGENT_DIR/stats-bar/badges)"
    else
      run sh -c "printf 'on\n' > '$AGENT_DIR/stats-bar/badges'"
      ok "badge toggle created (on) — 'claude-statsbar off' hides the badges AND silences both plugins"
    fi

    # Slash command inside Claude (/statsbar). $AGENT_DIR/commands is a symlink into
    # the config repo once step 1 ran, so this lands in the repo too.
    if [ -f "$SRC/statsbar.md" ] && ! cmp -s "$SRC/statsbar.md" "$AGENT_DIR/commands/statsbar.md" 2>/dev/null; then
      run mkdir -p "$AGENT_DIR/commands"
      run install -m 0644 "$SRC/statsbar.md" "$AGENT_DIR/commands/statsbar.md"
      ok "slash command installed: /statsbar"
    else
      skip "slash command /statsbar already current"
    fi
  fi
else
  step "6/6  Status bar"; skip "disabled (--no-statsbar)"
fi

# ── summary ───────────────────────────────────────────────────────────────────
step "Summary"
printf '  %-22s %s\n' "config repo"  "$([ -d "$CONFIG_DIR/.git" ] && echo "✓ $CONFIG_DIR" || echo "–")"
printf '  %-22s %s\n' "model"        "$(python3 -c 'import json,os;p=os.path.expanduser("~/.claude/settings.json");print(json.load(open(p)).get("env",{}).get("ANTHROPIC_MODEL","–"))' 2>/dev/null)"
printf '  %-22s %s\n' "context tokens" "$(python3 -c 'import json,os;p=os.path.expanduser("~/.claude/settings.json");print(json.load(open(p)).get("env",{}).get("CLAUDE_CODE_MAX_CONTEXT_TOKENS","–"))' 2>/dev/null)"
printf '  %-22s %s\n' "plugins"      "$(claude plugin list 2>/dev/null | grep -c '❯') installed"
printf '  %-22s %s\n' "rtk"          "$(command -v rtk >/dev/null && rtk --version 2>/dev/null | head -1 || echo '–')"
printf '  %-22s %s\n' "codegraph"    "$(command -v codegraph >/dev/null && echo "v$(codegraph --version 2>/dev/null | head -1)" || echo '–')"
printf '  %-22s %s\n' "MCP servers"  "$(claude mcp list 2>/dev/null | grep -c '✔ Connected') connected"
printf '  %-22s %s\n' "stats bar"    "$([ -f "$AGENT_DIR/stats-bar/badges" ] && { printf 'badges %s' "$(head -n1 "$AGENT_DIR/stats-bar/badges" 2>/dev/null)"; python3 -c 'import json,os;p=os.path.expanduser("~/.claude/settings.json");print(" · statusLine " + ("stats-bar" if "stats-bar/statusbar.sh" in json.load(open(p)).get("statusLine",{}).get("command","") else "NOT wired"))' 2>/dev/null; } || echo '–')"

cat <<EOF

  ${B}Next${R}
    1. Restart Claude Code — plugins, hooks and the MCP server load on a new session.
    2. Optional: commit the generated RTK.md in your config repo so every machine
       gets the @RTK.md import that CLAUDE.md already references.
    3. Index a project before expecting CodeGraph answers: cd <project> && codegraph init
    4. Run ./verify.sh to check the whole setup, or ./verify.sh --smoke for a live request.

  ${D}Notes worth knowing${R}
    - caveman stays OFF in headless \`claude -p\` runs by design (entrypoint sdk-*);
      set CAVEMAN_DEFAULT_MODE=caveman if you want it there too.
    - The status bar is ONE command now (step 6) carrying both plugins' badges.
      \`claude-statsbar off\` also silences ponytail + caveman in the workspace; \`on\`
      brings both back. /statsbar does the same from inside Claude, and
      \`claude-statsbar status\` shows what is on.
    - A mode is delivered as SessionStart context, so its ruleset text appears in the
      transcript whenever it is on. That is the plugin's design — only \`off\` removes it.
    - Don't accept a statusline-setup offer from caveman or ponytail afterwards: it
      would replace the merged bar with a single-plugin one. Both stay quiet while a
      statusLine exists (and step 6 passes the caveman script path so caveman keeps
      its badge copy current).
    - rtk's own \`rtk init -g\` writes ~/.claude/RTK.md, which is inert when CLAUDE.md is
      a symlink; this script also places it at the realpath (see step 4).
EOF

if [ "$SMOKE" = 1 ]; then
  step "Smoke test"
  run claude -p 'Reply with exactly: ok' --max-turns 1 2>&1 | tail -2
fi

exit 0
