#!/usr/bin/env bash
# pull-raw-archive.sh — tarik RAW pcap + markers dari sensor:~/pcap-archive/<TAG> ke host raw-archive/<TAG>.
# Pakai (di git-bash, dari ROOT repo):
#   bash infra/pull-raw-archive.sh <TAG>
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
SENSOR_PW='sensor'
SENSOR=192.168.56.20
TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "Pakai: bash infra/pull-raw-archive.sh <TAG>"
  echo "Daftar arsip di sensor:"
  sshpass -p "$SENSOR_PW" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 \
    sensor@$SENSOR "ls -1t ~/pcap-archive 2>/dev/null || echo '(kosong)'"
  exit 0
fi
O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12"
SRC="sensor@$SENSOR:/home/sensor/pcap-archive/$TAG"
DST="raw-archive/$TAG"

# cek TAG ada di sensor
sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "test -d '/home/sensor/pcap-archive/$TAG'" \
  || { echo "STOP: arsip '$TAG' tak ada di sensor (~/pcap-archive/$TAG)."; exit 1; }

mkdir -p "raw-archive"
echo "tarik $SRC -> $DST ..."
# -r rekursif; salin isi folder TAG (enp0s8/enp0s9/enp0s10/markers.csv) ke raw-archive/<TAG>/
sshpass -p "$SENSOR_PW" scp -r $O "$SRC" "raw-archive/" || { echo "STOP: scp gagal."; exit 1; }

# verifikasi jumlah file (sensor vs host)
NS=$(sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "find '/home/sensor/pcap-archive/$TAG' -type f | wc -l" | tr -d ' \r')
NH=$(find "$DST" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "file sensor=$NS host=$NH"
[ "$NS" = "$NH" ] && echo "SELESAI -> $DST/ ($NH file)" || echo "!! JUMLAH FILE BERBEDA — ulangi: bash infra/pull-raw-archive.sh $TAG"
