#!/usr/bin/env bash
# dvwa-ensure.sh — pastikan container DVWA benar-benar MELAYANI :80 setelah boot.
# Image vulnerables/web-dvwa kadang "Up" tapi apache/mysql gagal init saat auto-start
# setelah host reboot -> :80 connection refused. Service ini menyembuhkan tanpa intervensi.
set -u
log(){ logger -t dvwa-ensure "$*" 2>/dev/null; echo "dvwa-ensure: $*"; }
serving(){ local c; c=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null); [ "$c" = "302" ] || [ "$c" = "200" ]; }
# 1) tunggu docker daemon siap
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker start dvwa >/dev/null 2>&1 || true
# 2) tunggu DVWA melayani (~60s)
for i in $(seq 1 20); do serving && { log "serving (pass 1)"; exit 0; }; sleep 3; done
# 3) belum -> restart sekali, tunggu lagi (~90s)
log "belum melayani -> docker restart dvwa"
docker restart dvwa >/dev/null 2>&1 || true
for i in $(seq 1 30); do serving && { log "serving (pass 2)"; exit 0; }; sleep 3; done
log "GAGAL: DVWA tak melayani :80 setelah restart (cek: docker logs dvwa)"
exit 0   # jangan gagalkan boot
