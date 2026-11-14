#!/usr/bin/env bash
# extract-build.sh — jalan DI sensor. pcap /var/log/pcap/<if> -> zeek + argus offline
# -> ra_export (Tahap A) -> build_dataset (Tahap B) -> CSV final (single + multi-view).
# Progress tiap 10 dtk + timeout per tool (anti-hang). Segmen yang argus-nya korup/
# ter-timeout dibuang supaya tak merusak pipeline.
# Usage: extract-build.sh <markers.csv> [outdir] [pcap_dir]
#   pcap_dir: sumber pcap. Default /var/log/pcap (working dir, pola <if>/*.pcap).
#   Bila arsip (pola FLAT <if>.pcap, mis. ~/pcap-archive/<tag>), diterima juga.
set -uo pipefail
MARK="${1:?markers.csv}"; OUT="${2:-$HOME/extract-$(date +%Y%m%d-%H%M)}"
PCAP="${3:-/var/log/pcap}"
ZEEK=/opt/zeek/bin/zeek
ARGUS="$(command -v argus || echo /usr/sbin/argus)"
RA="$(command -v ra || echo /usr/bin/ra)"
MERGECAP="$(command -v mergecap || true)"
MAX_TIMEOUT="${MAX_TIMEOUT:-7200}"
ATTACKER_IP="${ATTACKER_IP:-10.10.30.10}"

shopt -s nullglob
rm -rf "$OUT"; mkdir -p "$OUT"
now(){ date -u +%H:%M:%S; }
log(){ echo "[$(now)] $*"; }

# ---------- preflight ----------
[ -x "$ZEEK" ]  || { log "FATAL: zeek tak ada di $ZEEK";  exit 1; }
[ -x "$ARGUS" ] || { log "FATAL: argus tak ada di $ARGUS"; exit 1; }
[ -x "$RA" ]    || { log "FATAL: ra tak ada di $RA";       exit 1; }
[ -f "$MARK" ]  || { log "FATAL: markers.csv tak ada: $MARK"; exit 1; }
log "zeek       : $ZEEK"
log "argus      : $ARGUS"
log "ra         : $RA"
log "mergecap   : ${MERGECAP:-<not found, will use manual header-strip>}"
log "markers    : $MARK"
log "pcap       : $PCAP"
log "outdir     : $OUT"
log "attacker-ip: ${ATTACKER_IP:-<none, window-only labeling>}"
log "max-timeout: ${MAX_TIMEOUT}s"

# ---------- helpers ----------

# is_classic_pcap <file> : return 0 jika pcap klasik (magic 0xa1b2c3d4 dkk).
# Return 1 jika pcapng atau format lain (fallback manual tak boleh dipakai).
is_classic_pcap(){
  local magic
  magic=$(od -A n -t x1 -N 4 "$1" 2>/dev/null | tr -d ' \n')
  case "$magic" in
    d4c3b2a1|a1b2c3d4|4d3cb2a1|a1b23c4d) return 0 ;;
    *) return 1 ;;
  esac
}

# merge_iface <iface> <dest.pcap> : kumpulkan SEMUA pcap iface (unit tcpdump -G 3600
# merotasi per jam -> banyak file) lalu GABUNG jadi 1 pcap valid.
#   - Prefer mergecap: validasi linktype + sort timestamp otomatis.
#   - Fallback manual (strip header 24B): hanya jika SEMUA file pcap klasik &
#     linktype sama (divalidasi magic byte). Aman utk arsip dari tcpdump yg sama.
merge_iface(){ local i="$1" dest="$2"; local -a f=()
  if [ -f "$PCAP/$i.pcap" ]; then f=("$PCAP/$i.pcap")
  else f=( "$PCAP/$i/"*.pcap ); [ ${#f[@]} -eq 0 ] && f=( "$PCAP/$i"*.pcap ); fi
  [ ${#f[@]} -eq 0 ] && return 1
  IFS=$'\n' f=($(printf '%s\n' "${f[@]}" | sort -V)); unset IFS

  if [ -n "$MERGECAP" ]; then
    if "$MERGECAP" -w "$dest" "${f[@]}" 2>"$OUT/.mergecap-$i.err"; then
      echo "${#f[@]}"; return 0
    fi
    log "WARN: mergecap gagal utk $i: $(head -1 "$OUT/.mergecap-$i.err" 2>/dev/null)"
    log "      -> fallback manual header-strip"
  fi

  # Fallback: validasi setiap file adalah pcap klasik
  local x
  for x in "${f[@]}"; do
    if ! is_classic_pcap "$x"; then
      log "ERROR: $x bukan pcap klasik (kemungkinan pcapng) -> tak bisa merge manual"
      return 1
    fi
  done
  cp "${f[0]}" "$dest" || return 1
  for x in "${f[@]:1}"; do tail -c +25 "$x" >> "$dest" || return 1; done
  echo "${#f[@]}"
}

# runp <label> <watch-path> -- <cmd...> : jalan di bg, progress tiap 10s,
# watchdog kill jika > MAX_TIMEOUT (0 = tak terbatas).
runp(){ local label="$1" watch="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  "$@" & local pid=$! t=0 killed=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 10; t=$((t+10))
    if [ "$MAX_TIMEOUT" -gt 0 ] && [ "$t" -ge "$MAX_TIMEOUT" ]; then
      log "   WATCHDOG: $label hang > ${MAX_TIMEOUT}s -> kill -TERM"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 3
      kill -KILL "$pid" 2>/dev/null || true
      killed=1
      break
    fi
    echo "   [$(now)] $label +${t}s out=$(du -sh "$watch" 2>/dev/null | cut -f1)"
  done
  wait "$pid" 2>/dev/null
  local rc=$?
  [ "$killed" -eq 1 ] && return 124   # 124 = timeout, konvensi coreutils
  return $rc
}

# report_zeek_logs <iface> : cetak jumlah baris per log penting
# (data rows, '#' di-skip). Kalau http.log/ftp.log kosong -> bug #2 (lihat analisa).
report_zeek_logs(){ local i="$1" l f n
  for l in conn.log http.log ftp.log dns.log ssl.log files.log; do
    f="$OUT/zeek-$i/$l"
    if [ -f "$f" ]; then
      n=$(awk '!/^#/ && NF>0' "$f" | wc -l)
      log "   $i: $l = $n rows"
    fi
  done
  if [ -s "$OUT/zeek-$i/.stderr" ]; then
    log "   $i: zeek stderr ($(wc -l < "$OUT/zeek-$i/.stderr") lines) -> $OUT/zeek-$i/.stderr"
  fi
}

# ---------- main loop ----------
SEG_OK=()
for i in enp0s8 enp0s9 enp0s10; do
  if ! n=$(merge_iface "$i" "$OUT/$i.pcap"); then
    log "WARN: tak ada pcap valid utk $i di $PCAP -> segmen dilewati"
    continue
  fi
  log "=== $i ($n file rotasi -> merge; input $(du -sh "$OUT/$i.pcap" | cut -f1)) ==="
  mkdir -p "$OUT/zeek-$i" "$OUT/argus-$i"

  # Zeek: -C = ignore checksum, 'local' = site/local.zeek (muat protokol standar)
  # --- Zeek (fail-fast) ---
  if ! runp "$i:zeek"  "$OUT/zeek-$i" \
       -- bash -c "cd '$OUT/zeek-$i' && '$ZEEK' -C -r '$OUT/$i.pcap' local 2>'$OUT/zeek-$i/.stderr'"; then
    log "ERROR: $i zeek gagal/timeout -> segmen dilewati"
    continue
  fi

  report_zeek_logs "$i"

  # FIX Q-P1-M: conn.log kosong = fatal (service lookup akan hancur)
  conn_rows=$(awk '!/^#/ && NF>0' "$OUT/zeek-$i/conn.log" 2>/dev/null | wc -l)
  if [ "$conn_rows" -lt 1 ]; then
    log "ERROR: $i conn.log kosong -> segmen dilewati"
    continue
  fi
  log "   $i: conn.log = $conn_rows rows OK"

  # --- Argus (fail-fast) ---
  if ! runp "$i:argus" "$OUT/argus-$i/$i.argus" \
       -- "$ARGUS" -r "$OUT/$i.pcap" -w "$OUT/argus-$i/$i.argus" -P 0; then
    log "ERROR: $i argus gagal/timeout -> segmen dilewati"
    continue
  fi

  # FIX Q-P1-N: cek jumlah baris (bukan head -1 | grep -q, yang bisa false-positive
  # jika ra mencetak error message ke stdout)
  n_argus=$(timeout 20 "$RA" -r "$OUT/argus-$i/$i.argus" -c , -s stime 2>/dev/null | wc -l)
  if [ "$n_argus" -lt 2 ]; then
    log "$i: argus tak menghasilkan flow valid ($n_argus baris) -> dilewati"
    rm -f "$OUT/argus-$i/$i.argus"
    continue
  fi
  log "   $i: argus = $((n_argus-1)) flows OK"
  SEG_OK+=("$i")
done

if [ ${#SEG_OK[@]} -eq 0 ]; then
  log "FATAL: tak ada segmen yg berhasil diproses"
  exit 1
fi
log "segmen berhasil: ${SEG_OK[*]}"

# ---------- Tahap A ----------
log "=== Tahap A: ra_export ==="
if ! bash ~/pipeline/ra_export.sh "$OUT" "$OUT/argus_csv" "$RA"; then
  log "FATAL: ra_export gagal"
  exit 1
fi

# ---------- Tahap B (single-view, dataset utama) ----------
log "=== Tahap B: build_dataset single-view ==="
if ! PYTHONUNBUFFERED=1 python3 ~/pipeline/build_dataset.py \
    --argus-dir "$OUT/argus_csv" \
    --zeek-root "$OUT" \
    --markers "$MARK" \
    --attacker-ip "$ATTACKER_IP" \
    --out "$OUT/unsw.csv"; then
  log "FATAL: build_dataset single-view gagal"
  exit 1
fi

# ---------- Tahap B (multi-view, varian) ----------
log "=== Tahap B: build_dataset multi-view ==="
if ! PYTHONUNBUFFERED=1 python3 ~/pipeline/build_dataset.py \
    --argus-dir "$OUT/argus_csv" \
    --zeek-root "$OUT" \
    --markers "$MARK" \
    --attacker-ip "$ATTACKER_IP" \
    --out "$OUT/unsw_multi.csv" \
    --dedup off --add-vantage; then
  log "WARN: build_dataset multi-view gagal (single-view tetap ada)"
fi


# ---------- sanity check output ----------
for f in "$OUT/unsw.csv" "$OUT/unsw_multi.csv"; do
  if [ -f "$f" ]; then
    log "OUT: $f ($(( $(wc -l < "$f") - 1 )) data rows, $(du -h "$f" | cut -f1))"
    # FIX Q-P1-F: QC post-build
    if [ -f ~/pipeline/qa_dataset.py ]; then
      log "== QA $f =="
      PYTHONUNBUFFERED=1 python3 ~/pipeline/qa_dataset.py "$f" || \
        log "  WARN: QA mengembalikan exit $? (cek output di atas)"
    fi
  fi
done

log "=== SELESAI OUTDIR=$OUT ==="