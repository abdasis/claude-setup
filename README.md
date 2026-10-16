# claude-setup

Installer satu perintah untuk menyiapkan Claude Code di perangkat baru — dari nol
sampai semua plugin, hook, dan MCP server aktif, plus verifikasinya.

Dibuat untuk setup pribadi: repo config, model lewat endpoint Anthropic-compatible
(Ollama Cloud), tiga plugin, `rtk`, dan `codegraph`.

```bash
git clone https://github.com/abdasis/claude-setup.git
cd claude-setup
./install.sh --machine home
```

> Jalankan dari clone (bukan `curl | bash`) supaya kamu bisa baca dulu isinya.
> Kalau tetap mau satu baris:
> `curl -fsSL https://raw.githubusercontent.com/abdasis/claude-setup/main/install.sh | bash -s -- --machine home`

## Yang dipasang

| Langkah | Hasil |
|---|---|
| 1. Config repo | `~/.claude-config` di-clone, `install.sh <machine>` dijalankan → symlink `CLAUDE.md`, `mcp.json`, `skills/`, `agents/`, `commands/` ke `~/.claude/` |
| 2. Model | `~/.claude/settings.json` → blok `env`: base URL, auth token, model, semua alias model, dan `CLAUDE_CODE_MAX_CONTEXT_TOKENS` |
| 3. Plugin | `ponytail@ponytail`, `caveman@caveman`, `superpowers@claude-plugins-official` (+ userConfig caveman) |
| 4. rtk | binary `rtk` + hook `PreToolUse` (`rtk hook claude`) + `RTK.md` di lokasi yang benar-benar di-resolve `@RTK.md` |
| 5. codegraph | binary `codegraph` + MCP server (user scope, `alwaysLoad`) + permission `mcp__codegraph__*` |

Setelah selesai: `./verify.sh` (atau `./verify.sh --smoke` untuk sekalian tes satu request nyata).

## Kebutuhan

- Claude Code sudah terpasang (`claude --version` jalan)
- `git`, `curl`, `python3`, dan `node` (node dibutuhkan hook plugin; tanpa itu hook hanya mencetak error tapi skill tetap jalan)
- API key Ollama Cloud — dari env `OLLAMA_API_KEY`, atau otomatis dibaca dari `~/.hermes/.env`, atau ditanya (input tersembunyi)

## Opsi

```
--machine <home|laptop|kantor>   profil mesin untuk install.sh config repo (default: laptop)
--yes                            tanpa prompt (key harus sudah ada di env)
--dry-run                        cetak perintah tanpa menjalankannya
--no-config / --no-model / --no-plugins / --no-rtk / --no-codegraph
--smoke                          tes satu request live di akhir
```

Variabel env: `OLLAMA_API_KEY`, `CLAUDE_MODEL`, `CLAUDE_ENDPOINT`,
`CLAUDE_CONTEXT_TOKENS`, `CONFIG_REPO`, `CONFIG_DIR`, `AGENT_DIR`.

## Aman diulang

Semua langkah cek dulu keadaannya, jadi menjalankan ulang akan melaporkan
`already` dan tidak menimpa apa pun. Setiap perubahan `settings.json`
membuat backup di `~/.claude/backups/pre-claude-setup-<timestamp>/`.

Tidak ada rahasia di repo ini: token hanya masuk ke `~/.claude/settings.json`
(file yang sudah di-gitignore oleh repo config).

## Keputusan yang tidak jelas kalau tidak dijelaskan

- **Base URL tanpa akhiran `/v1`.** Claude Code menambahkan `/v1/messages`
  sendiri; `https://ollama.com/v1` → request ke `/v1/v1/messages` → 404.
- **Semua alias model diarahkan ke satu model** (`ANTHROPIC_MODEL` plus
  haiku/sonnet/opus/small-fast/subagent). Kalau tidak, Claude Code akan meminta
  model `claude-*` yang tidak ada di endpoint ini.
- **`CLAUDE_CODE_MAX_CONTEXT_TOKENS`** perlu diisi manual: Claude Code
  menganggap model tak dikenal hanya punya 200.000 token.
- **`alwaysLoad: true`** pada MCP codegraph — tanpa itu Claude Code menyembunyikan
  tool MCP di balik langkah tool-search, sesi baru hanya tahu namanya.
- **`rtk init -g` saja tidak cukup** kalau `~/.claude/CLAUDE.md` adalah symlink:
  `@RTK.md` di-resolve relatif ke realpath symlink itu, jadi `RTK.md` ditulis di
  direktori tujuan symlink lalu di-symlink balik. Script ini yang melakukannya.
- **codegraph dipasang dari bundle resmi** (`~/.codegraph` + `~/.local/bin`),
  bukan `npm i -g`, supaya paket tidak masuk ke dalam instalasi toolchain lain.

## Yang TIDAK dilakukan script ini

- **Tidak mengindeks kode.** Indexing itu keputusan per proyek:
  `cd <proyek> && codegraph init`. Tanpa `.codegraph/`, CodeGraph tidak dipakai.
- **Tidak meng-commit `RTK.md`.** File itu muncul di repo config-mu setelah
  langkah 4; commit sendiri supaya mesin lain dapat import `@RTK.md`.
- **Tidak mengubah statusLine.** Plugin caveman menawarkan badge statusline;
  kalau kamu sudah punya `statusLine` di `settings.json`, menerimanya akan
  menimpanya. Script ini tidak menyentuhnya.
- **Tidak mematikan telemetry.** codegraph default-nya mengirim statistik
  anonim; matikan dengan `codegraph telemetry off` atau `DO_NOT_TRACK=1`.

## Yang perlu diketahui setelah install

- **Restart Claude Code** — plugin, hook, dan MCP baru aktif di sesi baru.
- **caveman sengaja OFF di `claude -p`** (entrypoint `sdk-*`, dianggap tool
  probe yang mem-parsing balasan). Untuk menyalakannya di sana:
  `CAVEMAN_DEFAULT_MODE=caveman`. Di sesi interaktif dia aktif sendiri.
- **Biaya token selalu-on** kira-kira: ponytail ~0,4k + caveman ~1,4k +
  superpowers ~0,7k (metadata skill), plus injeksi hook per sesi
  (caveman ~1,1k, ponytail ~1,2k, superpowers ~0,8k).
  Matikan yang tidak dipakai: `claude plugin disable <nama>@<marketplace>`.

## Troubleshooting

| Gejala | Sebab / solusi |
|---|---|
| `[claude-code:unrecognized_model]` | Normal untuk model non-Anthropic; tidak mengganggu |
| Error `node: command not found` di hook | node tidak ada di PATH non-interaktif |
| `codegraph` tidak ketemu padahal baru dipasang | Buka shell baru (PATH belum di-refresh) |
| `@RTK.md` tidak ter-import | Cek `./verify.sh` — file harus ada di realpath `CLAUDE.md` |
| `claude mcp list` kosong | Belum ada MCP terdaftar; jalankan langkah 5 atau `claude mcp add-json` manual |

## Lisensi

MIT — lihat [LICENSE](LICENSE).
