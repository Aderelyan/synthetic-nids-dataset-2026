#!/usr/bin/env bash
# run-1h.sh — ulang SATU skenario selama DURASI (default 1 jam) agar window capture
# berisi volume flow attack yang cukup. Dipakai untuk skenario yang cepat selesai
# (S01 recon, S02/S03 brute, S04 SQLi, S06/S07/S08/S10/S12). Skenario kontinu by-design
# (S11 DoS, S09 tunnel) boleh dijalankan run.sh langsung — wrapper ini tetap aman
# (per-iterasi dibatasi `timeout` sampai batas jam).
#
# Menulis SATU window (start..end) ke ~/capture-windows.csv = SUMBER LABEL untuk
# build_dataset.py (--markers). (run.sh tetap menulis per-iterasi ke ~/attack-markers.csv;
# untuk pelabelan pakai capture-windows.csv ini, bukan attack-markers.csv.)
#
# Usage: run-1h.sh <folder-skenario> [durasi_detik=3600] [gap_detik=5] [-- args run.sh...]
#   contoh: bash run-1h.sh s08-ssh-lateral-movement 3600 5
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="${1:?folder skenario, mis. s08-ssh-lateral-movement}"; shift || true
DUR=3600; GAP=5
[ $# -gt 0 ] && case "$1" in --) : ;; *) DUR="$1"; shift;; esac
[ $# -gt 0 ] && case "$1" in --) : ;; *) GAP="$1"; shift;; esac
[ "${1:-}" = "--" ] && shift || true           # sisa argumen -> diteruskan ke run.sh

RS="$HERE/$FOLDER/run.sh"
[ -f "$RS" ] || { echo "ERROR: $RS tak ada (nama folder skenario salah?)"
  echo "  Valid: $(ls -1 "$HERE" | grep -E '^s[0-9]+-' | tr '\n' ' ')"; exit 1; }
# ambil nilai var meski ditulis 1 baris (SCN=..; ATTACK_CAT=..; PHASE=..) & nilai bisa
# berisi spasi/kutip (mis. "Brute Force"). Potong di ';' atau kutip.
meta(){ sed -nE "s/.*(^|[;[:space:]])$1=\"?([^;\"]*)\"?.*/\2/p" "$RS" | head -1; }
SCN="$(meta SCN)"; CAT="$(meta ATTACK_CAT)"; PHASE="$(meta PHASE)"
now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
MARK="$HOME/capture-windows.csv"
[ -f "$MARK" ] || echo "scenario,attack_cat,phase,target,start_utc,end_utc" > "$MARK"

START="$(now)"; DEAD=$(( $(date +%s) + DUR )); n=0; fail=0
echo "[1h] $SCN ($CAT) loop hingga ${DUR}s, gap ${GAP}s — mulai $START"
while :; do
  rem=$(( DEAD - $(date +%s) )); [ "$rem" -le 0 ] && break
  n=$((n+1))
  if timeout "${rem}s" bash "$RS" "$@" >/dev/null 2>&1; then
    fail=0
  else
    rc=$?
    if [ "$rc" = 124 ]; then break                       # kena batas jam (skenario kontinu) — normal
    else fail=$((fail+1)); echo "  iterasi $n GAGAL rc=$rc (beruntun $fail)"
      [ "$fail" -ge 5 ] && { echo "[1h] STOP: 5 gagal beruntun — cek skenario"; break; }
    fi
  fi
  rem=$(( DEAD - $(date +%s) )); [ "$rem" -gt 0 ] && sleep "$GAP"
done
END="$(now)"
echo "$SCN,$CAT,$PHASE,loop-${n}x,$START,$END" >> "$MARK"
echo "[1h] $SCN selesai $END — $n iterasi (window -> $MARK)"
