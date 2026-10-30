#!/usr/bin/env bash
# capture-session-windows.sh — orkestrasi 1 SESI CAPTURE FASE WINDOWS dari HOST (git-bash).
# win-client NYALA, client-1/2 MATI. Normal dijalankan di win-client via VBoxManage
# guestcontrol (gen-normal.ps1); attack S05/S06/S07 dari attacker via run-1h.sh (SSH, sama
# spt fase Linux). SUMBER LABEL = ~/capture-windows.csv di attacker (window normal win-client
# di-APPEND ke sana). Ekstraksi + verifikasi tetap pakai extract-session.sh + check-overlap.py.
#
# Jalankan di GIT-BASH:
#   UJI  (durasi seragam, mis. 120s): bash infra/capture-session-windows.sh 120 15
#   REAL (DURMAP per-skenario):       bash infra/capture-session-windows.sh
# arg1 = durasi FLAT seragam (kosong = DURMAP); arg2 = gap antar-window (default 120).
#
# PRASYARAT: win-client NYALA (restore golden dulu), client-1/2 MATI, attacker+server+sensor
# NYALA. Guest Additions aktif di win-client (guestcontrol). s05/s06/s07 + run-1h.sh ter-bake
# di golden attacker. ISI SENSOR_PW bila beda.
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
export MSYS_NO_PATHCONV=1   # cegah git-bash ubah argumen ber-'/' (mis. /c, /q) jadi path Windows

# ===== kredensial lab (sintetis, lab-only) =====
SENSOR_PW='sensor'; ROOT_PW='root'; KALI_PW='kali'
SENSOR=192.168.56.20; ATT=10.10.30.10
WIN_VM="win-client"; WIN_USER="Admin_lab"; WIN_PASS='Admin@2024'
WIN_DIR='C:\LabData'                         # folder guest (sudah ada, phase4 §6) utk skrip+marker
# VBoxManage.exe = binary Windows -> butuh path HOST absolut gaya Windows (C:\...), bukan
# path relatif/MSYS. cygpath -w mengonversi. (Jalankan dari ROOT repo.)
GEN_PS1_SRC="$(pwd)/scenarios/normal/gen-normal.ps1"
[ -f "$GEN_PS1_SRC" ] || { echo "STOP: gen-normal.ps1 tak ada di $GEN_PS1_SRC (jalankan dari root repo)."; exit 1; }
GEN_PS1="$(cygpath -w "$GEN_PS1_SRC" 2>/dev/null || echo "$GEN_PS1_SRC")"

FLAT="${1:-}"; GAP="${2:-120}"; NORMAL_DUR=3600
# KALIBRASI dari capture BERSIH 2026-10-13 (overlap=0). Target ~2500 flow/kelas, floor 300, cap 3600.
declare -A DURMAP=(
  [s05-rdp-bruteforce]=1200          # 2.13 fl/s -> ~2560
  [s06-winrm-lateral-movement]=3600  # 0.68 fl/s -> cap (~2450)
  [s07-lsass-dump-pth]=3600          # 0.37 fl/s -> cap (~1330)
)
dur_of(){ [ -n "$FLAT" ] && echo "$FLAT" || echo "${DURMAP[$1]:-1800}"; }
ND=$([ -n "$FLAT" ] && echo "$FLAT" || echo "$NORMAL_DUR")

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
PX="sshpass -p $ROOT_PW ssh $O -W %h:%p root@192.168.56.10"
sens(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "echo '$SENSOR_PW' | sudo -S bash -c '$1'"; }
sens_plain(){ sshpass -p "$SENSOR_PW" ssh $O sensor@$SENSOR "$1"; }
att(){  sshpass -p $KALI_PW ssh $O -o ProxyCommand="$PX" kali@$ATT "$1"; }
# guestcontrol: kredensial DITARUH SETELAH subcommand (sintaks VBox 7). $1=subcommand.
gc(){ local sub="$1"; shift; VBoxManage guestcontrol "$WIN_VM" "$sub" --username "$WIN_USER" --password "$WIN_PASS" "$@"; }
vstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -q 'VMState="running"'; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*"; }
# Kode SCN dari run.sh (mis. "S05"). PENTING: run-1h.sh menulis KODE ini ke capture-windows.csv,
# BUKAN nama folder ("s05-rdp-bruteforce") — validasi marker harus pakai kode.
scn_code(){ sed -nE 's/.*(^|[;[:space:]])SCN="?([^;"]*)"?.*/\2/p' "scenarios/$1/run.sh" 2>/dev/null | head -1; }

SCNS="s05-rdp-bruteforce s06-winrm-lateral-movement s07-lsass-dump-pth"
log "=== CAPTURE SESSION FASE WINDOWS ==="

# 0) pre-check fase: win-client NYALA, client-1/2 MATI
vstate "$WIN_VM" || { echo "STOP: $WIN_VM TIDAK running. Restore golden + startvm dulu."; exit 1; }
for c in client-1 client-2; do
  vstate "$c" && { echo "STOP: $c masih NYALA — fase Windows harus MATI (trafik Linux nyelip). Matikan dulu."; exit 1; }
done
att "pkill -f run-1h.sh 2>/dev/null; true"

# 1) pcap bersih + start (3 segmen, sama spt fase Linux)
log "clean+start pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10; rm -f /var/log/pcap/enp0s8/* /var/log/pcap/enp0s9/* /var/log/pcap/enp0s10/*; systemctl start pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
sleep 3
log "pcap: $(sens_plain "systemctl is-active pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10" | tr '\n' ' ')"
SESS_START=$(ts); SESS_EPOCH=$(date +%s)
log "SESSION_START=$SESS_START"

# 2) reset marker attacker (sumber label gabungan attack+normal-win)
att "rm -f ~/capture-windows.csv; true"

# 3) Normal di win-client via guestcontrol: buang marker basi -> push skrip -> start (async) ->
#    TUNGGU marker benar-benar ada (bukan sleep buta) -> tarik (multi-metode) -> validasi.
GMARK="$WIN_DIR\\normal-markers.csv"          # C:\LabData\normal-markers.csv
log "push gen-normal.ps1 -> $WIN_VM:$WIN_DIR"
# copyto FILE->DIR (--target-directory) stabil; bentuk file->file sempat hang di versi ini.
gc copyto "$GEN_PS1" --target-directory "$WIN_DIR\\" || { echo "STOP: guestcontrol copyto gagal (Guest Additions/creds?)."; exit 1; }

# TEMP DIR HOST: JANGAN pakai `mktemp -d` di sini. PATH skrip ini menaruh /c/msys64/usr/bin di
# depan, jadi 'mktemp' yang terpanggil = binari MSYS64 yang memetakan /tmp -> C:\msys64\tmp,
# sementara redirection '>' dan test bawaan bash (git-bash) memetakan /tmp -> %TEMP%.
# Hasilnya dua namespace berbeda: copyfrom "sukses" menulis C:\msys64\tmp\tmp.X\..., tapi
# `[ -s "$WINMARK" ]` melihat %TEMP%\tmp.X\... -> "marker normal win KOSONG" padahal file ada.
# Solusi: pakai path /c/... (disepakati kedua runtime).
tmpd="$(pwd)/.tmp-win-capture.$$"
mkdir -p "$tmpd" || { echo "STOP: tak bisa membuat folder temp host $tmpd"; exit 1; }
WINMARK="$tmpd/win-normal.csv"; PULLLOG="$tmpd/pull.log"
log "temp host: $tmpd (win: $(cygpath -w "$tmpd" 2>/dev/null))"
trap 'rm -rf "$tmpd"' EXIT

# Tarik isi marker guest -> $WINMARK. Metode UTAMA: stdout dari guest process (cmd /c type).
# Tidak lewat semantik 'copyfrom' yang flaky (file->file sempat hang / hasil 0 byte) dan
# error-nya kelihatan, bukan ditelan. rc=0 hanya bila dapat header CSV.
pull_marker(){
  local out
  out=$(gc run --quiet --wait-stdout --no-wait-stderr --dos2unix \
        --exe "C:\\Windows\\System32\\cmd.exe" -- /c type "$GMARK" 2>"$PULLLOG")
  printf '%s\n' "$out" > "$WINMARK"
  grep -q '^scenario,' "$WINMARK" 2>/dev/null
}

# 3a) Buang marker sesi LALU. Kalau gen-normal gagal jalan, file basi bisa lolos jadi label
#     Normal palsu (timestamp lama -> overlap) -> hapus dulu, jangan cuma andalkan overwrite.
log "hapus marker Normal lama di guest"
gc run --quiet --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -- \
   -NoProfile -Command "Remove-Item -LiteralPath '$GMARK' -Force -ErrorAction SilentlyContinue" \
   >/dev/null 2>&1 || log "WARN: gagal hapus marker lama (gen-normal tetap menimpa header di awal)."

# 3b) start = fire-and-forget (VBox 7 tak punya --wait-exit utk 'start'); sinkronisasi lewat
#     polling marker di 3c/3d. Argumen TIDAK mengulang 'powershell.exe' (bentuk salah: exe
#     dikirim dua kali -> bisa jalan sbg instance bersarang / arg terbuang).
log "start gen-normal.ps1 ${ND}s (async, user $WIN_USER)"
gc start --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -- \
   -NoProfile -ExecutionPolicy Bypass -File "$WIN_DIR\\gen-normal.ps1" -Duration "$ND" -OutDir "$WIN_DIR" \
   || { echo "STOP: guestcontrol start gen-normal gagal."; exit 1; }

# 3c) Tunggu proses BENAR-BENAR hidup: gen-normal menulis header di detik pertama. Ini
#     memisahkan 'start tak jalan' (tak ada file) dari 'marker belum selesai' (header saja).
log "tunggu header marker muncul di guest (bukti proses hidup)"
hdr_dl=$(( $(date +%s) + 180 )); got_hdr=0
while [ "$(date +%s)" -lt "$hdr_dl" ]; do
  pull_marker && { got_hdr=1; break; }
  sleep 10
done
if [ "$got_hdr" -eq 0 ]; then
  echo "STOP: gen-normal tak menulis $GMARK di guest — proses kemungkinan tak jalan."
  echo "  Cek: jalur powershell.exe -File, Guest Additions, kredensial user $WIN_USER."
  head -5 "$PULLLOG" 2>/dev/null
  exit 1
fi

# 3d) Tunggu baris N01 — ditulis di AKHIR loop (gen-normal.ps1 baris terakhir), jadi batas =
#     ND + margin. Ganti 'sleep $((ND+30))' yang buta terhadap start yang telat/gagal.
log "tunggu baris N01 (${ND}s + margin 120s)"
n01_dl=$(( $(date +%s) + ND + 120 )); got_n01=0
while [ "$(date +%s)" -lt "$n01_dl" ]; do
  pull_marker && grep -q '^N01,' "$WINMARK" && { got_n01=1; break; }
  sleep 15
done

# 3e) Fallback transfer: copyfrom dgn OPSI DI DEPAN (sintaks resmi VBox 7:
#     copyfrom [--opsi] <guest-src> <host-dst>), lalu cek isi lagi.
if [ "$got_n01" -eq 0 ]; then
  log "metode stdout belum dapat N01; fallback guestcontrol copyfrom"
  timeout 120 VBoxManage guestcontrol "$WIN_VM" copyfrom --quiet \
    --username "$WIN_USER" --password "$WIN_PASS" \
    "$GMARK" "$(cygpath -w "$WINMARK")" >>"$PULLLOG" 2>&1 || true
  grep -q '^N01,' "$WINMARK" 2>/dev/null && got_n01=1
  # metode ketiga: baca ulang lewat PowerShell (jalur command berbeda dari cmd /c type)
  if [ "$got_n01" -eq 0 ]; then
    log "copyfrom belum berhasil; baca ulang via PowerShell Get-Content"
    gc run --quiet --wait-stdout --no-wait-stderr --dos2unix \
      --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -- \
      -NoProfile -Command "Get-Content -LiteralPath '$GMARK'" > "$WINMARK" 2>>"$PULLLOG" || true
    grep -q '^N01,' "$WINMARK" 2>/dev/null && got_n01=1
  fi
fi

if [ "$got_n01" -eq 0 ]; then
  echo "STOP: marker Normal Windows tak terbaca (guest punya file, host dapat kosong/nihil)."
  echo "  Log transfer terakhir:"; tail -15 "$PULLLOG" 2>/dev/null
  echo "  Probe manual di git-bash:"
  echo "    VBoxManage guestcontrol $WIN_VM run --quiet --username $WIN_USER --password '***' --exe 'C:\\Windows\\System32\\cmd.exe' -- /c dir 'C:\\LabData'"
  echo "    VBoxManage guestcontrol $WIN_VM run --quiet --username $WIN_USER --password '***' --exe 'C:\\Windows\\System32\\cmd.exe' -- /c type '$GMARK'"
  echo "    VBoxManage guestcontrol $WIN_VM copyfrom --username $WIN_USER --password '***' '$GMARK' 'C:\\Windows\\Temp\\probe.csv'"
  exit 1
fi

# 3f) Tolak marker BASI: start_utc harus >= awal sesi (toleransi 10 menit jam lab).
s_utc=$(grep -m1 '^N01,' "$WINMARK" | cut -d',' -f5 | tr -d '\r')
s_ep=$(date -u -d "$s_utc" +%s 2>/dev/null || echo 0)
if [ "${s_ep:-0}" -gt 0 ] && [ "$s_ep" -lt $((SESS_EPOCH - 600)) ]; then
  echo "STOP: marker Normal ber-timestamp LAMA ($s_utc, sesi mulai $SESS_START) — file basi, bukan sesi ini."
  exit 1
fi

grep -v '^scenario,' "$WINMARK" | tr -d '\r' | att "cat >> ~/capture-windows.csv"
log "window normal win -> appended: $(grep -vc '^scenario,' "$WINMARK") baris (start_utc=$s_utc)"
log "gap ${GAP}s"; sleep "$GAP"

# 4) tiap skenario Windows (poll BARIS DATA — fix overlap, sama spt fase Linux)
FAILED=""
for s in $SCNS; do
  base=$(att "cat ~/capture-windows.csv 2>/dev/null | grep -vc '^scenario,'"); base=${base:-0}
  d=$(dur_of "$s"); log ">>> $s mulai (${d}s)"
  att "nohup bash ~/scenarios/run-1h.sh $s $d 5 > ~/run-1h.out 2>&1 & echo started"
  deadline=$(( $(date +%s) + d + 240 )); got=0; k=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 60; k=$((k + 1))
    now=$(att "cat ~/capture-windows.csv 2>/dev/null | grep -vc '^scenario,'"); now=${now:-0}
    [ "$now" -gt "$base" ] && { got=1; break; }
    # run-1h.sh mati seketika kalau folder skenario salah -> deteksi awal, jangan tunggu deadline.
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

# 5) stop pcap
log "stop pcap sensor"
sens "systemctl stop pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10"
log "SESSION_END=$(ts)"

# 6) ARSIPKAN pcap + marker -> sensor:~/pcap-archive/<TAG> (AMAN lintas-hari; clean sesi berikut
#    HANYA sentuh /var/log/pcap/<if>/ = working dir). Marker fase Windows = capture-windows.csv
#    attacker (sudah berisi N01-win + S05/06/07).
TAG="windows-$(date -u +%Y%m%d-%H%M%S)"
ARCH="/home/sensor/pcap-archive/$TAG"
log "arsipkan pcap + marker -> sensor:$ARCH (TAG=$TAG)"
# arsip PCAP dulu (mv semua file rotasi per-iface)
sens "mkdir -p '$ARCH'; for i in enp0s8 enp0s9 enp0s10; do mkdir -p '$ARCH/'\$i; mv /var/log/pcap/\$i/*.pcap '$ARCH/'\$i/ 2>/dev/null; done; chown -R sensor:sensor /home/sensor/pcap-archive"
# marker fase Windows = capture-windows.csv attacker (sudah N01-win + S05/06/07). PIPE LANGSUNG
# ke arsip sensor TANPA file tmp host (redirect /tmp git-bash kadang gagal).
{ echo "scenario,attack_cat,phase,target,start_utc,end_utc"
  att "cat ~/capture-windows.csv" 2>/dev/null | tr -d '\r' \
  | awk -F',' '/^scenario,/{next} NF<3{next}
      { if ($1 ~ /ATTACK_CAT=/){ split($1,a,/; */); scn=a[1]; cat=a[2]; sub(/^ATTACK_CAT=/,"",cat); gsub(/"/,"",cat); ph=a[3]; sub(/^PHASE=/,"",ph); print scn","cat","ph","$(NF-2)","$(NF-1)","$NF } else print }'
} | sens_plain "cat > '$ARCH/markers.csv'"
# Verifikasi: baris data harus = jumlah window = (n skenario + 1 normal win-client).
NEXP=$(echo $SCNS | wc -w | tr -dc '0-9'); NEXP=${NEXP:-0}; NEXP=$((NEXP + 1))
# Baris skenario memakai kode SCN dari run.sh (S05/S06/S07), BUKAN nama folder — ambil sekali, cek lokal.
MK=$(sens_plain "cat '$ARCH/markers.csv' 2>/dev/null")
NACT=0; [ -n "$MK" ] && NACT=$(printf '%s\n' "$MK" | grep -vc '^scenario,')
log "markers arsip: $NACT/$NEXP baris data"
for s in $SCNS; do
  c=$(scn_code "$s"); c=${c:-$s}
  printf '%s\n' "$MK" | grep -q -e "^$c," -e "^$s," \
    || { log "WARN: $s ($c) tak ada di markers arsip"; FAILED="$FAILED $s"; }
done
log "=== SELESAI. ARSIP TAG=$TAG (pcap+markers di sensor:$ARCH). Ekstrak nanti: bash infra/extract-session.sh $TAG ==="
if [ -n "$FAILED" ]; then
  log "SESI TIDAK LENGKAP — window bermasalah:$FAILED"
  exit 1
fi
# CAVEAT:
# - client-1/2 MATI wajib (fase Windows).
# - Arsip di ~/pcap-archive AMAN dari clean sesi Linux besok; pantau disk sensor bila banyak arsip.
# - DURMAP Windows terkalibrasi (lihat atas); utk UJI pakai arg "120 15".
