#!/usr/bin/env bash
# common.sh — fungsi bersama untuk semua skenario serangan.
# Di-source oleh tiap scenarios/sNN-*/run.sh:
#   HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
# Tiap run.sh WAJIB set sebelum/ sesudah source: SCN, ATTACK_CAT, PHASE.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$LIB_DIR/targets.env"
USERLIST="$LIB_DIR/$USERLIST"
PASSLIST="$LIB_DIR/$PASSLIST"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_rst=$'\033[0m'

die(){ echo "${c_red}ERROR:${c_rst} $*" >&2; exit 1; }
now_utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

banner(){
  echo "============================================================"
  echo " ${SCN} | attack_cat=${ATTACK_CAT} | phase=${PHASE}"
  echo " LAB ONLY — jaringan terisolasi, target milik sendiri."
  echo " Waktu mulai (UTC): $(now_utc)"
  echo "============================================================"
}

# tolak target di luar range lab (pengaman salah ketik / salah alamat)
require_lab_target(){
  case "$1" in
    10.10.10.*|10.10.20.*|10.10.30.*|192.168.56.*) : ;;
    *) die "Target '$1' di luar range lab (10.10.0.0/16, 192.168.56.0/24) — ditolak." ;;
  esac
}

# pastikan tool ada; kalau tidak, STOP (jangan improvisasi/instal diam-diam)
need_tool(){ command -v "$1" >/dev/null 2>&1 || die "Tool '$1' tidak ada di attacker. Cek inventaris Phase 3 attacker; jangan pasang lewat internet (lab isolated)."; }

# pastikan target hidup (ping). Gagal = kemungkinan salah PHASE (VM target mati).
ensure_up(){
  require_lab_target "$1"
  ping -c1 -W2 "$1" >/dev/null 2>&1 || die "Target $1 tidak merespons ping. Pastikan PHASE benar & VM target nyala (lihat PHASE=$PHASE di header)."
}

# penanda waktu untuk pelabelan. mark_start sebelum serangan, mark_end sesudah.
_SC_START=""
mark_start(){ _SC_START="$(now_utc)"; echo "${c_grn}>>> START${c_rst} $SCN target=${1:-lab} @ $_SC_START"; }
mark_end(){
  local tgt="${1:-lab}" end; end="$(now_utc)"
  [ -f "$MARKER_LOG" ] || echo "scenario,attack_cat,phase,target,start_utc,end_utc" > "$MARKER_LOG"
  echo "$SCN,$ATTACK_CAT,$PHASE,$tgt,$_SC_START,$end" >> "$MARKER_LOG"
  echo "${c_grn}<<< END${c_rst}   $SCN @ $end  (marker -> $MARKER_LOG)"
}

# jeda antar-fase serangan biar window flow jelas terpisah di pcap
settle(){ local s="${1:-5}"; echo "   ...jeda ${s}s (pemisah window)"; sleep "$s"; }
