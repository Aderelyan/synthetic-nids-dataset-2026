#!/usr/bin/env bash
# Cek software per VM (READ-ONLY) -> laporan Markdown.
# Jalankan di git-bash HOST, lewat Hermes atau manual.
#
# Prasyarat (jalankan dulu di shell yang sama):
#   export PATH="/c/msys64/usr/bin:$PATH"          # ssh + sshpass dari msys2
#   export USER_LINUX=...   PASS_LINUX=...          # srv-web/srv-file/client-1/client-2
#   export USER_SENSOR=...  PASS_SENSOR=...         # sensor (akun beda)
#   export USER_KALI=...    PASS_KALI=...           # attacker
#   # router jump default root/root; override kalau beda:
#   export USER_ROUTER=root PASS_ROUTER=root
#
# Skrip ini TIDAK memasang apa pun dan TIDAK mengubah VM selain menyala/mematikan
# (ACPI). Router dibiarkan menyala sebagai jump host. Satu VM target nyala per waktu.

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"

command -v sshpass >/dev/null || { echo "ERROR: sshpass tidak ditemukan di /c/msys64/usr/bin. Pastikan MSYS2 + sshpass terpasang."; exit 1; }

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }

echo "Masukkan kredensial (tekan Enter untuk pakai default di dalam kurung):"
USER_LINUX=$(ask  "User srv-web/srv-file/client-1/client-2" labadmin)
PASS_LINUX=$(asksecret "  password" labadmin)
USER_SENSOR=$(ask "User sensor" sensor)
PASS_SENSOR=$(asksecret "  password" sensor)
USER_KALI=$(ask   "User attacker (kali)" kali)
PASS_KALI=$(asksecret "  password" kali)
USER_ROUTER=$(ask "User router jump" root)
PASS_ROUTER=$(asksecret "  password" root)
echo

RPT="validation/laporan-software-$(date +%Y%m%d-%H%M%S).md"
mkdir -p validation
SSHOPTS="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }
stopvm(){ [ "$(vmstate "$1")" = running ] || return 0; VBoxManage controlvm "$1" acpipowerbutton >/dev/null 2>&1
  for _ in $(seq 1 36); do sleep 5; [ "$(vmstate "$1")" != running ] && return 0; done; }

# runssh <mode direct|jump> <user> <pass> <ip> <remote-cmd>
runssh(){ local m=$1 u=$2 p=$3 ip=$4 cmd=$5
  if [ "$m" = direct ]; then
    SSH_AUTH_SOCK= sshpass -p "$p" ssh $SSHOPTS "$u@$ip" "$cmd" 2>&1
  else
    SSH_AUTH_SOCK= sshpass -p "$p" ssh $SSHOPTS -o ProxyCommand="sshpass -p '$PASS_ROUTER' ssh $SSHOPTS -W %h:%p $USER_ROUTER@192.168.56.10" "$u@$ip" "$cmd" 2>&1
  fi
}

# remote command: cek daftar binary + daftar service. Argumen: "<bins>" "<svcs>" [extra]
mkcmd(){ local bins=$1 svcs=$2 extra=${3:-}
  printf 'for b in %s; do if command -v "$b" >/dev/null 2>&1; then echo "bin $b: OK"; elif [ -x "/usr/sbin/$b" ] || [ -x "/sbin/$b" ]; then echo "bin $b: OK (sbin)"; else echo "bin $b: MISSING"; fi; done; ' "$bins"
  [ -n "$svcs" ] && printf 'for s in %s; do printf "svc %%s: " "$s"; systemctl is-active "$s" 2>/dev/null || echo "(?)"; done; ' "$svcs"
  [ -n "$extra" ] && printf '%s' "$extra"
}

declare -a NAME MODE IP USR PAS CMD
add(){ NAME+=("$1"); MODE+=("$2"); IP+=("$3"); USR+=("$4"); PAS+=("$5"); CMD+=("$6"); }

ZEEK='test -x /opt/zeek/bin/zeek && echo "bin zeek: OK (/opt/zeek/bin)" || echo "bin zeek: MISSING"; '
add sensor   direct 192.168.56.20 "$USER_SENSOR" "$PASS_SENSOR" "$(mkcmd 'tcpdump suricata argus ra' 'suricata' "$ZEEK")"
add srv-web  jump   10.10.10.10   "$USER_LINUX" "$PASS_LINUX" "$(mkcmd 'docker curl' 'ssh docker' 'echo "catatan: container DVWA cek manual: sudo docker ps --filter name=dvwa";')"
add srv-file jump   10.10.10.11   "$USER_LINUX" "$PASS_LINUX" "$(mkcmd 'sudo smbd vsftpd' 'ssh rsyslog smbd vsftpd' '')"
add client-1 jump   10.10.20.20   "$USER_LINUX" "$PASS_LINUX" "$(mkcmd 'sudo curl python3' 'ssh' '')"
add client-2 jump   10.10.20.21   "$USER_LINUX" "$PASS_LINUX" "$(mkcmd 'sudo curl python3' 'ssh' '')"
add attacker jump   10.10.30.10   "$USER_KALI"  "$PASS_KALI"  "$(mkcmd 'nmap hydra hping3 nc impacket-secretsdump pypykatz sqlmap iodine evil-winrm nxc crackmapexec' '' '')"

{
  echo "# Laporan Cek Software VM (READ-ONLY)"
  echo
  echo "Dibuat: $(date -u '+%Y-%m-%d %H:%M:%SZ') (UTC host)"
  echo
  echo "> router-opnsense dilewati (shell OPNsense = menu). Layanan Unbound (DNS) & ntpd sudah divalidasi terpisah."
  echo "> win-client (Windows) dicek manual — lihat pesan chat."
  echo
} > "$RPT"

# pastikan router nyala, matikan semua target
[ "$(vmstate router-opnsense)" = running ] || { VBoxManage startvm router-opnsense --type headless >/dev/null 2>&1; sleep 40; }
for n in "${NAME[@]}"; do stopvm "$n"; done

for i in "${!NAME[@]}"; do
  n=${NAME[$i]}; echo "===== $n ====="
  VBoxManage startvm "$n" --type headless >/dev/null 2>&1
  ok=""
  for _ in $(seq 1 30); do
    out=$(runssh "${MODE[$i]}" "${USR[$i]}" "${PAS[$i]}" "${IP[$i]}" 'echo __UP__')
    case "$out" in *__UP__*) ok=1; break;; esac
    sleep 10
  done
  {
    echo "## $n (${IP[$i]})"
    echo
    if [ -z "$ok" ]; then
      echo '```'; echo "KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual."; echo '```'
    else
      echo '```'; runssh "${MODE[$i]}" "${USR[$i]}" "${PAS[$i]}" "${IP[$i]}" "${CMD[$i]}"; echo '```'
    fi
    echo
  } >> "$RPT"
  stopvm "$n"
done

{
  echo "## Ringkasan yang perlu dipasang (harapan awal)"
  echo "- srv-file: **smbd (samba)** dan **vsftpd** → kemungkinan MISSING, memang belum dipasang."
  echo "- attacker: **iodine** (S09) dan **evil-winrm**/**nxc** (S06) → kemungkinan MISSING."
  echo "- client-1/2: **curl** → kalau MISSING, perlu untuk generator traffic normal."
  echo "- Baris bertanda MISSING / svc inactive = kandidat instalasi tahap berikutnya."
} >> "$RPT"

echo; echo "Selesai. Laporan: $RPT"; cat "$RPT"
