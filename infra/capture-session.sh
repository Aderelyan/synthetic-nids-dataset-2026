#!/usr/bin/env bash
# capture-session.sh — orkestrasi 1 SESI CAPTURE FASE LINUX end-to-end, dari HOST.
# Alur: bersih+start pcap (sensor) -> Normal (client-1/2) -> tiap skenario (durasi PER-SKENARIO
#       via DURMAP, run-1h.sh di attacker, + start iodined srv-file utk S09) -> stop pcap.
#
# Jalankan di GIT-BASH:
#   REAL (durasi per-skenario DURMAP):  bash infra/capture-session.sh
#   UJI  (durasi seragam, mis. 120s):   bash infra/capture-session.sh 120 15
# arg1 = durasi FLAT seragam (kosong = pakai DURMAP); arg2 = gap antar-window (default 300).
#
# PRASYARAT: sshpass (msys), VBoxManage di PATH, helper sudah ter-bake (run-1h.sh di
# attacker, run-linux.sh di client-1/2), semua VM fase Linux SUDAH NYALA.
# ISI SENSOR_PW di bawah (password user 'sensor'); kredensial lab lain sudah default.
#
# CATATAN: skrip ini BLOCKING ~10 jam. Jaga laptop tetap nyala & terminal terbuka.
#          win-client HARUS mati (ini fase Linux). Sensor TIDAK di-restore (pasif).
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"

# ===== kredensial lab (sintetis, lab-only) =====
SENSOR_PW='sensor'
ROOT_PW='root'; KALI_PW='kali'; LAB_PW='labadmin'
SENSOR=192.168.56.20; ATT=10.10.30.10; C1=10.10.20.20; C2=10.10.20.21; SRVFILE=10.10.10.11
# arg1 = FLAT (durasi seragam semua window; utk uji). Kosong = pakai PETA DURASI per-skenario (real).
FLAT="${1:-}"; GAP="${2:-300}"
NORMAL_DUR=3600
# PETA DURASI per-skenario (detik) — disesuaikan dgn rate flow tiap attack supaya volume
# antar-kelas lebih SEBANDING (bukan sama persis). Padat flow -> pendek; sedikit flow -> panjang.
# Nilai AWAL = estimasi; KALIBRASI presisi dari capture bersih (lihat phase8 roadmap).
# KALIBRASI dari capture BERSIH 2026-10-12 (overlap=0). Target ~2500 flow/kelas,
# floor 300s, cap 3600s. Rate single-view (fl/s) di komentar. Recon & S10 padat -> floor.
declare -A DURMAP=(
  [s01-port-scanning]=300         # 120.6 fl/s -> floor (tetap dominan ~36k, wajar; TtV#9)
  [s02-bruteforce-ssh-ftp]=3600   # 0.71 fl/s -> cap  (~2560)
  [s03-password-spraying]=3600    # 0.27 fl/s -> cap  (~970, inheren jarang)
  [s04-web-injection-sqli]=3600   # 0.69 fl/s -> cap  (~2480)
  [s08-ssh-lateral-movement]=1300 # 1.92 fl/s         (~2500)
  [s09-dns-tunneling-doh]=2850    # 0.88 fl/s         (~2510)
  [s10-ransomware-smb-sim]=300    # 8.15 fl/s -> floor (~2445)
  [s11-dos-ddos-hping3]=2800      # 0.90 fl/s         (~2520)
  [s12-data-exfiltration]=3600    # 0.55 fl/s -> cap  (~1980)
)
dur_of(){ [ -n "$FLAT" ] && echo "$FLAT" || echo "${DURMAP[$1]:-1800}"; }
ND=$([ -n "$FLAT" ] && echo "$FLAT" || echo "$NORMAL_DUR")

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
PX="sshpass -p $ROOT_PW ssh $O -W %h:%p root@192.168.56.10"

# sensor hostonly; jalankan $1 SEBAGAI ROOT lewat SATU 'sudo -S bash -c' (pw dari stdin,
# tanpa TTY). $1 TANPA prefix sudo. sens_plain = perintah non-root (mis. systemctl is-active).
sens(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "echo '$SENSOR_PW' | sudo -S bash -c '$1'"; }
sens_plain(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "$1"; }
att(){  sshpass -p $KALI_PW ssh $O -o ProxyCommand="$PX" kali@$ATT "$1"; }
cli(){  sshpass -p $LAB_PW ssh $O -o ProxyCommand="$PX" labadmin@"$1" "$2"; }
srv(){  sshpass -p $LAB_PW ssh $O -o ProxyCommand="$PX" labadmin@$SRVFILE "echo '$LAB_PW' | sudo -S bash -c '$1'"; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*"; }
# Kode SCN dari run.sh (mis. "S05"). PENTING: run-1h.sh menulis KODE ini ke capture-windows.csv,
# BUKAN nama folder ("s05-rdp-bruteforce") — validasi marker harus pakai kode.
scn_code(){ sed -nE 's/.*(^|[;[:space:]])SCN="?([^;"]*)"?.*/\2/p' "scenarios/$1/run.sh" 2>/dev/null | head -1; }

SCNS="s01-port-scanning s02-bruteforce-ssh-ftp s03-password-spraying s04-web-injection-sqli s08-ssh-lateral-movement s09-dns-tunneling-doh s10-ransomware-smb-sim s11-dos-ddos-hping3 s12-data-exfiltration"
# SPLIT 2-HARI: override subset skenario lewat env SCN_LIST; lewati Normal lewat env SKIP_NORMAL=1.
# PENTING (git-bash/MSYS): bentuk prefix `VAR=val bash script` TIDAK diwarisi ke skrip di
# git-bash — WAJIB `export` di baris terpisah dulu (diverifikasi 2026-10-14). Verifikasi baris
# pertama log harus `SCNS=[...] | Normal=lewati`:
#   Hari-1:  export SCN_LIST="s01-port-scanning s02-bruteforce-ssh-ftp ..."; bash infra/capture-session.sh
#   Hari-2:  export SKIP_NORMAL=1
#            export SCN_LIST="s03-password-spraying s04-web-injection-sqli s09-dns-tunneling-doh s11-dos-ddos-hping3 s12-data-exfiltration"
#            bash infra/capture-session.sh
#   (selesai -> `unset SKIP_NORMAL SCN_LIST` biar tak kebawa run berikutnya)
SCNS="${SCN_LIST:-$SCNS}"
DO_NORMAL=1; [ "${SKIP_NORMAL:-0}" = 1 ] && DO_NORMAL=0
[ "$SENSOR_PW" = 'ISI_PASSWORD_SENSOR' ] && { echo "EDIT dulu SENSOR_PW di skrip."; exit 1; }

# PRE-FLIGHT nama skenario (host-side). run-1h.sh keluar SEGERA ("ERROR: ... tak ada",
# exit 1) bila folder tak ada, dan TIDAK menulis baris marker -> window hilang tanpa jejak.
# Kasus nyata 2026-10-22: SCN_LIST berisi "s10-ransomware-sim" (folder sebenarnya
# "s10-ransomware-smb-sim") -> poll menunggu d+240s lalu lanjut seolah sukses.
[ -d scenarios ] || { echo "STOP: jalankan dari ROOT repo (folder scenarios/ tak ada di $(pwd))."; exit 1; }
BAD=""
for s in $SCNS; do [ -f "scenarios/$s/run.sh" ] || BAD="$BAD $s"; done
if [ -n "$BAD" ]; then
  echo "STOP: nama skenario tak dikenal:$BAD"
  echo "  Yang valid: $(ls -1 scenarios | grep -E '^s[0-9]+-' | tr '\n' ' ')"
  exit 1
fi

log "=== FASE LINUX: SCNS=[$SCNS] | Normal=$([ "$DO_NORMAL" = 1 ] && echo ya || echo lewati) ==="

log "=== CAPTURE SESSION FASE LINUX ==="

# 0) bersihkan sisa proses campaign lama
cli $C1 "pkill -f run-linux.sh 2>/dev/null; true"; cli $C2 "pkill -f run-linux.sh 2>/dev/null; true"
att "pkill -f run-1h.sh 2>/dev/null; true"

# 1) pcap bersih + start
log "clean+start pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10; rm -f /var/log/pcap/enp0s8/* /var/log/pcap/enp0s9/* /var/log/pcap/enp0s10/*; systemctl start pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
sleep 3
A=$(sens_plain "systemctl is-active pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10" | tr '\n' ' ')
log "pcap status: $A"
log "SESSION_START=$(ts)"

# 2) Normal 1 jam (paralel) + reset marker lama di client — dilewati bila SKIP_NORMAL=1
if [ "$DO_NORMAL" = 1 ]; then
  cli $C1 "rm -f ~/normal-markers.csv; nohup bash ~/run-linux.sh --duration $ND > ~/normal.out 2>&1 & echo c1 pid \$!"
  cli $C2 "rm -f ~/normal-markers.csv; nohup bash ~/run-linux.sh --duration $ND > ~/normal.out 2>&1 & echo c2 pid \$!"
  log "Normal start ${ND}s; tunggu selesai"
  sleep $((ND + 30))
  log "Normal selesai; gap ${GAP}s"; sleep "$GAP"
else
  log "SKIP_NORMAL=1 -> Normal dilewati (pakai Normal dari sesi hari-1)"
fi

# 3) reset capture-windows.csv lama di attacker, lalu tiap skenario 1 jam (poll selesai)
att "rm -f ~/capture-windows.csv; true"
FAILED=""
for s in $SCNS; do
  if [ "$s" = "s09-dns-tunneling-doh" ]; then
    log "S09: start iodined di srv-file"
    srv "systemctl unmask iodined 2>/dev/null; systemctl start iodined 2>/dev/null; true" || true
  fi
  # hitung BARIS DATA (bukan header) — run-1h tulis header saat mulai; poll harus tunggu
  # baris DATA (ditulis di AKHIR), supaya tak start skenario berikut terlalu cepat (overlap).
  base=$(att "cat ~/capture-windows.csv 2>/dev/null | grep -vc '^scenario,'"); base=${base:-0}
  d=$(dur_of "$s")
  log ">>> $s mulai (${d}s)"
  att "nohup bash ~/scenarios/run-1h.sh $s $d 5 > ~/run-1h.out 2>&1 & echo started"
  deadline=$(( $(date +%s) + d + 240 )); got=0; k=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 60; k=$((k + 1))
    now=$(att "cat ~/capture-windows.csv 2>/dev/null | grep -vc '^scenario,'"); now=${now:-0}
    [ "$now" -gt "$base" ] && { got=1; break; }
    # run-1h.sh mati seketika kalau nama folder salah -> deteksi awal (maks 2 poll), jangan
    # tunggu deadline yang bisa sejam.
    if [ "$k" -le 2 ] && att "grep -q 'tak ada' ~/run-1h.out 2>/dev/null"; then
      log "WARN: $s gagal start di attacker:"; att "tail -3 ~/run-1h.out"
      break
    fi
  done
  if [ "$got" -eq 1 ]; then
    log "<<< $s selesai (window tercatat); gap ${GAP}s"
  else
    log "WARN: <<< $s TIDAK menulis window (baris marker tetap $base); gap ${GAP}s"
    FAILED="$FAILED $s"
  fi
  sleep "$GAP"
done

# 4) stop pcap
log "stop pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
log "SESSION_END=$(ts)"

# 5) ARSIPKAN pcap + marker ke sensor:~/pcap-archive/<TAG> -> AMAN lintas-hari.
#    (clean di AWAL sesi berikutnya HANYA sentuh /var/log/pcap/<if>/ = working dir; arsip tak tersentuh.)
TAG="linux-$(date -u +%Y%m%d-%H%M%S)"
ARCH="/home/sensor/pcap-archive/$TAG"
log "arsipkan pcap + marker -> sensor:$ARCH (TAG=$TAG)"
# arsip PCAP dulu (mv semua file rotasi per-iface)
sens "mkdir -p '$ARCH'; for i in enp0s8 enp0s9 enp0s10; do mkdir -p '$ARCH/'\$i; mv /var/log/pcap/\$i/*.pcap '$ARCH/'\$i/ 2>/dev/null; done; chown -R sensor:sensor /home/sensor/pcap-archive"
# kumpulkan+NORMALISASI marker (attacker capture-windows + client normal) lalu PIPE LANGSUNG ke
# arsip di sensor — TANPA file tmp host (redirect /tmp git-bash kadang gagal "No such file or dir").
{ echo "scenario,attack_cat,phase,target,start_utc,end_utc"
  { att "cat ~/capture-windows.csv" 2>/dev/null || true
    if [ "$DO_NORMAL" = 1 ]; then
      cli $C1 "cat ~/normal-markers.csv" 2>/dev/null || true
      cli $C2 "cat ~/normal-markers.csv" 2>/dev/null || true
    fi
  } | tr -d '\r' | awk -F',' '/^scenario,/{next} NF<3{next}
      { if ($1 ~ /ATTACK_CAT=/){ split($1,a,/; */); scn=a[1]; cat=a[2]; sub(/^ATTACK_CAT=/,"",cat); gsub(/"/,"",cat); ph=a[3]; sub(/^PHASE=/,"",ph); print scn","cat","ph","$(NF-2)","$(NF-1)","$NF } else print }'
} | sens_plain "cat > '$ARCH/markers.csv'"
# Verifikasi: jumlah baris data harus = jumlah window = n skenario + 2 (normal c1+c2).
NEXP=$(echo $SCNS | wc -w | tr -dc '0-9'); NEXP=${NEXP:-0}
[ "$DO_NORMAL" = 1 ] && NEXP=$((NEXP + 2))
# Ambil marker SEKALI (1x SSH) lalu cek lokal. Baris skenario memakai kode SCN (S05, ...),
# bukan nama folder — mencocokkan nama folder = false-negative.
MK=$(sens_plain "cat '$ARCH/markers.csv' 2>/dev/null")
NACT=0; [ -n "$MK" ] && NACT=$(printf '%s\n' "$MK" | grep -vc '^scenario,')
log "markers arsip: $NACT/$NEXP baris data"
for s in $SCNS; do
  c=$(scn_code "$s"); c=${c:-$s}
  printf '%s\n' "$MK" | grep -q -e "^$c," -e "^$s," \
    || { log "WARN: $s ($c) tak ada di markers arsip"; FAILED="$FAILED $s"; }
done
[ "$NACT" -lt "$NEXP" ] && FAILED="$FAILED [total<$NEXP]"
log "=== SELESAI. ARSIP TAG=$TAG (pcap+markers di sensor:$ARCH). Ekstrak nanti: bash infra/extract-session.sh $TAG ==="
if [ -n "$FAILED" ]; then
  log "SESI TIDAK LENGKAP — window bermasalah:$FAILED"
  log "  Arsip tetap disimpan, tapi sesi ini JANGAN dipakai utk training sebelum window itu diulang."
  exit 1
fi
# CAVEAT: pcap TETAP di sensor (jangan restore sensor). Working dir /var/log/pcap akan di-clean
# oleh sesi capture berikutnya — arsip di ~/pcap-archive AMAN. Pantau disk sensor bila banyak arsip.
