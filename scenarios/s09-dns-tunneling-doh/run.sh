#!/usr/bin/env bash
# S09 — DNS tunneling (iodine). Kategori: Backdoor/Worms (covert channel).
# CATATAN: DoH DIKELUARKAN dari scope (terenkripsi -> dns.log kosong, bukan bagian
# UNSW-NB15, butuh PKI). S09 = iodine saja.
#
# PREREQUISITE (WAJIB dijalankan DULU di host IODINE_SERVER=$IODINE_SERVER, sebagai root):
#     sudo iodined -f -c -P "$IODINE_PASS" 172.16.254.1 "$IODINE_DOMAIN"
#   iodined belum terpasang/terkonfigurasi di lab -> pasang di server saat ada
#   window instalasi, atau jalankan manual di console server. Kalau koneksi gagal,
#   skrip BERHENTI dan lapor — JANGAN improvisasi.
SCN=S09; ATTACK_CAT=Backdoor; PHASE=linux
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool iodine
banner
ensure_up "$IODINE_SERVER"

DURATION="${1:-60}"   # detik tunnel aktif
mark_start "$IODINE_SERVER"
echo "== buka tunnel iodine (direct mode ke server IP) selama ${DURATION}s =="
# -r = paksa raw/direct ke server (tanpa resolver rekursif), -f = foreground
sudo timeout "$DURATION" iodine -f -r -P "$IODINE_PASS" "$IODINE_SERVER" "$IODINE_DOMAIN" \
  & IOD=$!
sleep 10
if ! ip addr show dns0 >/dev/null 2>&1; then
  kill "$IOD" 2>/dev/null || true
  die "Tunnel iodine tidak terbentuk (interface dns0 tak ada). Pastikan iodined jalan di $IODINE_SERVER (lihat PREREQUISITE). STOP."
fi
echo "   tunnel up (dns0). Membangkitkan trafik lewat tunnel..."
TUN_SRV=172.16.254.1
ping -c 20 -i 0.5 "$TUN_SRV" >/dev/null 2>&1 || true   # payload melalui DNS tunnel
wait "$IOD" 2>/dev/null || true
mark_end "$IODINE_SERVER"
echo "Selesai. (Trafik query DNS bervolume tinggi ke domain $IODINE_DOMAIN = sampel S09.)"
