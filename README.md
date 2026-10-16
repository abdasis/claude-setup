# claude-setup

Installer satu perintah untuk menyiapkan Claude Code di perangkat baru — dari nol
sampai semua plugin, hook, dan MCP server aktif, plus verifikasinya.

Dibuat untuk setup pribadi: repo config, model lewat endpoint Anthropic-compatible
(Ollama Cloud), tiga plugin, `rtk`, dan `codegraph`.

```bash
git clone https://github.com/abdasis/claude-setup.git
cd claude-setup
./os-tools.sh                     # langkah 0: alat OS (lihat di bawah)
./install.sh --machine home
```

> Jalankan dari clone (bukan `curl | bash`) supaya kamu bisa baca dulu isinya.
> Kalau tetap mau satu baris:
> `curl -fsSL https://raw.githubusercontent.com/abdasis/claude-setup/main/install.sh | bash -s -- --machine home`

## Langkah 0 — alat OS (`os-tools.sh`)

Claude Code sendiri hanya menyebut satu dependensi OS: **ripgrep** (biasanya
sudah dibundel; kalau search gagal, pakai paket distro). Selebihnya kebutuhan
praktis: `node` untuk hook plugin, `tmux` untuk sesi panjang/interaktif,
`python3`+`pip`+`venv`, dan utilitas yang dipakai agen saat bekerja.

```bash
./os-tools.sh                  # required + recommended
./os-tools.sh --required-only  # hanya yang dipakai Claude Code & plugin-nya
./os-tools.sh --dry-run        # tampilkan yang kurang tanpa memasang
```

| Tier | Isi |
|---|---|
| required | ripgrep, git, curl, nodejs, npm, python3, ca-certificates, openssh-client, unzip, xz-utils, build-essential, tmux |
| recommended | jq, python3-pip, python3-venv, python3-yaml, fd-find, shellcheck, tree, htop, pkg-config, cmake, zip, gnupg, libsecret-tools, dbus-x11 |

Paket distro diutamakan karena dapat update keamanan. Hanya jalur **apt** yang
diuji penulis — mapping `dnf`/`pacman`/`apk` best-effort.

**Hak akses root** — skrip mencoba tiga jalur, dan tidak akan menggantung menunggu
input yang tak bisa dijawab:

1. sudah root → langsung;
2. `sudo` tanpa password → dipakai;
3. `pkexec` (PolicyKit) → **dipakai di sesi desktop**, karena gnome-shell
   menyediakan polkit agent sehingga otorisasi bisa lewat GUI tanpa password
   terminal. Ini jalur yang dipakai di mesin penulis;
4. kalau ketiganya tidak ada → skrip mencetak perintah siap-tempel, dan —
   kecuali `--no-user-fallback` — memasang binary user-space dari rilis resmi
   GitHub ke `~/.local/bin` (ripgrep, fd, shellcheck; `tmux` dan `pip` tidak
   punya rilis statis, jadi wajib lewat paket manager):

```bash
sudo apt-get update
sudo apt-get install -y ripgrep tmux python3-pip python3-venv fd-find shellcheck tree htop pkg-config cmake libsecret-tools dbus-x11
```

Kalau nanti paket distro sudah dipasang, hapus salinan lokalnya supaya update
datang dari package manager: `rm -f ~/.local/bin/rg ~/.local/bin/fd ~/.local/bin/shellcheck`

**Kuirk distro yang ditangani script:** Debian/Ubuntu memasang `fd` sebagai
binary bernama `fdfind` (nama `fd` sudah dipakai paket lain). Pengecekan paket
akan lulus padahal perintah `fd` tidak ada, jadi script membuat symlink
`~/.local/bin/fd -> /usr/bin/fdfind` supaya agen bisa memanggil `fd`.

## Yang dipasang

| Langkah | Hasil |
|---|---|
| 1. Config repo | `~/.claude-config` di-clone, `install.sh <machine>` dijalankan → symlink `CLAUDE.md`, `mcp.json`, `skills/`, `agents/`, `commands/` ke `~/.claude/` |
| 2. Model | provider + model Anthropic-compatible, dipilih dari `ollama`/`deepseek`/`opencode` (+ CLI `claude-model` untuk pindah kapan saja) |
| 3. Plugin | `ponytail@ponytail`, `caveman@caveman`, `superpowers@claude-plugins-official` (+ userConfig caveman) |
| 4. rtk | binary `rtk` + hook `PreToolUse` (`rtk hook claude`) + `RTK.md` di lokasi yang benar-benar di-resolve `@RTK.md` |
| 5. codegraph | binary `codegraph` + MCP server (user scope, `alwaysLoad`) + permission `mcp__codegraph__*` |
| 6. Status bar | satu `statusLine` gabungan (badge `[PONYTAIL]` + `[CAVEMAN]`) + CLI `claude-statsbar` untuk toggle on/off, plus slash command `/statsbar` |

Setelah selesai: `./verify.sh` (atau `./verify.sh --smoke` untuk sekalian tes satu request nyata).

## Memilih provider & model

Step 2 dijalankan dengan `--provider` (atau menu, kalau dijalankan interaktif tanpa flag), lalu
`claude-model` yang menulis blok `env` di `~/.claude/settings.json`.

| Provider | Endpoint (Anthropic-compatible) | Model default | Key |
|---|---|---|---|
| `ollama` | `https://ollama.com` | `deepseek-v4.1-flash` | `OLLAMA_API_KEY` |
| `deepseek` | `https://api.deepseek.com/anthropic` | `deepseek-chat` | `DEEPSEEK_API_KEY` |
| `opencode` | `https://opencode.ai/zen` | `claude-sonnet-4-5` | `OPENCODE_ZEN_API_KEY` |

Pindah provider/model kapan saja, tanpa menjalankan ulang installer:

```bash
claude-model list                    # provider, endpoint, model profil, status key
claude-model use deepseek            # pindah provider (pakai model default profilnya)
claude-model use opencode claude-opus-4-5
claude-model key deepseek            # putar API key (ditanya, input tersembunyi)
claude-model status                  # yang sedang dipakai
```

Key yang dipakai otomatis tersimpan per provider (mode 0600), jadi pindah-pindah provider
tidak perlu input key lagi.

Dari dalam Claude: `/claude-model list`, `/claude-model use ollama`, dan seterusnya.

Catatan yang tidak bisa ditebak dari kodenya:

- **Env baru dipakai di sesi Claude berikutnya** — Claude Code membaca `env` saat start,
  jadi restart dulu sebelum menyimpulkan modelnya belum berganti.
- **Semua alias model diarahkan ke satu model** (`ANTHROPIC_MODEL` plus haiku/sonnet/opus/
  small-fast/subagent), supaya Claude Code tidak pernah meminta model `claude-*` yang tidak
  ada di endpoint non-Anthropic.
- **Base URL tanpa akhiran `/v1`.** Claude Code menambahkan `/v1/messages` sendiri: rute
  Anthropic DeepSeek memang di `/anthropic`, relay Zen melayani Messages di `/zen`.
- **`CLAUDE_CODE_MAX_CONTEXT_TOKENS` ikut profil**: 1.000.000 untuk `deepseek-v4.1-flash` di
  Ollama Cloud, 131.072 untuk DeepSeek langsung, 200.000 untuk model Claude lewat Zen.
- **Relay Zen** hanya berguna untuk model yang dilayani lewat Messages API (`claude-*`,
  `qwen*`). Model `gpt-*`/`grok-*` di sana memakai Responses API dan tidak bisa dipakai
  Claude Code. Header `x-opencode-session` dikirim lewat `ANTHROPIC_CUSTOM_HEADERS`; key itu
  dibuang otomatis ketika pindah ke provider yang tidak memerlukannya.
- **Key diingat per provider.** Key yang dipakai otomatis disimpan mode 0600 di
  `~/.claude/model-keys/<provider>`, jadi setelah sekali pakai, pindah-pindah provider
  tidak pernah ditanya key lagi. Putar key: `claude-model key <provider>`.
  Urutan pencarian: `--key`/`CLAUDE_MODEL_KEY` → file itu → `$<PROVIDER>_API_KEY` →
  `~/.hermes/.env`. Tidak ada key yang masuk repo.
- Setiap perubahan `settings.json` membuat backup di `~/.claude/backups/pre-claude-model-<timestamp>/`.

## Status bar & satu toggle

Claude Code hanya mengizinkan **satu** `statusLine`, sementara ponytail dan caveman
masing-masing punya badge sendiri. Step 6 memasang satu pembungkus
(`~/.claude/stats-bar/statusbar.sh`) yang memanggil badge keduanya dalam satu baris:
`[PONYTAIL:FULL] [CAVEMAN]`.

Badge dirender oleh script milik plugin masing-masing — disalin ke path stabil
(`~/.claude/ponytail-statusline.sh`, `~/.claude/hooks/caveman-statusline.sh`) supaya
tidak putus saat plugin di-update; pembungkus selalu memilih yang terbaru antara
salinan stabil dan isi plugin cache, dan tidak error kalau salah satunya hilang.

Kalau Orca (atau hook statusline lain) sudah memasang `statusLine`-nya sendiri,
perintah lama itu **tetap dijalankan**: pembungkus meneruskan payload-nya, jadi
usage/quota Claude di status bar Orca tidak mati. Perintah `statusLine` sebelumnya
disimpan di `~/.claude/stats-bar/previous-statusline.txt`.

Ponytail dan caveman mengirim modenya sebagai konteks `SessionStart`, jadi teks
ruleset-nya **selalu muncul di transkrip** selama modenya aktif — itu desain
pluginnya, bukan bug yang bisa disembunyikan. Satu-satunya cara membuat workspace
bersih adalah mematikan modenya, dan itu yang dilakukan toggle ini:

```bash
claude-statsbar status        # keadaan sekarang (badge, defaultMode, statusLine)
claude-statsbar off           # badge hilang + ponytail & caveman diam (workspace bersih)
claude-statsbar on            # badge tampil + kedua mode aktif
claude-statsbar toggle        # balik on/off
claude-statsbar badges off    # hanya sembunyikan badge; mode plugin tidak diubah
```

Dari dalam Claude: `/statsbar off`, `/statsbar status`, dan seterusnya. CLI-nya ada
di PATH lewat `~/.local/bin/claude-statsbar`.

`off` menulis `defaultMode: "off"` ke `~/.config/ponytail/config.json` dan
`~/.config/caveman/config.json` — lever resmi yang dibaca kedua hook sebelum
mencetak apa pun. Karena itu efeknya berlaku di **sesi Claude berikutnya**; untuk
sesi yang sedang jalan pakai `/ponytail off` dan `/caveman off`.

## Kebutuhan

- Claude Code sudah terpasang (`claude --version` jalan)
- `git`, `curl`, `python3`, dan `node` (node dibutuhkan hook plugin; tanpa itu hook hanya mencetak error tapi skill tetap jalan)
- API key provider yang dipilih — dari env `OLLAMA_API_KEY` / `DEEPSEEK_API_KEY` /
  `OPENCODE_ZEN_API_KEY`, atau otomatis dibaca dari `~/.hermes/.env`, atau ditanya (input
  tersembunyi). Pindah provider nanti: `claude-model key <provider>`.

## Opsi

```
--machine <home|laptop|kantor>   profil mesin untuk install.sh config repo (default: laptop)
--provider <ollama|deepseek|opencode>  provider model (default: ollama, atau menu interaktif)
--model <id>                     model id untuk provider terpilih (default: model profil provider)
--yes                            tanpa prompt (key harus sudah ada di env)
--dry-run                        cetak perintah tanpa menjalankannya
--no-config / --no-model / --no-plugins / --no-rtk / --no-codegraph / --no-statsbar
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
- **Tidak meng-commit `statusLine` ke repo config.** Step 6 menulisnya di
  `~/.claude/settings.json`; repo config sendiri sudah meng-gitignore file itu.
  Perintah lamanya disimpan di `~/.claude/stats-bar/previous-statusline.txt`.
- **Tidak memilih plugin mana yang tampil di badge.** Sekarang ponytail + caveman;
  menambah plugin lain berarti menambah satu pemanggilan badge di `statusbar.sh`.
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
| Model tidak berubah setelah `claude-model use` | Env dibaca saat Claude Code start — restart sesinya dulu |
| `401` / `Model ... is not supported` di relay Zen | Model harus dari keluarga yang dilayani Messages API (`claude-*`, `qwen*`); lihat `claude-model list` |
| DeepSeek balas 404 | Base URL harus `https://api.deepseek.com/anthropic` (bukan `/v1`), sudah diatur profil `deepseek` |
| Badge ponytail/caveman tidak muncul | `claude-statsbar status` (badge harus `on`), lalu `./verify.sh` bagian "status bar" — salinan script badge & `statusLine` dicek di sana |
| Workspace tetap penuh teks ruleset | Mode sedang aktif; itu memang cara plugin mengirim instruksinya. `claude-statsbar off` (berlaku sesi berikutnya) atau `/ponytail off` + `/caveman off` sekarang |
| `claude mcp list` kosong | Belum ada MCP terdaftar; jalankan langkah 5 atau `claude mcp add-json` manual |
| `os-tools.sh` berhenti di soal `sudo` | Bukan error: jalankan perintah `sudo apt-get install ...` yang dicetaknya di terminalmu, lalu ulangi `./os-tools.sh` |
| `rg`/`fd` jalan tapi versinya beda dari paket distro | Salinan user-space di `~/.local/bin` mendahului `/usr/bin`; hapus kalau mau pakai paket distro |

## Lisensi

MIT — lihat [LICENSE](LICENSE).
