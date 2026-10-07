#!/usr/bin/env bash
# srv-web: aktifkan docker + pastikan container DVWA jalan (target S04 SQLi).
# Dijalankan SEBAGAI ROOT di dalam srv-web. docker sudah terpasang.
# NIC NAT hanya diperlukan kalau image DVWA belum ada (perlu pull).
set -e

for i in $(ls /sys/class/net | grep -vE '^(lo|enp0s3)$'); do ip link set "$i" up 2>/dev/null || true; done
dhclient 2>/dev/null || true

systemctl enable --now docker

if docker ps -a --format '{{.Names}}' | grep -qx dvwa; then
  docker start dvwa || true
else
  echo "Container dvwa belum ada, menarik image (butuh internet)..."
  docker run -d -p 80:80 --name dvwa vulnerables/web-dvwa
fi
sleep 6

echo "--- status ---"
systemctl is-active docker
docker ps --filter name=dvwa --format '{{.Names}} {{.Status}}'
# DVWA harus Up; security level diset Low lewat UI saat Phase 7 (butuh login web)
echo "SETUP-OK-SRVWEB"
