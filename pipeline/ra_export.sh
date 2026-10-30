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
  { echo "$HDR,segment"
    # -M nomar: buang record status Argus; -u: stime/ltime epoch; -n: jangan resolve DNS
    TZ=UTC "$RA" -M nomar -u -n -r "$a" -c ',' -s $FIELDS 2>/dev/null \
      | awk -v s="$seg" 'NR>1 && NF {print $0","s}'
  } > "$out"
  echo "  $seg -> $out ($(( $(wc -l < "$out") - 1 )) flows)"
done
[ "$found" = 1 ] || { echo "ERROR: tak ada argus-*/*.argus di $EXDIR"; exit 1; }
