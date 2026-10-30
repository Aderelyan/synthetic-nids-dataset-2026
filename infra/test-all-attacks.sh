#!/usr/bin/env bash
# test-all-attacks.sh — SMOKE TEST semua skenario serangan (validasi cepat: tiap attack VALID).
# Menjalankan tiap scenarios/sNN/run.sh di ATTACKER (via jump router) dengan argumen SINGKAT
# + timeout, lalu lapor PASS/FAIL per skenario. TIDAK menjalankan pcap (ini validasi tool,
# bukan capture data) — bukti "serangan valid" = tool benar-benar jalan & hasil terlihat.
#
# Pakai (di git-bash, dari ROOT repo):
#   bash infra/test-all-attacks.sh            # semua 12 skenario
#   bash infra/test-all-attacks.sh linux      # 9 skenario fase Linux (client-1/2 nyala)
#   bash infra/test-all-attacks.sh windows    # 3 skenario fase Windows + S03 (win-client nyala)
#
# Prasyarat:
#   - router-opnsense, attacker, sensor, srv-web, srv-file NYALA (selalu).
#   - fase 'linux'   : client-1 & client-2 NYALA, win-client MATI.
#   - fase 'windows' : win-client NYALA, client-1/2 MATI.
#   - S09: skrip ini menyalakan iodined otomatis di srv-file.
#   - Output tiap skenario disimpan ke test-attacks-<folder>.log untuk bukti.
set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
SENSOR_PW='sensor'; ROOT_PW='root'; KALI_PW='kali'; LAB_PW='labadmin'
SENSOR=192.168.56.20; ATT=10.10.30.10; SRVWEB=10.10.10.10; SRVFILE=10.10.10.11
PHASE="${1:-all}"

O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=12 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
PX="sshpass -p $ROOT_PW ssh $O -W %h:%p root@192.168.56.10"
att(){ sshpass -p $KALI_PW ssh $O -o ProxyCommand="$PX" kali@$ATT "$1"; }
srv(){ sshpass -p $LAB_PW ssh $O -o ProxyCommand="$PX" labadmin@$SRVFILE "echo '$LAB_PW' | sudo -S bash -c '$1'"; }
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*"; }
strip(){ sed -E 's/\x1b\[[0-9;]*m//g'; }

# --- daftar skenario per fase ---
LINUX_SCNS="s01-port-scanning s02-bruteforce-ssh-ftp s03-password-spraying s04-web-injection-sqli s08-ssh-lateral-movement s09-dns-tunneling-doh s10-ransomware-smb-sim s11-dos-ddos-hping3 s12-data-exfiltration"
WIN_SCNS="s05-rdp-bruteforce s06-winrm-lateral-movement s07-lsass-dump-pth"
case "$PHASE" in
  linux)   SCNS="$LINUX_SCNS";;
  windows) SCNS="s03-password-spraying $WIN_SCNS";;
  all)     SCNS="$LINUX_SCNS $WIN_SCNS";;
  *) echo "phase salah. Pakai: linux | windows | all"; exit 2;;
esac

# argumen SINGKAT + timeout per skenario (supaya cepat)
args_for(){ case "$1" in
  s09-dns-tunneling-doh) echo "60";;                 # tunnel 60 dtk (butuh autodetect + establish)
  s10-ransomware-smb-sim) echo "10";;                # 10 file (bukan 40)
  s11-dos-ddos-hping3) echo "$SRVWEB 80 10";;       # DoS 10 dtk (bukan 60)
  *) echo "";;
esac; }
timeout_for(){ case "$1" in
  s01-port-scanning) echo 300;;
  s02-bruteforce-ssh-ftp) echo 180;;
  s03-password-spraying) echo 240;;
  s04-web-injection-sqli) echo 180;;
  s05-rdp-bruteforce) echo 180;;
  s06-winrm-lateral-movement) echo 120;;
  s07-lsass-dump-pth) echo 180;;
  s08-ssh-lateral-movement) echo 120;;
  s09-dns-tunneling-doh) echo 100;;
  s10-ransomware-smb-sim) echo 120;;
  s11-dos-ddos-hping3) echo 40;;
  s12-data-exfiltration) echo 120;;
  *) echo 180;;
esac; }

[ -f scenarios/run-1h.sh ] || { echo "STOP: jalankan dari ROOT repo."; exit 1; }
log "=== TEST ALL ATTACKS (phase=$PHASE) ==="

# 0) pre-flight: attacker reachable
att "echo ATT-OK" >/dev/null 2>&1 || { echo "STOP: attacker ($ATT) tak terjangkau. Nyalakan router-opnsense + attacker dulu."; exit 1; }
log "attacker reachable."

# 1) deploy skenario terbaru -> attacker:~/scenarios (bersihkan dulu)
log "deploy scenarios -> attacker"
tar -czf - --exclude='scenarios/normal' scenarios \
  | att "rm -rf ~/scenarios && tar -xzf - -C ~ && echo DEPLOYED $(ls -1 ~/scenarios | grep -c '^s[0-9]') skenario" \
  || { echo "STOP: deploy scenarios gagal."; exit 1; }

# 2) jalankan tiap skenario
RESULT=""
for s in $SCNS; do
  to=$(timeout_for "$s"); args=$(args_for "$s")
  scn_code=$(sed -nE 's/.*(^|[;[:space:]])SCN="?([^;"]*)"?.*/\2/p' "scenarios/$s/run.sh" 2>/dev/null | head -1)
  log ">>> $s (${scn_code:-?}) timeout=${to}s"

  # S09: nyalakan iodined di srv-file dulu (prasyarat tunnel)
  [ "$s" = "s09-dns-tunneling-doh" ] && { srv "systemctl unmask iodined 2>/dev/null; systemctl start iodined 2>/dev/null; true" || true; }

  before=$(att "grep -vc '^scenario,' ~/attack-markers.csv 2>/dev/null || echo 0" | tr -d ' \r')
  before=${before:-0}

  raw=$(att "cd ~/scenarios/$s || exit 99; timeout $to bash run.sh $args 2>&1; echo __RC__=\$?")
  rc=$(printf '%s\n' "$raw" | grep '__RC__=' | tail -1 | cut -d= -f2)
  out=$(printf '%s\n' "$raw" | grep -v '__RC__=' | strip)

  after=$(att "grep -vc '^scenario,' ~/attack-markers.csv 2>/dev/null || echo 0" | tr -d ' \r')
  after=${after:-0}

  verdict="PASS"
  [ "$rc" = "124" ] && verdict="FAIL(timeout ${to}s)"
  { [ "$rc" != "0" ] && [ "$rc" != "124" ]; } && verdict="FAIL(rc=$rc)"
  printf '%s\n' "$out" | grep -qiE 'ERROR:|S08-FAIL' && verdict="FAIL"

  printf '%s\n' "$out" > "test-attacks-$s.log"

  echo "  [$verdict] rc=$rc marker=$before->$after"
  # bukti singkat: baris pertama (banner) + baris hasil terakhir
  printf '%s\n' "$out" | grep -iE 'attack_cat=|Selesai|S08-OK|S08-FAIL|tunnel up|Diterima nc|Host is up|valid|Target discovery|login found|HOP-FINAL|chain berhasil|STOP|ERROR:' | head -6 | sed 's/^/    /'
  RESULT="$RESULT\n$s : $verdict"
  echo
done

echo "================ RINGKASAN ================"
printf '%b\n' "$RESULT" | sed '/^$/d'
echo "============================================"
echo "Log per skenario: test-attacks-<folder>.log"
