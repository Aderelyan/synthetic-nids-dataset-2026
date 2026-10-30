#!/usr/bin/env bash
# Runner batch fase Linux (sesuai instruksi STEP 1 & STEP 2)
set -u
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
O="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
PX="sshpass -p 'root' ssh $O -W %h:%p root@192.168.56.10"
run(){ SSH_AUTH_SOCK= sshpass -p kali ssh $O -o ProxyCommand="$PX" kali@10.10.30.10 "cd ~/scenarios && bash $1"; }

echo "=========================================================="
echo "BATCH FASE LINUX DIMULAI: $(date -u '+%F %T') UTC"
echo "=========================================================="

# ===== STEP 1: 8 skenario dengan jeda 5 menit =====
SCENARIOS=(
  s01-port-scanning
  s02-bruteforce-ssh-ftp
  s03-password-spraying
  s04-web-injection-sqli
  s08-ssh-lateral-movement
  s10-ransomware-smb-sim
  s11-dos-ddos-hping3
  s12-data-exfiltration
)

for s in "${SCENARIOS[@]}"; do
  echo "===== MULAI $s @ $(date -u +%H:%M:%S)Z ====="
  run "./$s/run.sh"
  rc=$?
  echo "===== SELESAI $s (rc=$rc) @ $(date -u +%H:%M:%S)Z — jeda 5 menit ====="
  sleep 300
done

# ===== STEP 2: S09 (iodined di srv-file) =====
echo "===== STEP 2: MULAI s09-dns-tunneling-doh @ $(date -u +%H:%M:%S)Z ====="
# Unmask dan jalankan iodined di srv-file
SSH_AUTH_SOCK= sshpass -p labadmin ssh $O -o ProxyCommand="$PX" labadmin@10.10.10.11 '
  printf "#!/bin/sh\necho labadmin\n" > ~/.askpass && chmod 700 ~/.askpass
  export SUDO_ASKPASS=~/.askpass
  sudo -A systemctl unmask iodined.service 2>/dev/null || true
  sudo -A systemctl start iodined.service 2>/dev/null || true
  sleep 3
  systemctl is-active iodined.service || true
'
run "./s09-dns-tunneling-doh/run.sh"
rc=$?
echo "===== s09 rc=$rc ====="
SSH_AUTH_SOCK= sshpass -p labadmin ssh $O -o ProxyCommand="$PX" labadmin@10.10.10.11 '
  export SUDO_ASKPASS=~/.askpass
  sudo -A systemctl stop iodined.service 2>/dev/null || true
'
echo "===== SELESAI s09 — jeda 60s ====="
sleep 60

echo "=========================================================="
echo "BATCH SELESAI SELURUHNYA: $(date -u '+%F %T') UTC"
echo "=========================================================="
