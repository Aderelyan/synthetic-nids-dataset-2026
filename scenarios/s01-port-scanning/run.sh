#!/usr/bin/env bash
# S01 — Port scanning / Reconnaissance (nmap). Kategori: Reconnaissance.
# Dijalankan DARI attacker (10.10.30.10). Fase: mana saja (target always-on).
SCN=S01; ATTACK_CAT=Reconnaissance; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool nmap
banner

# target yang selalu nyala (server). Client/win ditambah kalau fase-nya aktif.
TARGETS="$SRV_WEB $SRV_FILE"
ping -c1 -W2 "$CLIENT1" >/dev/null 2>&1 && TARGETS="$TARGETS $CLIENT1 $CLIENT2"
ping -c1 -W2 "$WIN"     >/dev/null 2>&1 && TARGETS="$TARGETS $WIN"
for t in $TARGETS; do require_lab_target "$t"; done
echo "Target discovery: $TARGETS"

mark_start "$TARGETS"
# 1) TCP SYN scan + service/version + OS (khas pola recon flow)
sudo nmap -sS -sV -O --top-ports 1000 -T4 -oN "$HERE/s01-tcp.nmap" $TARGETS
settle 5
# 2) UDP scan ringan (top 50) — pola berbeda, tetap recon
sudo nmap -sU --top-ports 50 -T4 -oN "$HERE/s01-udp.nmap" $TARGETS
mark_end "$TARGETS"
echo "Output: s01-tcp.nmap, s01-udp.nmap"
