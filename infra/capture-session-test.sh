#!/usr/bin/env bash
# capture-session-test.sh — UJI ORKESTRASI (bukan capture asli).
# Memanggil capture-session.sh dengan tiap window 2 menit + gap 15 detik, supaya
# seluruh alur (clean pcap -> Normal -> 9 skenario + iodined S09 -> stop pcap) teruji
# cepat (~25 menit) sebelum jalan versi 1 jam penuh.
#
# Jalankan di git-bash:
#   bash infra/capture-session-test.sh 2>&1 | tee session-TEST-$(date +%Y%m%d-%H%M).log
#
# Prasyarat sama dgn capture-session.sh (VM fase Linux nyala, win-client mati).
# Artefak uji (pcap pendek + marker) otomatis tertimpa saat capture-session.sh asli
# dijalankan (ia bersihkan pcap + reset marker di awal).
exec bash "$(dirname "$0")/capture-session.sh" 120 15
