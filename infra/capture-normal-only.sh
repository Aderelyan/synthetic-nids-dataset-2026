#!/usr/bin/env bash
# capture-normal-only.sh — capture HANYA trafik Normal (TANPA skenario attack), fase LINUX.
# Alur: deploy run-linux.sh terbaru ke client -> clean+start pcap sensor -> run-linux.sh
# (paralel) di client-1/2 selama DUR -> stop pcap -> arsip pcap+marker -> sensor:~/pcap-archive/<TAG>.
#
# Pakai (di git-bash, dari ROOT repo):
#   bash infra/capture-normal-only.sh [DUR] [WORKERS]
#   default DUR=3600 (1 jam), WORKERS=4 (diteruskan ke run-linux.sh)
#
# Prasyarat: VM fase Linux NYALA (client-1, client-2, srv-web, srv-file, sensor), win-client MATI.
# Hasil RAW di sensor. Tarik ke host: bash infra/pull-raw-archive.sh <TAG>
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
SENSOR_PW='sensor'; ROOT_PW='root'; LAB_PW='labadmin'
SENSOR=192.168.56.20; C1=10.10.20.20; C2=10.10.20.21
DUR="${1:-3600}"; WORKERS="${2:-4}"

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
PX="sshpass -p $ROOT_PW ssh $O -W %h:%p root@192.168.56.10"
sens(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "echo '$SENSOR_PW' | sudo -S bash -c '$1'"; }
sens_plain(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "$1"; }
cli(){  sshpass -p $LAB_PW ssh $O -o ProxyCommand="$PX" labadmin@"$1" "$2"; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*"; }

[ -f scenarios/normal/run-linux.sh ] || { echo "STOP: jalankan dari ROOT repo (scenarios/normal/run-linux.sh tak ada)."; exit 1; }
log "=== CAPTURE NORMAL-ONLY (Linux) DUR=${DUR}s WORKERS=$WORKERS ==="

# pre-flight: VM fase Linux harus nyala (router + sensor + srv + client), win-client MATI
vstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -q 'VMState="running"'; }
MISSING=""
for v in router-opnsense sensor srv-web srv-file client-1 client-2; do
  vstate "$v" || MISSING="$MISSING $v"
done
if [ -n "$MISSING" ]; then
  echo "STOP: VM belum nyala:$MISSING"
  echo "  Cek      : VBoxManage list runningvms"
  echo "  Nyalakan : VBoxManage startvm <vm> --type headless   (router tunggu ~40s dulu)"
  exit 1
fi
vstate win-client && { echo "STOP: win-client NYALA — fase Linux harus MATI (matikan dulu)."; exit 1; }

# 0) deploy run-linux.sh TERBARU (supaya flag --workers aktif) ke client-1/2
log "deploy run-linux.sh -> client-1 & client-2"
cat scenarios/normal/run-linux.sh | cli $C1 "cat > ~/run-linux.sh; chmod +x ~/run-linux.sh" || { echo "STOP: deploy ke client-1 gagal."; exit 1; }
cat scenarios/normal/run-linux.sh | cli $C2 "cat > ~/run-linux.sh; chmod +x ~/run-linux.sh" || { echo "STOP: deploy ke client-2 gagal."; exit 1; }

# 1) pcap bersih + start (3 segmen)
log "clean+start pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10; rm -f /var/log/pcap/enp0s8/* /var/log/pcap/enp0s9/* /var/log/pcap/enp0s10/*; systemctl start pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
sleep 3
log "pcap: $(sens_plain "systemctl is-active pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10" | tr '\n' ' ')"

# 2) start generator normal (paralel) di kedua client
log "start run-linux.sh --duration $DUR --workers $WORKERS di client-1 & client-2"
cli $C1 "rm -f ~/normal-markers.csv; nohup bash ~/run-linux.sh --duration $DUR --workers $WORKERS > ~/normal.out 2>&1 & echo c1 pid \$!"
cli $C2 "rm -f ~/normal-markers.csv; nohup bash ~/run-linux.sh --duration $DUR --workers $WORKERS > ~/normal.out 2>&1 & echo c2 pid \$!"
log "tunggu ${DUR}s + 30s (blocking)"
sleep $((DUR + 30))

# 3) stop pcap
log "stop pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"

# 4) arsip pcap + marker -> sensor:~/pcap-archive/<TAG>
TAG="normal-linux-$(date -u +%Y%m%d-%H%M%S)"
ARCH="/home/sensor/pcap-archive/$TAG"
log "arsip pcap+marker -> sensor:$ARCH"
sens "mkdir -p '$ARCH'; for i in enp0s8 enp0s9 enp0s10; do mkdir -p '$ARCH/'\$i; mv /var/log/pcap/\$i/*.pcap '$ARCH/'\$i/ 2>/dev/null; done; chown -R sensor:sensor /home/sensor/pcap-archive"
{ echo "scenario,attack_cat,phase,target,start_utc,end_utc"
  { cli $C1 "cat ~/normal-markers.csv 2>/dev/null" || true
    cli $C2 "cat ~/normal-markers.csv 2>/dev/null" || true
  } | tr -d '\r' | awk -F',' '/^scenario,/{next} NF<3{next} {print}'
} | sens_plain "cat > '$ARCH/markers.csv'"
N=$(sens_plain "grep -vc '^scenario,' '$ARCH/markers.csv' 2>/dev/null" | tr -d ' \r')
log "markers arsip: $N baris data (harus 2 = client-1 + client-2)"

log "=== SELESAI. TAG=$TAG ==="
log "Tarik raw ke host: bash infra/pull-raw-archive.sh $TAG"
