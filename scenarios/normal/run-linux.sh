#!/usr/bin/env bash
# N01 — generator trafik NORMAL/benign (VERSI PARALEL). Dijalankan DI client-1 / client-2
# (BUKAN attacker). UNSW-NB15 asli membangkitkan normal secara eksplisit (IXIA PerfectStorm).
# Ini padanannya: beberapa WORKER paralel (bukan 1 thread) yang membangkitkan sesi benign acak
# (HTTP page-view, DNS, FTP, SSH, ICMP, unduhan kecil) ke srv-web/srv-file dengan think-time
# singkat (0.5–3 dtk). Tak melibatkan IP attacker -> otomatis label=0 (Normal) di build_dataset.py.
#
# Perubahan vs versi lama:
#   - PARALEL: `--workers N` worker berjalan bersamaan (default 4), bukan 1 loop tunggal.
#   - Think-time 0.5–3 dtk (dulu 1–8 dtk) -> rate normal lebih padat tapi tetap manusiawi.
#   - Aksi "web" = PAGE-VIEW (2–3 request cepat: HTML + aset), meniru perilaku browser.
#   - Tambah aksi unduhan HTTP kecil (variasi byte + keragaman).
#   - Kontrak marker TIDAK berubah: tetap 1 baris N01 di akhir + header bila file belum ada.
#
# Usage: run-linux.sh [--duration SEC] [--workers N] [--web IP] [--file IP] [--user U] [--pass P]
#   default: 1800s, 4 worker, web=10.10.10.10, file=10.10.10.11, labadmin/labadmin
set -uo pipefail
DURATION=1800; WORKERS=4; WEB=10.10.10.10; FILE=10.10.10.11; LUSER=labadmin; LPASS=labadmin
while [ $# -gt 0 ]; do case "$1" in
  --duration) DURATION="$2"; shift 2;;
  --workers)  WORKERS="$2"; shift 2;;
  --web) WEB="$2"; shift 2;;
  --file) FILE="$2"; shift 2;;
  --user) LUSER="$2"; shift 2;;
  --pass) LPASS="$2"; shift 2;;
  *) echo "arg tak dikenal: $1"; exit 2;;
esac; done

now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
MARK="$HOME/normal-markers.csv"
[ -f "$MARK" ] || echo "scenario,attack_cat,phase,target,start_utc,end_utc" > "$MARK"
START="$(now)"
echo "[N01] normal-traffic mulai $START, durasi ${DURATION}s, workers=${WORKERS}, dari $(hostname)"

WEB_PATHS=( / /login.php /index.php /about /vulnerabilities/ /dvwa/ /favicon.ico /robots.txt /instructions.php /security.php )
DNS_NAMES=( srv-web.lab.local srv-file.lab.local opnsense.lab.local client-1.lab.local client-2.lab.local )
rnd(){ echo $(( RANDOM % $1 )); }
# think-time 0.5–3.0 dtk (persepuluh detik) — lebih padat dari 1–8 dtk tapi tetap "manusia".
think(){ local t=$(( RANDOM % 26 + 5 )); sleep "$(( t / 10 )).$(( t % 10 ))"; }

END_EPOCH=$(( $(date +%s) + DURATION ))
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
head -c 131072 /dev/urandom > "$TMP/upload.bin"   # 128 KiB, upload kecil tapi sedikit berisi

# SATU worker: loop aksi sampai END_EPOCH. Nama file upload pakai $BASHPID supaya tiap
# worker punya nama unik (mencegah tabrakan di srv-file saat paralel).
worker(){
  while [ "$(date +%s)" -lt "$END_EPOCH" ]; do
    case $(rnd 6) in
      0) # "page view": 2–3 request cepat (HTML + aset) — meniru browser membuka halaman.
         n=$(( (RANDOM % 2) + 2 ))
         for ((k=0; k<n; k++)); do
           p="${WEB_PATHS[$(rnd ${#WEB_PATHS[@]})]}"
           curl -s -m 6 -o /dev/null "http://$WEB$p" 2>/dev/null
         done
         echo "  web x$n" ;;
      1) n="${DNS_NAMES[$(rnd ${#DNS_NAMES[@]})]}"
         getent hosts "$n" >/dev/null 2>&1 && echo "  dns $n" ;;
      2) curl -s -m 8 -u "$LUSER:$LPASS" "ftp://$FILE/" -o /dev/null 2>/dev/null && echo "  ftp list"
         curl -s -m 8 -u "$LUSER:$LPASS" -T "$TMP/upload.bin" "ftp://$FILE/normal_$(date +%s)_${BASHPID}.bin" 2>/dev/null && echo "  ftp put" ;;
      3) if command -v sshpass >/dev/null 2>&1; then
           sshpass -p "$LPASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
             -o ConnectTimeout=6 "$LUSER@$FILE" 'uptime >/dev/null; ls ~ >/dev/null' 2>/dev/null \
             && echo "  ssh srv-file"
         fi ;;
      4) t="$([ "$(rnd 2)" = 0 ] && echo "$WEB" || echo "$FILE")"
         ping -c 2 -i 0.3 "$t" >/dev/null 2>&1 && echo "  ping $t" ;;
      5) # unduhan HTTP kecil (tambah byte + keragaman aktivitas)
         curl -s -m 6 -o /dev/null "http://$WEB/favicon.ico" 2>/dev/null
         curl -s -m 6 -o /dev/null "http://$WEB/dvwa/" 2>/dev/null
         echo "  http dl" ;;
    esac
    think
  done
}

# jalankan N worker paralel lalu tunggu semua selesai
for ((w=1; w<=WORKERS; w++)); do worker & done
wait

ENDT="$(now)"
echo "N01,Normal,any,benign,$START,$ENDT" >> "$MARK"
echo "[N01] selesai $ENDT (marker -> $MARK)"
# CAVEAT: upload FTP meninggalkan file normal_*.bin di srv-file; bersih otomatis saat
# restore-golden srv-file, atau hapus manual bila capture tanpa restore.
