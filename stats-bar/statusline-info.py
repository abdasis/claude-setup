#!/usr/bin/env python3
"""statusline-info.py — segmen info status bar Claude Code.

Sumber angka:
  - context terpakai: payload JSON Claude Code di stdin (docs statusline):
      context_window.total_input_tokens   (termasuk cache read/write)
      context_window.total_output_tokens
      context_window.context_window_size  (200k default, 1M untuk extended)
      context_window.used_percentage
  - token sesi: dijumlah sendiri dari transcript (`transcript_path`), kumulatif
      input + output + cache read + cache write — sama dengan yang dihitung plugin
      ponytail — dengan cache incremental di <state-dir>/session-tokens.json supaya
      tiap render hanya membaca byte baru, bukan seluruh file.

Keluaran: tiga varian dipisah TAB (full, ringkas, mini). Wrapper memilih yang muat
di lebar status bar; kalau tidak ada yang bisa dihitung, keluaran kosong. Ikon, bukan
teks — lihat IC_* di bawah.

  ◔ 45% 90k/200k   context terpakai (persentase berwarna + token/window)
  Σ 22.5M          token sesi, kumulatif (termasuk cache read/write)
  ↑ 1.8M ↓ 134k    rinciannya: input & output (hanya di varian full)

Dipanggil oleh status-bar/statusbar.sh. Bukan untuk dijalankan manual tanpa alasan.
"""
import json
import os
import sys

DIM = "\033[38;5;245m"
RESET = "\033[0m"
C_OK, C_WARN, C_BAD = "\033[38;5;114m", "\033[38;5;179m", "\033[38;5;203m"
C_VAL = "\033[38;5;252m"
# Ikon, bukan teks: hemat ruang. Semua glyph ini ada di font terminal Dank Mono
# (diperiksa lewat fc-list --charset), jadi tidak jatuh ke font fallback:
#   ◔ context terpakai   Σ token sesi   ↑ input   ↓ output
IC_CTX, IC_TOK, IC_IN, IC_OUT = "◔", "Σ", "↑", "↓"
MAX_READ = 4 * 1024 * 1024  # batas byte per render (transcript besar tidak memblokir bar)


def fmt(n):
    """1200 -> 1.2k, 1200000 -> 1.2M, 999 -> 999."""
    try:
        n = int(n)
    except (TypeError, ValueError):
        return None
    if n < 0:
        return None
    if n >= 999_500:
        return f"{n / 1_000_000:.1f}".rstrip("0").rstrip(".") + "M"
    if n >= 1000:
        return f"{n / 1000:.1f}".rstrip("0").rstrip(".") + "k"
    return str(n)


def load_state(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(path, state):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(state, fh)
        os.replace(tmp, path)
    except Exception:
        pass


def session_tokens(transcript, state_path):
    """Kembalikan dict total kumulatif, atau None kalau tidak bisa dihitung."""
    if not transcript or not os.path.isfile(transcript):
        return None
    state = load_state(state_path)
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return None

    offset = state.get("offset") if state.get("path") == transcript else None
    if not isinstance(offset, int) or offset < 0 or size < offset:
        # transcript baru, diputar ulang, atau dipangkas: hitung dari awal lagi
        state = {"path": transcript, "offset": 0, "input": 0, "output": 0,
                 "cacheRead": 0, "cacheWrite": 0}
        offset = 0

    if size > offset:
        try:
            with open(transcript, "rb") as fh:
                fh.seek(offset)
                chunk = fh.read(min(MAX_READ, size - offset))
        except OSError:
            return None
        # hanya baris lengkap yang dihitung; sisa tanpa newline dibaca render berikutnya
        cut = chunk.rfind(b"\n")
        if cut >= 0:
            body = chunk[: cut + 1]
            state["offset"] = offset + cut + 1
            for raw in body.splitlines():
                raw = raw.strip()
                if not raw.startswith(b"{"):
                    continue
                try:
                    entry = json.loads(raw)
                except Exception:
                    continue
                usage = (entry.get("message") or {}).get("usage")
                if isinstance(usage, dict):
                    for key, field in (("input", "input_tokens"), ("output", "output_tokens"),
                                       ("cacheRead", "cache_read_input_tokens"),
                                       ("cacheWrite", "cache_creation_input_tokens")):
                        value = usage.get(field)
                        if isinstance(value, (int, float)):
                            state[key] = int(state.get(key, 0)) + int(value)
            save_state(state_path, state)

    return {k: int(state.get(k, 0)) for k in ("input", "output", "cacheRead", "cacheWrite")}


def ctx_segment(payload):
    cw = payload.get("context_window")
    if not isinstance(cw, dict):
        return None
    used = cw.get("used_percentage")
    in_tok = cw.get("total_input_tokens")
    out_tok = cw.get("total_output_tokens")
    window = cw.get("context_window_size")

    if used is None and isinstance(in_tok, (int, float)) and isinstance(window, (int, float)) and window:
        used = 100.0 * (in_tok + (out_tok or 0)) / window
    if used is None and not isinstance(in_tok, (int, float)):
        return None
    pct = max(0, min(999, int(round(float(used))))) if isinstance(used, (int, float)) else None

    color = C_OK if (pct is not None and pct <= 50) else C_WARN if (pct is not None and pct <= 80) else C_BAD
    parts = [f"{DIM}{IC_CTX}{RESET}"]
    if pct is not None:
        parts.append(f"{color}{pct}%{RESET}")
    if isinstance(in_tok, (int, float)):
        have = fmt(int(in_tok) + int(out_tok or 0))
        win = fmt(window) if isinstance(window, (int, float)) else None
        parts.append(f"{C_VAL}{have}{RESET}{DIM}/{win or '?'}{RESET}" if have else "")
    seg = " ".join(p for p in parts if p)
    return seg or None


def tok_segment(tokens):
    if not tokens:
        return None
    total = sum(tokens.values())
    if total <= 0:
        return None
    detail = (f"{DIM}{IC_IN}{RESET}{C_VAL}{fmt(tokens['input'])}{RESET} "
              f"{DIM}{IC_OUT}{RESET}{C_VAL}{fmt(tokens['output'])}{RESET}")
    return f"{DIM}{IC_TOK}{RESET} {C_VAL}{fmt(total)}{RESET}", detail


def main():
    state_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    tokens = session_tokens(payload.get("transcript_path"),
                            os.path.join(state_dir, "session-tokens.json"))
    ctx = ctx_segment(payload)
    tok = tok_segment(tokens)

    dot = f"{DIM}·{RESET}"
    variants = []
    if ctx and tok:
        variants.append(f"{ctx} {dot} {tok[0]} {tok[1]}")
        variants.append(f"{ctx} {dot} {tok[0]}")
        variants.append(ctx)
    elif ctx:
        variants.append(ctx)
        variants.append(ctx)
        variants.append(ctx)
    elif tok:
        variants.append(f"{tok[0]} {tok[1]}")
        variants.append(tok[0])
        variants.append(tok[0])
    else:
        variants = ["", "", ""]

    sys.stdout.write("\t".join(variants))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.stdout.write("\t\t")  # status bar tidak boleh pernah gagal
