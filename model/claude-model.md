---
description: Pilih provider + model Claude Code (ollama, deepseek, opencode) lewat claude-model.
---

Jalankan script berikut dan tampilkan outputnya apa adanya:

```bash
~/.claude/bin/claude-model $ARGUMENTS
```

Tanpa argumen = `status`. Arti perintah:

- `list` — daftar provider, endpoint, model default, dan status key.
- `use <provider> [model]` — pindah provider/model (menulis blok `env` di `~/.claude/settings.json`, backup otomatis).
- `key <provider> [value]` — simpan/putar API key provider (tanpa value = ditanya, input tersembunyi).
- `status` — provider/model yang sedang dipakai.

Provider: `ollama` (Ollama Cloud), `deepseek` (api.deepseek.com/anthropic), `opencode`
(relay Zen opencode.ai untuk model claude-*/qwen*).

Sesudah `use`, env baru dipakai di **sesi Claude berikutnya** — beri tahu user untuk restart
Claude Code, jangan klaim model sudah berganti di sesi yang sedang jalan.
