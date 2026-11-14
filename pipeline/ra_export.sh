#!/usr/bin/env bash
# Tahap A — re-export .argus (biner) -> CSV 32 field numerik UNSW (epoch, tanpa MAR).
# Dijalankan di mesin yang punya argus-client v5 (sensor, atau mesin build ra v5).
# ra v3 TIDAK bisa baca file argus v5 -> wajib ra v5.
#
# Usage: ra_export.sh <extraction_dir> <out_dir> [ra_binary]
#   extraction_dir : folder berisi argus-<iface>/<iface>.argus (hasil sensor)
#   out_dir        : tujuan CSV per-segmen
#   ra_binary      : path ra (default: 'ra' di PATH)
set -euo pipefail
# FIX Q-P1-J: paksa locale C supaya decimal separator = titik (bukan koma
# di locale id_ID), dan TZ=UTC konsisten untuk stime/ltime.
export LC_ALL=C
export LANG=C
export TZ=UTC

EXDIR="${1:?extraction dir}"; OUT="${2:?out dir}"; RA="${3:-ra}"

# 32 field argus = basic/content/time/state UNSW-NB15 (ct_*/service/http diisi Tahap B)
FIELDS="stime ltime dur proto saddr sport daddr dport state sbytes dbytes sttl dttl sloss dloss spkts dpkts swin dwin stcpb dtcpb smeansz dmeansz sload dload sjit djit sintpkt dintpkt tcprtt synack ackdat"
HDR="stime,ltime,dur,proto,saddr,sport,daddr,dport,state,sbytes,dbytes,sttl,dttl,sloss,dloss,spkts,dpkts,swin,dwin,stcpb,dtcpb,smeansz,dmeansz,sload,dload,sjit,djit,sintpkt,dintpkt,tcprtt,synack,ackdat"

mkdir -p "$OUT"; shopt -s nullglob
found=0
for a in "$EXDIR"/argus-*/*.argus; do
  found=1
  seg="$(basename "$a" .argus)"                       # enp0s8 / enp0s9 / enp0s10
  out="$OUT/${seg}_argus49.csv"
  tmp="$out.part"
  { echo "$HDR,segment"
    # -M nomar: buang record status Argus; -u: stime/ltime epoch; -n: jangan resolve DNS
    "$RA" -M nomar -u -n -r "$a" -c ',' -s $FIELDS 2>/dev/null \
      | awk -v s="$seg" '
          # FIX Q-P1-I: header detection aman — baris pertama di-skip HANYA jika
          # field pertama bukan numerik (stime harus numeric). Ini handle ra
          # yang kadang cetak header kadang tidak, tergantung versi.
          NR==1 {
            split($0, f, ",")
            if (f[1] !~ /^-?[0-9]+(\.[0-9]+)?$/) next
          }
          NF { print $0 "," s }
        '
  } > "$tmp"

  n=$(( $(wc -l < "$tmp") - 1 ))   # -1 untuk header CSV
  if [ "$n" -lt 1 ]; then
    echo "  WARN: $seg tidak menghasilkan flow valid -> dilewati"
    rm -f "$tmp"
    continue
  fi
  mv "$tmp" "$out"
  echo "  $seg -> $out ($n flows)"
done
# FIX Q-P1-K: log versi ra untuk reproduktibilitas

[ "$found" = 1 ] || { echo "ERROR: tak ada argus-*/*.argus di $EXDIR"; exit 1; }
