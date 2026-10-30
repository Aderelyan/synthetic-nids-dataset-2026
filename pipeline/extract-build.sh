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
shopt -s nullglob
rm -rf "$OUT"; mkdir -p "$OUT"     # bersih tiap run -> tak ada sisa run sebelumnya
now(){ date -u +%H:%M:%S; }

# merge_iface <iface> <dest.pcap> : kumpulkan SEMUA pcap iface (unit tcpdump -G 3600 merotasi
# per jam -> banyak file) lalu GABUNG jadi 1 pcap valid. Sumber bisa: arsip flat <if>.pcap,
# arsip/working subdir <if>/*.pcap, atau flat <if>*.pcap. Merge pakai trik potong header 24B
# (tail -c +25) utk file ke-2 dst — valid utk pcap klasik (linktype sama, 1 iface). Tanpa mergecap.
merge_iface(){ local i="$1" dest="$2"; local -a f=()
  if [ -f "$PCAP/$i.pcap" ]; then f=("$PCAP/$i.pcap")
  else f=( "$PCAP/$i/"*.pcap ); [ ${#f[@]} -eq 0 ] && f=( "$PCAP/$i"*.pcap ); fi
  [ ${#f[@]} -eq 0 ] && return 1
  IFS=$'\n' f=($(printf '%s\n' "${f[@]}" | sort)); unset IFS   # kronologis (nama = timestamp)
  cp "${f[0]}" "$dest"
  local x; for x in "${f[@]:1}"; do tail -c +25 "$x" >> "$dest"; done
  echo "${#f[@]}"
}

# runp <label> <watchfile/dir> -- <cmd...> : jalan di bg, poll ukuran tiap 10s SAMPAI SELESAI
# (tanpa timeout-kill: asal progress kelihatan, biarkan jalan sampai beres).
runp(){ local label="$1" watch="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  "$@" & local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 10; t=$((t+10))
    echo "   [$(now)] $label +${t}s out=$(du -sh "$watch" 2>/dev/null | cut -f1)"
  done
  wait "$pid" 2>/dev/null || true
}

for i in enp0s8 enp0s9 enp0s10; do
  n=$(merge_iface "$i" "$OUT/$i.pcap") || { echo "[$(now)] WARN: tak ada pcap $i di $PCAP"; continue; }
  echo "[$(now)] === $i ($n file rotasi -> merge; input $(du -sh "$OUT/$i.pcap" | cut -f1)) ==="
  mkdir -p "$OUT/zeek-$i" "$OUT/argus-$i"
  runp "$i:zeek"  "$OUT/zeek-$i"            -- bash -c "cd '$OUT/zeek-$i' && '$ZEEK' -C -r '$OUT/$i.pcap' local 2>/dev/null"
  runp "$i:argus" "$OUT/argus-$i/$i.argus"  -- "$ARGUS" -r "$OUT/$i.pcap" -w "$OUT/argus-$i/$i.argus" -P 0
  if ! timeout 20 "$RA" -r "$OUT/argus-$i/$i.argus" -c , -s stime 2>/dev/null | head -1 | grep -q .; then
    echo "[$(now)] $i: argus tak menghasilkan flow valid -> dilewati"; rm -f "$OUT/argus-$i/$i.argus"
  fi
done

echo "[$(now)] === Tahap A: ra_export ==="
bash ~/pipeline/ra_export.sh "$OUT" "$OUT/argus_csv" "$RA" || true
echo "[$(now)] === Tahap B: build_dataset single-view ==="
python3 ~/pipeline/build_dataset.py --argus-dir "$OUT/argus_csv" --zeek-root "$OUT" --markers "$MARK" --out "$OUT/unsw.csv"
echo "[$(now)] === Tahap B: build_dataset multi-view ==="
python3 ~/pipeline/build_dataset.py --argus-dir "$OUT/argus_csv" --zeek-root "$OUT" --markers "$MARK" --out "$OUT/unsw_multi.csv" --dedup off --add-vantage
echo "[$(now)] === SELESAI OUTDIR=$OUT ==="
