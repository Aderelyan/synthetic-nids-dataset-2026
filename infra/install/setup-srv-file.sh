#!/usr/bin/env bash
# srv-file: pasang Samba + vsftpd sebagai target S02 (FTP) / S03,S10 (SMB).
# Dijalankan SEBAGAI ROOT di dalam srv-file. Butuh NIC NAT aktif (internet).
# Kredensial lab labadmin/labadmin memang lemah — ini target brute-force, bukan produksi.
set -e
export DEBIAN_FRONTEND=noninteractive

# --- pastikan internet lewat NIC NAT sementara ---
for i in $(ls /sys/class/net | grep -vE '^(lo|enp0s3)$'); do ip link set "$i" up 2>/dev/null || true; done
dhclient 2>/dev/null || true
if ! apt-get update; then echo "NET-FAIL (apt update gagal — NIC NAT belum dapat internet)"; exit 2; fi

apt-get install -y samba vsftpd

# --- Samba share ---
mkdir -p /srv/labshare
chown labadmin:labadmin /srv/labshare
cat > /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = LABWORKGROUP
   server string = srv-file
   security = user
   map to guest = never
   log file = /var/log/samba/log.%m
[labshare]
   path = /srv/labshare
   valid users = labadmin
   read only = no
   browseable = yes
EOF
(echo 'labadmin'; echo 'labadmin') | smbpasswd -s -a labadmin
systemctl enable --now smbd nmbd

# --- vsftpd (login user lokal) ---
cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pam_service_name=vsftpd
EOF
systemctl enable --now vsftpd

echo "--- status ---"
systemctl is-active smbd nmbd vsftpd
echo "SETUP-OK-SRVFILE"
