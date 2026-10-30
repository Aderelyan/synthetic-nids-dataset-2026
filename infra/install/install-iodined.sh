#!/usr/bin/env bash
# Pasang iodined di srv-file via NIC NAT sementara, lalu lepas NAT + golden ulang.
# Pola sama dengan run-install.sh (yang sudah sukses). srv-file punya sudo.
# Jalankan dari ROOT repo:  bash infra/install/install-iodined.sh
#
# ATURAN: tiap langkah maksimal 3x. Gagal -> cetak STOP, keluar. JANGAN improvisasi.

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
command -v sshpass >/dev/null || { echo "ERROR: sshpass tak ada di /c/msys64/usr/bin"; exit 1; }
[ -f infra/install/setup-iodined.sh ] || { echo "ERROR: infra/install/setup-iodined.sh tak ada — jalankan dari root repo."; exit 1; }

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }
echo "Kredensial (Enter = default):"
USER_LINUX=$(ask "User srv-file" labadmin); PASS_LINUX=$(asksecret "  pw" labadmin)
PASS_ROUTER=$(asksecret "pw router jump (root)" root)
echo

IP=10.10.10.11
SSHOPTS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
PROXY="sshpass -p '$PASS_ROUTER' ssh $SSHOPTS -W %h:%p root@192.168.56.10"
sshrun(){ timeout 150 env SSH_AUTH_SOCK= sshpass -p "$PASS_LINUX" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_LINUX@$1" "$2" 2>&1; }
sshcopy(){ timeout 60 env SSH_AUTH_SOCK= sshpass -p "$PASS_LINUX" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_LINUX@$1" "cat > $2" < "$3" 2>&1; }
vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }
stopvm(){ local s; s=$(vmstate "$1")
  case "$s" in
    saved|paused) VBoxManage discardstate "$1" >/dev/null 2>&1 || true; return 0 ;;  # Saved -> poweroff (snapshot aman)
    running) VBoxManage controlvm "$1" acpipowerbutton >/dev/null 2>&1
      for _ in $(seq 1 36); do sleep 5; [ "$(vmstate "$1")" != running ] && return 0; done; return 1 ;;
    *) return 0 ;;
  esac; }
STOP(){ echo; echo "================ STOP ================"; echo "$1"; echo "Lapor ke user, JANGAN improvisasi/cari solusi sendiri."; exit 1; }

# router nyala (jump host) + NatNetwork-temp aktif
[ "$(vmstate router-opnsense)" = running ] || { echo "Menyalakan router..."; VBoxManage startvm router-opnsense --type headless >/dev/null 2>&1; sleep 40; }
VBoxManage natnetwork start --netname "NatNetwork-temp" >/dev/null 2>&1 || true

echo "===== srv-file: pasang iodined ====="
stopvm srv-file || STOP "srv-file tak mau mati untuk pasang NIC NAT."
VBoxManage modifyvm srv-file --nic2 natnetwork --nat-network2 "NatNetwork-temp" || STOP "Gagal pasang NIC NAT di srv-file."
VBoxManage startvm srv-file --type headless >/dev/null 2>&1

up=""
for _ in $(seq 1 18); do case "$(sshrun "$IP" 'echo __UP__')" in *__UP__*) up=1; break;; esac; sleep 10; done
[ -n "$up" ] || STOP "srv-file ($IP): SSH tak siap setelah 3 menit (router OK? password benar?)."

ok=""
for t in 1 2 3; do sshcopy "$IP" /tmp/setup-iodined.sh infra/install/setup-iodined.sh >/dev/null 2>&1 && { ok=1; break; }; sleep 5; done
[ -n "$ok" ] || STOP "Gagal menyalin setup-iodined.sh 3x."

# Salin juga paket deb lokal jika ada di host (offline bypass flakiness NAT DNS)
if [ -f /c/Users/Aderelyan/iodine.deb ]; then
  sshcopy "$IP" /tmp/iodine.deb /c/Users/Aderelyan/iodine.deb >/dev/null 2>&1 || true
fi

ok=""; out=""
for t in 1 2 3; do
  out=$(sshrun "$IP" "echo '$PASS_LINUX' | sudo -S bash /tmp/setup-iodined.sh 2>&1")
  echo "--- percobaan $t ---"; echo "$out" | tail -n 10
  case "$out" in *SETUP-OK-IODINED*) ok=1; break;; esac
  sleep 8
done
[ -n "$ok" ] || STOP "setup iodined gagal 3x (tidak ada SETUP-OK-IODINED). Kemungkinan NET-FAIL (NIC NAT tak dapat internet)."

# lepas NAT + golden ulang (offline)
stopvm srv-file || STOP "srv-file tak mau mati sebelum lepas NAT."
VBoxManage modifyvm srv-file --nic2 none || STOP "Gagal melepas NIC NAT (JANGAN snapshot sebelum ini beres)."
if VBoxManage showvminfo srv-file --machinereadable | grep -qi natnet; then STOP "NAT masih menempel di srv-file — JANGAN snapshot."; fi
echo "(NIC bersih)"
VBoxManage snapshot srv-file delete golden >/dev/null 2>&1 || true
VBoxManage snapshot srv-file take golden >/dev/null || STOP "Gagal mengambil golden snapshot srv-file."
echo ">>> srv-file SELESAI: iodine terpasang, unit iodined (disabled, start manual S09), NAT lepas, golden baru."
VBoxManage snapshot srv-file list | grep -i golden
