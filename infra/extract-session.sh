#!/usr/bin/env bash
# extract-session.sh — EKSTRAKSI dari ARSIP pcap di sensor (dari HOST git-bash).
# Tiap capture (capture-session*.sh) MENGARSIPKAN pcap+marker ke sensor:~/pcap-archive/<TAG>
# di akhir sesi, jadi pcap TAK HILANG walau sesi lain (yg clean working-dir) jalan belakangan.
# Skrip ini menjalankan pipeline atas SATU arsip -> CSV ke extract-out/<TAG>/.
#
# Pakai:
#   bash infra/extract-session.sh              # tampilkan daftar arsip di sensor
#   bash infra/extract-session.sh <TAG>        # ekstrak arsip <TAG>
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"; export MSYS_NO_PATHCONV=1
SENSOR_PW=sensor
O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12"
SENS(){ sshpass -p $SENSOR_PW ssh $O sensor@192.168.56.20 "$1"; }

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "Arsip pcap di sensor (~/pcap-archive):"
  SENS "ls -1t ~/pcap-archive 2>/dev/null || echo '(kosong)'"
  echo; echo "Pakai: bash infra/extract-session.sh <TAG>"; exit 0
fi
ARCH="/home/sensor/pcap-archive/$TAG"
SENS "test -d '$ARCH'" || { echo "STOP: arsip '$TAG' tak ada di sensor ($ARCH)."; exit 1; }

OUTDIR_HOST="$(pwd)/extract-out/$TAG"; mkdir -p "$OUTDIR_HOST"

echo "== marker arsip $TAG =="
SENS "cat '$ARCH/markers.csv'"
echo "== kirim extract-build.sh + jalankan pipeline atas arsip (bisa beberapa menit) =="
cat pipeline/extract-build.sh | SENS "cat > ~/pipeline/extract-build.sh; chmod +x ~/pipeline/extract-build.sh"
SENS "bash ~/pipeline/extract-build.sh '$ARCH/markers.csv' ~/extract-$TAG '$ARCH' 2>&1"

echo "== tarik CSV + markers ke host =="
# tulis .tmp -> cek jumlah baris sensor vs host -> ganti (anti terpotong & anti file terkunci)
pull(){ # $1 = path ABSOLUT di sensor, $2 = path lokal
  local nr nl
  if ! SENS "cat '$1'" > "$2.tmp" 2>/dev/null || [ ! -s "$2.tmp" ]; then
    echo "  GAGAL tarik $1 (tutup program yg buka $2?)."; rm -f "$2.tmp"; return 1; fi
  nr=$(SENS "wc -l < '$1'" | tr -d ' \r'); nl=$(wc -l < "$2.tmp" | tr -d ' \r')
  [ "$nr" = "$nl" ] || { echo "  !! MISMATCH baris sensor=$nr host=$nl -> ulangi."; rm -f "$2.tmp"; return 1; }
  mv -f "$2.tmp" "$2" 2>/dev/null || { echo "  !! $2 TERKUNCI (OneDrive/editor). data di $2.tmp"; return 1; }
  echo "  OK $2 ($nl baris)"
}
ok=1
pull "$ARCH/markers.csv"                         "$OUTDIR_HOST/markers.csv"    || ok=0
pull "/home/sensor/extract-$TAG/unsw.csv"        "$OUTDIR_HOST/unsw.csv"       || ok=0
pull "/home/sensor/extract-$TAG/unsw_multi.csv"  "$OUTDIR_HOST/unsw_multi.csv" || ok=0
[ "$ok" = 1 ] && echo "SELESAI -> $OUTDIR_HOST/ ; verifikasi: python infra/check-overlap.py extract-out/$TAG" \
             || echo "SELESAI SEBAGIAN — perbaiki yg gagal lalu ulang: bash infra/extract-session.sh $TAG"
