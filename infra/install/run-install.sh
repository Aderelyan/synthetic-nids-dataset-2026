#!/usr/bin/env bash
# Orkestrasi instalasi software (host-side). Menjalankan setup-*.sh di dalam
# srv-file, srv-web, client-1, client-2 lewat NIC NAT sementara, lalu melepas
# NAT & mengambil ulang golden snapshot.
#
# ATURAN: setiap langkah dicoba maksimal 3x. Kalau tetap gagal -> BERHENTI,
# cetak pesan STOP, keluar. JANGAN cari solusi lain.
#
# Tiap install dicoba lewat `sudo`; kalau sudo tak ada/gagal (mis. client-2),
# otomatis jatuh ke `su -` dengan root/root.
#
# Jalankan dari root repo:  bash infra/install/run-install.sh

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
command -v sshpass >/dev/null || { echo "ERROR: sshpass tak ada di /c/msys64/usr/bin"; exit 1; }
for s in setup-srv-file setup-srv-web setup-client; do
  [ -f "infra/install/$s.sh" ] || { echo "ERROR: infra/install/$s.sh tidak ditemukan. Jalankan dari root repo."; exit 1; }
done

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }
echo "Kredensial (Enter = default):"
USER_LINUX=$(ask  "User srv-file/srv-web/client-1" labadmin)
PASS_LINUX=$(asksecret "  password" labadmin)
PASS_ROUTER=$(asksecret "Password router jump (root)" root)
echo

SSHOPTS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12"
PROXY="sshpass -p '$PASS_ROUTER' ssh $SSHOPTS -W %h:%p root@192.168.56.10"

sshrun(){ SSH_AUTH_SOCK= sshpass -p "$PASS_LINUX" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_LINUX@$1" "$2" 2>&1; }
sshcopy(){ SSH_AUTH_SOCK= sshpass -p "$PASS_LINUX" ssh $SSHOPTS -o ProxyCommand="$PROXY" "$USER_LINUX@$1" "cat > $2" < "$3" 2>&1; }
# fallback kalau sudo tak ada: login labadmin -> `su -` (pw root), jalankan /tmp/setup.sh.
# Butuh PTY (-tt) karena su baca password dari terminal, bukan stdin biasa.
# Baris pertama yang dikirim = password root ('root'), lalu perintah, lalu exit.
PASS_SU=root
sshrun_su(){ printf '%s\nbash /tmp/setup.sh; exit\n' "$PASS_SU" | SSH_AUTH_SOCK= sshpass -p "$PASS_LINUX" ssh -tt $SSHOPTS -o ProxyCommand="$PROXY" "$USER_LINUX@$1" "su -" 2>&1; }
vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }
stopvm(){ [ "$(vmstate "$1")" = running ] || return 0; VBoxManage controlvm "$1" acpipowerbutton >/dev/null 2>&1
  for _ in $(seq 1 36); do sleep 5; [ "$(vmstate "$1")" != running ] && return 0; done; return 1; }

STOP(){ echo; echo "================ STOP ================"; echo "$1"; echo "Proses dihentikan. Laporkan ini ke user, JANGAN lanjut atau cari solusi sendiri."; exit 1; }

# pastikan router nyala (jump host) + NatNetwork-temp aktif
[ "$(vmstate router-opnsense)" = running ] || { VBoxManage startvm router-opnsense --type headless >/dev/null 2>&1; sleep 40; }
VBoxManage natnetwork start --netname "NatNetwork-temp" >/dev/null 2>&1 || true

install_vm(){ # <vm> <ip> <scriptfile>
  local vm=$1 ip=$2 scr=$3
  echo "===================== $vm ====================="
  # hanya router + vm ini yang nyala
  for other in srv-file srv-web client-1 client-2 sensor attacker win-client; do
    [ "$other" = "$vm" ] && continue
    stopvm "$other" || STOP "$other tidak mau mati (butuh RAM bebas sebelum $vm). "
  done
  stopvm "$vm" || STOP "$vm tidak mau dimatikan untuk pasang NIC NAT."

  # pasang NIC NAT sementara
  VBoxManage modifyvm "$vm" --nic2 natnetwork --nat-network2 "NatNetwork-temp" || STOP "Gagal pasang NIC NAT di $vm."
  VBoxManage startvm "$vm" --type headless >/dev/null 2>&1

  # tunggu SSH siap (maks ~3 menit)
  local up=""
  for _ in $(seq 1 18); do
    case "$(sshrun "$ip" 'echo __UP__')" in *__UP__*) up=1; break;; esac
    sleep 10
  done
  [ -n "$up" ] || STOP "$vm ($ip): SSH tidak siap setelah 3 menit (cek: VM nyala? jump router OK? password benar?)."

  # salin skrip (3x)
  local ok=""
  for t in 1 2 3; do
    sshcopy "$ip" /tmp/setup.sh "$scr" >/dev/null 2>&1 && { ok=1; break; }
    sleep 5
  done
  [ -n "$ok" ] || STOP "$vm: gagal menyalin skrip setup setelah 3x."

  # jalankan skrip (3x) — coba sudo dulu; kalau sudo tak ada/gagal, fallback `su -` (root/root).
  # Cari penanda SETUP-OK.
  ok=""
  local out=""
  for t in 1 2 3; do
    out=$(sshrun "$ip" "echo '$PASS_LINUX' | sudo -S bash /tmp/setup.sh 2>&1")
    case "$out" in
      *SETUP-OK*) echo "--- percobaan $t ($vm) via sudo ---"; echo "$out" | tail -n 8; ok=1; break;;
    esac
    # sudo gagal/tak ada -> coba su -
    out=$(sshrun_su "$ip")
    echo "--- percobaan $t ($vm) via su - ---"; echo "$out" | tail -n 8
    case "$out" in *SETUP-OK*) ok=1; break;; esac
    sleep 8
  done
  [ -n "$ok" ] || STOP "$vm: skrip setup gagal 3x via sudo maupun su- (tidak ada SETUP-OK). Output terakhir di atas — kemungkinan NET-FAIL (NIC NAT tak dapat internet), password root/labadmin salah, atau su diblokir."

  # lepas NAT + snapshot ulang (offline)
  stopvm "$vm" || STOP "$vm tidak mau dimatikan sebelum lepas NAT."
  VBoxManage modifyvm "$vm" --nic2 none || STOP "Gagal melepas NIC NAT di $vm (JANGAN snapshot sebelum ini beres)."
  VBoxManage snapshot "$vm" delete golden >/dev/null 2>&1 || true
  VBoxManage snapshot "$vm" take golden >/dev/null 2>&1 || STOP "Gagal mengambil golden snapshot $vm."
  echo ">>> $vm SELESAI: software terpasang, NAT dilepas, golden snapshot baru dibuat."
}

install_vm srv-file 10.10.10.11 infra/install/setup-srv-file.sh
install_vm srv-web  10.10.10.10 infra/install/setup-srv-web.sh
install_vm client-1 10.10.20.20 infra/install/setup-client.sh
install_vm client-2 10.10.20.21 infra/install/setup-client.sh   # tanpa sudo -> otomatis lewat su -

echo
echo "=== SEMUA SELESAI (srv-file, srv-web, client-1, client-2) ==="
echo "Sapuan NIC NAT (harus kosong untuk keempatnya):"
for v in srv-file srv-web client-1 client-2; do echo "--- $v"; VBoxManage showvminfo "$v" --machinereadable | grep -i natnet || echo "(bersih)"; done
