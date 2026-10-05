#!/usr/bin/env bash
set -euo pipefail
INPUT_PCAP="${1:?usage: run-zeek.sh <pcap> [output-dir]}"
OUTPUT_DIR="${2:-zeek-output}"
mkdir -p "$OUTPUT_DIR"
zeek -Cr "$INPUT_PCAP" LogAscii::use_json=T Site::local_nets='[10.0.0.0/8]' 2>&1 | tee "$OUTPUT_DIR/run.log"
