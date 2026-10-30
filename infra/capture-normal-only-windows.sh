#!/usr/bin/env bash
# capture-normal-only-windows.sh — capture HANYA trafik Normal (TANPA skenario attack), fase WINDOWS.
# Alur: pre-check VM -> clean+start pcap sensor -> push+start gen-normal.ps1 di win-client (guestcontrol)
# -> tunggu marker N01 -> stop pcap -> arsip pcap+marker -> sensor:~/pcap-archive/<TAG>.
#
# Pakai (di git-bash, dari ROOT repo):
#   bash infra/capture-normal-only-windows.sh [DUR] [WORKERS]
#   default DUR=3600 (1 jam), WORKERS=4 (diteruskan ke gen-normal.ps1)
#
# Prasyarat: win-client NYALA (restore golden dulu), client-1/2 MATI, attacker+server+sensor NYALA.
# Guest Additions aktif (guestcontrol). Hasil RAW di sensor; tarik: bash infra/pull-raw-archive.sh <TAG>
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
export MSYS_NO_PATHCONV=1
SENSOR_PW='sensor'; ROOT_PW='root'; KALI_PW='kali'
SENSOR=192.168.56.20
WIN_VM="win-client"; WIN_USER="Admin_lab"; WIN_PASS='Admin@2024'
WIN_DIR='C:\LabData'
GEN_PS1_SRC="$(pwd)/scenarios/normal/gen-normal.ps1"
[ -f "$GEN_PS1_SRC" ] || { echo "STOP: gen-normal.ps1 tak ada (jalankan dari root repo)."; exit 1; }
GEN_PS1="$(cygpath -w "$GEN_PS1_SRC" 2>/dev/null || echo "$GEN_PS1_SRC")"
DUR="${1:-3600}"; WORKERS="${2:-4}"

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
sens(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "echo '$SENSOR_PW' | sudo -S bash -c '$1'"; }
sens_plain(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "$1"; }
gc(){ local sub="$1"; shift; VBoxManage guestcontrol "$WIN_VM" "$sub" --username "$WIN_USER" --password "$WIN_PASS" "$@"; }
vstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -q 'VMState="running"'; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*"; }

log "=== CAPTURE NORMAL-ONLY (Windows) DUR=${DUR}s WORKERS=$WORKERS ==="

# 0) pre-check fase
vstate "$WIN_VM" || { echo "STOP: $WIN_VM TIDAK running. Restore golden + startvm dulu."; exit 1; }
for c in client-1 client-2; do
  vstate "$c" && { echo "STOP: $c masih NYALA — fase Windows harus MATI. Matikan dulu."; exit 1; }
done

# 1) pcap bersih + start
log "clean+start pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10; rm -f /var/log/pcap/enp0s8/* /var/log/pcap/enp0s9/* /var/log/pcap/enp0s10/*; systemctl start pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
sleep 3
log "pcap: $(sens_plain "systemctl is-active pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10" | tr '\n' ' ')"

# 2) push gen-normal.ps1 (retry sampai guest session siap — Guest Additions butuh waktu setelah boot)
GMARK="$WIN_DIR\\normal-markers.csv"
log "push gen-normal.ps1 -> $WIN_VM:$WIN_DIR"
ok=0
for try in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if gc copyto "$GEN_PS1" --target-directory "$WIN_DIR\\" >/dev/null 2>&1; then ok=1; break; fi
  log "  guest session belum siap (coba $try/12), tunggu 10s..."
  sleep 10
done
[ "$ok" = 1 ] || { echo "STOP: guestcontrol copyto gagal 12x (Guest Additions belum siap / creds salah?)."; exit 1; }
log "gen-normal.ps1 terkirim."
gc run --quiet --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -- \
   -NoProfile -Command "Remove-Item -LiteralPath '$GMARK' -Force -ErrorAction SilentlyContinue" \
   >/dev/null 2>&1 || log "WARN: gagal hapus marker lama (gen-normal menimpa header di awal)."

# 3) start gen-normal.ps1 (async, fire-and-forget)
log "start gen-normal.ps1 ${DUR}s workers=$WORKERS (async, user $WIN_USER)"
gc start --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -- \
   -NoProfile -ExecutionPolicy Bypass -File "$WIN_DIR\\gen-normal.ps1" -Duration "$DUR" -Workers "$WORKERS" -OutDir "$WIN_DIR" \
   || { echo "STOP: guestcontrol start gen-normal gagal."; exit 1; }

# 4) tunggu marker N01 selesai (DUR + margin)
log "tunggu marker N01 (${DUR}s + margin 120s)"
sleep $((DUR + 120))
WINMARK="$(pwd)/.tmp-win-normal.$$"
trap 'rm -f "$WINMARK"' EXIT
out=$(gc run --quiet --wait-stdout --no-wait-stderr --dos2unix \
      --exe "C:\\Windows\\System32\\cmd.exe" -- /c type "$GMARK" 2>/dev/null)
printf '%s\n' "$out" > "$WINMARK"
if ! grep -q '^N01,' "$WINMARK" 2>/dev/null; then
  echo "STOP: marker N01 tak terbaca dari guest (cek gen-normal.ps1 / Guest Additions)."
  exit 1
fi
log "marker N01 terbaca: $(grep -m1 '^N01,' "$WINMARK" | cut -d',' -f5,6)"

# 5) stop pcap
log "stop pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"

# 6) arsip pcap + marker -> sensor:~/pcap-archive/<TAG>
TAG="normal-windows-$(date -u +%Y%m%d-%H%M%S)"
ARCH="/home/sensor/pcap-archive/$TAG"
log "arsip pcap+marker -> sensor:$ARCH"
sens "mkdir -p '$ARCH'; for i in enp0s8 enp0s9 enp0s10; do mkdir -p '$ARCH/'\$i; mv /var/log/pcap/\$i/*.pcap '$ARCH/'\$i/ 2>/dev/null; done; chown -R sensor:sensor /home/sensor/pcap-archive"
{ echo "scenario,attack_cat,phase,target,start_utc,end_utc"
  grep -v '^scenario,' "$WINMARK" 2>/dev/null
} | tr -d '\r' | sens_plain "cat > '$ARCH/markers.csv'"
N=$(sens_plain "grep -vc '^scenario,' '$ARCH/markers.csv' 2>/dev/null" | tr -d ' \r')
log "markers arsip: $N baris data (harus 1 = N01 win-client)"

log "=== SELESAI. TAG=$TAG ==="
log "Tarik raw ke host: bash infra/pull-raw-archive.sh $TAG"
