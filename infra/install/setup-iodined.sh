#!/usr/bin/env bash
# srv-file: pasang iodine (menyediakan daemon iodined) untuk S09 DNS tunneling.
# Dijalankan SEBAGAI ROOT di srv-file. Butuh NIC NAT aktif (internet).
# Unit systemd dibuat TAPI TIDAK di-enable/start — dinyalakan MANUAL saat capture
# S09 saja (biar baseline bersih, tak ada listener nganggur).
set -e
export DEBIAN_FRONTEND=noninteractive

# Cek apakah paket deb lokal tersedia (offline transfer dari host)
if [ -f /tmp/iodine.deb ]; then
    echo "Memasang iodine dari paket deb lokal (/tmp/iodine.deb)..."
    dpkg -i /tmp/iodine.deb || apt-get install -f -y
else
    # internet lewat NIC NAT sementara
    for i in $(ls /sys/class/net | grep -vE '^(lo|enp0s3)$'); do ip link set "$i" up 2>/dev/null || true; done
    dhclient 2>/dev/null || true
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf
    if ! apt-get update -o Acquire::Retries=3; then echo "NET-FAIL (apt update gagal — NIC NAT belum dapat internet)"; exit 2; fi
    apt-get install -y -o Acquire::Retries=5 iodine
fi

cat > /etc/systemd/system/iodined.service <<'EOF'
[Unit]
Description=iodine DNS tunnel server (S09) - start MANUAL saat capture
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/sbin/iodined -f -c -P labtunnel 172.16.254.1 tunnel.lab.local
Restart=no
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
# sengaja TIDAK 'enable'/'start' — S09 nanti: sudo systemctl start iodined

echo "--- status ---"
command -v iodined && command -v iodine
systemctl is-enabled iodined 2>/dev/null || echo "iodined: disabled (benar, start manual saat S09)"
echo "SETUP-OK-IODINED"
