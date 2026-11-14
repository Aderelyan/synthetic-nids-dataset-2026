#!/usr/bin/env bash
# extract-session.sh — EKSTRAKSI dari ARSIP pcap di sensor (dari HOST git-bash).
# Tiap capture (capture-session*.sh) MENGARSIPKAN pcap+marker ke sensor:~/pcap-archive/<TAG>
# di akhir sesi, jadi pcap TAK HILANG walau sesi lain (yg clean working-dir) jalan belakangan.
# Skrip ini menjalankan pipeline atas SATU arsip -> CSV ke extract-out/<TAG>/.
#
# Pakai:
#   bash infra/extract-session.sh              # tampilkan daftar arsip di sensor
#   bash infra/extract-session.sh <TAG>        # ekstrak arsip <TAG>
#!/usr/bin/env bash
# extract-session.sh — EKSTRAKSI dari ARSIP pcap di sensor (dari HOST git-bash).
# Patch: upload SEMUA pipeline scripts tiap run (bukan cuma extract-build.sh),
# dan simpan log pipeline ke extract-out/<TAG>/pipeline.log untuk audit.
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"; export MSYS_NO_PATHCONV=1
SENSOR_PW=sensor
O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12"
SENS(){ sshpass -p $SENSOR_PW ssh $O sensor@192.168.56.20 "$1"; }

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "Arsip pcap di sensor (~/pcap-archive):"
  SENS "ls -1t ~/pcap-archive 2>/dev/null || echo '(kosong)'"
  echo; echo "Pakai: bash infra/extract-session.sh <TAG>"; exit 0
fi
ARCH="/home/sensor/pcap-archive/$TAG"
SENS "test -d '$ARCH'" || { echo "STOP: arsip '$TAG' tak ada di sensor ($ARCH)."; exit 1; }

OUTDIR_HOST="$(pwd)/extract-out/$TAG"; mkdir -p "$OUTDIR_HOST"

echo "== marker arsip $TAG =="
SENS "cat '$ARCH/markers.csv'"

# ---- upload SEMUA pipeline scripts (anti stale) ----
echo "== upload pipeline scripts ke sensor =="
for f in extract-build.sh build_dataset.py ra_export.sh qa_dataset.py; do
  if [ ! -f "pipeline/$f" ]; then
    echo "  WARN: pipeline/$f tak ada di host, skip"
    continue
  fi
  cat "pipeline/$f" | SENS "cat > ~/pipeline/$f; chmod +x ~/pipeline/$f"
  # verifikasi cepat: checksum host vs sensor
  h_host=$(md5sum "pipeline/$f" | cut -d' ' -f1)
  h_sens=$(SENS "md5sum ~/pipeline/$f" | cut -d' ' -f1 | tr -d '\r')
  if [ "$h_host" = "$h_sens" ]; then
    echo "  OK pipeline/$f (md5 $h_host)"
  else
    echo "  !! MISMATCH pipeline/$f host=$h_host sens=$h_sens -> STOP"
    exit 1
  fi
done

# ---- jalankan pipeline, tee log ke host ----
# FIX Q-P0-E: attacker IP & max timeout bisa beda per arsip -> jangan hardcode di sensor
ATTACKER_IP="${ATTACKER_IP:-10.10.30.10}"
MAX_TIMEOUT="${MAX_TIMEOUT:-7200}"
echo "== attacker-ip: $ATTACKER_IP, max-timeout: ${MAX_TIMEOUT}s =="

echo "== jalankan pipeline atas arsip (bisa beberapa menit) =="
LOG_HOST="$OUTDIR_HOST/pipeline.log"
SENS "ATTACKER_IP='$ATTACKER_IP' MAX_TIMEOUT='$MAX_TIMEOUT' \
      bash ~/pipeline/extract-build.sh '$ARCH/markers.csv' ~/extract-$TAG '$ARCH' 2>&1" \
  | tee "$LOG_HOST"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
    # FIX Q-P0-F: jangan lanjut pull CSV kalau pipeline remote gagal
    echo "FATAL: pipeline remote exit $status (lihat $LOG_HOST) — berhenti."
    exit 1
fi
echo "== log tersimpan di $LOG_HOST =="

# ---- tarik CSV + markers ke host ----
pull(){ # $1 = path ABSOLUT di sensor, $2 = path lokal
  local nr nl
  if ! SENS "cat '$1'" > "$2.tmp" 2>/dev/null || [ ! -s "$2.tmp" ]; then
    echo "  GAGAL tarik $1 (tutup program yg buka $2?)."; rm -f "$2.tmp"; return 1; fi
  nr=$(SENS "wc -l < '$1'" | tr -d ' \r'); nl=$(wc -l < "$2.tmp" | tr -d ' \r')
  [ "$nr" = "$nl" ] || { echo "  !! MISMATCH baris sensor=$nr host=$nl -> ulangi."; rm -f "$2.tmp"; return 1; }
  mv -f "$2.tmp" "$2" 2>/dev/null || { echo "  !! $2 TERKUNCI (OneDrive/editor). data di $2.tmp"; return 1; }
  echo "  OK $2 ($nl baris)"
}
ok=1
pull "$ARCH/markers.csv"                         "$OUTDIR_HOST/markers.csv"    || ok=0
pull "/home/sensor/extract-$TAG/unsw.csv"        "$OUTDIR_HOST/unsw.csv"       || ok=0
pull "/home/sensor/extract-$TAG/unsw_multi.csv"  "$OUTDIR_HOST/unsw_multi.csv" || ok=0
if [ "$ok" = 1 ]; then
    echo "SELESAI -> $OUTDIR_HOST/"
    # FIX Q-P2-D: jalankan check-overlap.py hanya kalau file-nya ada
    if [ -f "infra/check-overlap.py" ]; then
        echo "== verifikasi overlap =="
        python3 infra/check-overlap.py "extract-out/$TAG" || \
            echo "  WARN: check-overlap.py gagal (non-fatal)"
    else
        echo "  (infra/check-overlap.py tidak ada, skip verifikasi)"
    fi
else
    echo "SELESAI SEBAGIAN — perbaiki yg gagal lalu ulang: bash infra/extract-session.sh $TAG"
fi