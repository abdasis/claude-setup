---
description: Toggle indikator ponytail & caveman di status bar Claude (on/off/toggle/badges/status).
---

Jalankan script berikut dan tampilkan outputnya apa adanya:

```bash
~/.claude/bin/claude-statsbar $ARGUMENTS
```

Tanpa argumen = `status`. Arti perintah:

- `on` — ponytail + caveman aktif, badge muncul di status bar.
- `off` — keduanya diam (tidak ada ruleset yang masuk ke workspace) dan status bar kosong.
- `toggle` — balik on/off.
- `badges on|off` — hanya tampilan status bar, mode plugin tidak diubah.
- `status` — lihat keadaan sekarang.

Perubahan mode baru berlaku di sesi Claude berikutnya; kalau mau langsung berlaku di sesi yang sedang jalan, pakai `/ponytail off` dan `/caveman off`.
