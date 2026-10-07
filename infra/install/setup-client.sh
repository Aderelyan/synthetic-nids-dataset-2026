#!/usr/bin/env bash
# client-1 / client-2: pasang curl (generator traffic normal) + sudo.
# Dijalankan SEBAGAI ROOT di dalam client. Butuh NIC NAT aktif (internet).
set -e
export DEBIAN_FRONTEND=noninteractive

for i in $(ls /sys/class/net | grep -vE '^(lo|enp0s3)$'); do ip link set "$i" up 2>/dev/null || true; done
dhclient 2>/dev/null || true
if ! apt-get update; then echo "NET-FAIL (apt update gagal — NIC NAT belum dapat internet)"; exit 2; fi

apt-get install -y sudo curl
usermod -aG sudo labadmin 2>/dev/null || true

echo "--- status ---"
command -v sudo && command -v curl
echo "SETUP-OK-CLIENT"
