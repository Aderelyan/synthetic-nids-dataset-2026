#!/usr/bin/env bash
# Offline Argus extraction from a saved pcap (see docs/phase5-sensor.md section 7.3).
set -euo pipefail
INPUT_PCAP="${1:?usage: run-argus.sh <pcap> [output-dir]}"
OUTPUT_DIR="${2:-argus-output}"
BASE="$(basename "${INPUT_PCAP%.pcap}")"
mkdir -p "$OUTPUT_DIR"
argus -r "$INPUT_PCAP" -w "$OUTPUT_DIR/$BASE.argus" -P 0
# -M nomar drops Argus's own status records, which otherwise look like flows.
ra -M nomar -r "$OUTPUT_DIR/$BASE.argus" -c ',' \
  -s stime,dur,proto,saddr,sport,daddr,dport,sttl,dttl,sbytes,dbytes,spkts,dpkts,state \
  > "$OUTPUT_DIR/${BASE}_flows.csv"
