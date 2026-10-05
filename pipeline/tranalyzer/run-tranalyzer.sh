#!/usr/bin/env bash
set -euo pipefail
INPUT_PCAP="${1:?usage: run-tranalyzer.sh <pcap> [output-dir]}"
OUTPUT_DIR="${2:-tranalyzer-output}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"
tranalyzer "$INPUT_PCAP"
