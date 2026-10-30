#!/usr/bin/env bash
# Pasang sshpass + NOPASSWD di attacker via NIC NAT sementara, lalu lepas NAT +
# golden ulang (biar sshpass, NOPASSWD, dan ~/scenarios yang sudah ter-deploy
# IKUT ke golden -> restore berikutnya langsung siap). Pola sama install-iodined.sh.
# Jalankan dari ROOT repo:  bash infra/install/install-sshpass-attacker.sh
#
# CATATAN: skrip ini TIDAK restore golden (biar ~/scenarios di disk attacker tetap
# ada dan ikut ter-bake). Hanya poweroff -> NAT -> install -> lepas NAT -> golden.

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
command -v sshpass >/dev/null || { echo "ERROR: sshpass tak ada di /c/msys64/usr/bin (host)"; exit 1; }
[ -f infra/install/setup-sshpass.sh ] || { echo "ERROR: infra/install/setup-sshpass.sh tak ada — jalankan dari root repo."; exit 1; }

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }
echo "Kredensial (Enter = default):"
USER_AT=$(ask "User attacker" kali); PASS_AT=$(asksecret "  pw" kali)
PASS_ROUTER=$(asksecret "pw router jump (root)" root)
echo

IP=10.10.30.10
SSHOPTS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
PROXY="sshpass -p '$PASS_ROUTER' ssh $SSHOPTS -W %h:%p root@192.168.56.10"
sshrun(){ timeout 600 env SSH_AUTH_SOCK= sshpass -p "$PASS_AT" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_AT@$1" "$2" 2>&1; }  # 600s: apt Kali-rolling index besar
sshcopy(){ timeout 60 env SSH_AUTH_SOCK= sshpass -p "$PASS_AT" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_AT@$1" "cat > $2" < "$3" 2>&1; }
vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }
stopvm(){ local s; s=$(vmstate "$1")
  case "$s" in
    saved|paused) VBoxManage discardstate "$1" >/dev/null 2>&1 || true; return 0 ;;
    running) VBoxManage controlvm "$1" acpipowerbutton >/dev/null 2>&1
      for _ in $(seq 1 36); do sleep 5; [ "$(vmstate "$1")" != running ] && return 0; done; return 1 ;;
    *) return 0 ;;
  esac; }
STOP(){ echo; echo "================ STOP ================"; echo "$1"; echo "Lapor ke user, JANGAN improvisasi."; exit 1; }

[ "$(vmstate router-opnsense)" = running ] || { echo "Menyalakan router..."; VBoxManage startvm router-opnsense --type headless >/dev/null 2>&1; sleep 40; }
VBoxManage natnetwork start --netname "NatNetwork-temp" >/dev/null 2>&1 || true

echo "===== attacker: pasang sshpass + NOPASSWD ====="
stopvm attacker || STOP "attacker tak mau mati untuk pasang NIC NAT."
VBoxManage modifyvm attacker --nic2 natnetwork --nat-network2 "NatNetwork-temp" || STOP "Gagal pasang NIC NAT di attacker."
VBoxManage startvm attacker --type headless >/dev/null 2>&1

up=""
for _ in $(seq 1 18); do case "$(sshrun "$IP" 'echo __UP__')" in *__UP__*) up=1; break;; esac; sleep 10; done
[ -n "$up" ] || STOP "attacker ($IP): SSH tak siap setelah 3 menit."

ok=""
for t in 1 2 3; do sshcopy "$IP" /tmp/setup-sshpass.sh infra/install/setup-sshpass.sh >/dev/null 2>&1 && { ok=1; break; }; sleep 5; done
[ -n "$ok" ] || STOP "Gagal menyalin setup-sshpass.sh 3x."

ok=""; out=""
for t in 1 2 3; do
  out=$(sshrun "$IP" "echo '$PASS_AT' | sudo -S bash /tmp/setup-sshpass.sh 2>&1")
  echo "--- percobaan $t ---"; echo "$out" | tail -n 10
  case "$out" in *SETUP-OK-SSHPASS*) ok=1; break;; esac
  sleep 8
done
[ -n "$ok" ] || STOP "install sshpass gagal 3x (tidak ada SETUP-OK-SSHPASS). Kemungkinan NET-FAIL."

# verifikasi ~/scenarios masih ada (akan ikut ter-bake)
echo "--- cek ~/scenarios di attacker ---"; sshrun "$IP" "ls ~/scenarios 2>/dev/null | head; [ -d ~/scenarios ] && echo SCENARIOS-ADA || echo SCENARIOS-HILANG"

stopvm attacker || STOP "attacker tak mau mati sebelum lepas NAT."
VBoxManage modifyvm attacker --nic2 none || STOP "Gagal melepas NIC NAT (JANGAN snapshot sebelum ini beres)."
if VBoxManage showvminfo attacker --machinereadable | grep -qi natnet; then STOP "NAT masih menempel di attacker — JANGAN snapshot."; fi
echo "(NIC bersih)"
VBoxManage snapshot attacker delete golden >/dev/null 2>&1 || true
VBoxManage snapshot attacker take golden >/dev/null || STOP "Gagal mengambil golden snapshot attacker."
echo ">>> attacker SELESAI: sshpass + NOPASSWD + scenarios ter-bake, NAT lepas, golden baru."
VBoxManage snapshot attacker list | grep -i golden
