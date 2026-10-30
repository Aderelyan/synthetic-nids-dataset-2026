#!/usr/bin/env bash
# attacker (Kali): pasang sshpass (dibutuhkan S08 & S12) + NOPASSWD sudoers.
# Dijalankan SEBAGAI ROOT di attacker. Butuh NIC NAT aktif (internet).
set -e
export DEBIAN_FRONTEND=noninteractive

# internet lewat NIC NAT sementara (Kali: intnet=eth0, NAT=eth1)
for i in $(ls /sys/class/net | grep -vE '^(lo|eth0)$'); do ip link set "$i" up 2>/dev/null || true; done
dhclient 2>/dev/null || true
ip route replace default via 10.0.99.1 2>/dev/null || true   # default via NAT utk window ini

# DNS lab (10.10.30.1) hanya resolve *.lab.local -> pakai DNS publik lewat NAT utk apt.
# (Kali/NetworkManager mengunci resolver ke DNS lab, beda dari Debian yang pakai dhclient.)
cp -a /etc/resolv.conf /tmp/resolv.lab.bak 2>/dev/null || true
rm -f /etc/resolv.conf
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf

# matikan unduhan index 'Contents' (~54 MB, tak perlu utk install) + retry -> hemat waktu
APTNC='-o Acquire::IndexTargets::deb::Contents-deb::DefaultEnabled=false -o Acquire::IndexTargets::deb::Contents-deb-legacy::DefaultEnabled=false -o Acquire::Retries=3'
if ! apt-get $APTNC update; then
  printf 'nameserver 10.10.30.1\n' > /etc/resolv.conf   # kembalikan DNS lab sebelum keluar
  echo "NET-FAIL (apt update gagal via NAT — cek NatNetwork-temp)"; exit 2
fi
apt-get install -y sshpass

# kembalikan resolver lab supaya golden TIDAK membawa DNS publik
printf 'nameserver 10.10.30.1\n' > /etc/resolv.conf

# NOPASSWD sudo (lab attacker; weak-by-design) + bersihkan marker lama agar golden bersih
echo 'kali ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/kali-nopasswd
chmod 440 /etc/sudoers.d/kali-nopasswd
rm -f /home/kali/attack-markers.csv

echo "--- status ---"
command -v sshpass
sudo -n true && echo "NOPASSWD: OK"
grep -q '10.10.30.1' /etc/resolv.conf && echo "resolver lab dipulihkan"
echo "SETUP-OK-SSHPASS"
