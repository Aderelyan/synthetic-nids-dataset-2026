#!/usr/bin/env bash
# Phase 6 (WINDOWS PHASE) — validasi ISOLASI + BASELINE/SENSOR. READ-ONLY.
# Jalankan di git-bash HOST dari root repo:  bash validation/phase6-windows.sh
#
# Fokus: win-client ON, client-1/2 OFF. Cek win-client punya gateway (Phase 4),
# sensor enp0s9 menangkap trafik RDP/SMB/WinRM, dan isolasi internet dari Windows.
# Berhenti otomatis setelah 6 error. SSH dibungkus timeout + ServerAlive.

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
command -v sshpass >/dev/null || { echo "ERROR: sshpass tak ada di /c/msys64/usr/bin"; exit 1; }

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }
echo "Kredensial (Enter = default):"
USER_KALI=$(ask "User attacker" kali);        PASS_KALI=$(asksecret "  pw" kali)
USER_SEN=$(ask "User sensor" sensor);          PASS_SEN=$(asksecret "  pw" sensor)
WIN_USER=$(ask "User win-client (admin)" admin_lab); WIN_PASS=$(asksecret "  pw" Admin@2024)
PASS_ROUTER=$(asksecret "pw router jump (root)" root)
echo

mkdir -p validation
RPT="validation/laporan-phase6-windows-$(date -u +%Y%m%d-%H%M%S).md"
O="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=2"
PROXY="sshpass -p '$PASS_ROUTER' ssh $O -W %h:%p root@192.168.56.10"
jr(){ timeout 150 env SSH_AUTH_SOCK= sshpass -p "$2" ssh $O -o ProxyCommand="$PROXY" "$1" "$3" 2>&1; }  # attacker (jump)
dr(){ timeout 150 env SSH_AUTH_SOCK= sshpass -p "$2" ssh $O "$1" "$3" 2>&1; }                           # sensor (langsung)
vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }

ERR=0
rec(){ printf '%s\n' "$*" | tee -a "$RPT"; }
STOPNOW(){ rec ""; rec "================ STOP ================"; rec "$1"; rec "Sudah $ERR error. BERHENTI & lapor ke user — jangan lanjut/improvisasi."; rec ""; echo; echo "Laporan: $RPT"; cat "$RPT"; exit 1; }
PASS(){ rec "  PASS: $1"; }
FAIL(){ ERR=$((ERR+1)); rec "  FAIL ($ERR/6): $1"; [ "$ERR" -ge 6 ] && STOPNOW "Mencapai 6 error."; }

{ echo "# Laporan Phase 6 (Windows phase) — Isolasi + Baseline Sensor"; echo; echo "Dibuat (UTC): $(date -u '+%F %T')Z"; echo; } > "$RPT"

# ---------- 1. isolasi NIC (host) ----------
rec "## 1. Sapuan isolasi NIC (host)"
for v in router-opnsense srv-web srv-file client-1 client-2 win-client attacker sensor; do
  bad=$(VBoxManage showvminfo "$v" --machinereadable 2>/dev/null | grep -iE '^nic[0-9]=' | grep -viE '=\"(none|null|intnet|hostonly)\"' || true)
  if [ -z "$bad" ]; then PASS "$v: hanya intnet/hostonly/none"; else rec "    $bad"; FAIL "$v: ADA NIC non-isolasi"; fi
done

# ---------- 2. phase switch ke Windows ----------
rec ""
rec "## 2. Phase switch: win-client ON, client-1/2 OFF"
for v in client-1 client-2; do VBoxManage controlvm "$v" acpipowerbutton >/dev/null 2>&1 || true; done
for v in router-opnsense sensor srv-web srv-file attacker win-client; do
  [ "$(vmstate "$v")" = running ] || VBoxManage startvm "$v" --type headless >/dev/null 2>&1
done
rec "    menunggu boot 75s..."; sleep 75
for v in client-1 client-2; do
  if [ "$(vmstate "$v")" != running ]; then PASS "$v mati (phase switching benar)"; else FAIL "$v masih nyala (harus mati di Windows phase)"; fi
done
[ "$(vmstate win-client)" = running ] && PASS "win-client nyala" || FAIL "win-client tidak nyala"

# tunggu win-client reachable dari attacker (punya gateway dari Phase 4)
rec "    menunggu win-client reachable dari attacker..."
up=""
for n in 1 2 3 4 5 6 7 8 9 10; do
  jr "$USER_KALI@10.10.30.10" "$PASS_KALI" "ping -c1 -W2 10.10.20.50 >/dev/null 2>&1 && echo __WINUP__" | grep -q __WINUP__ && { up=1; break; }
  sleep 10
done
[ -n "$up" ] && PASS "win-client reachable (routing Windows OK)" || FAIL "win-client tak reachable dari attacker (boot lambat / gateway?)"

# ---------- 3. sensor capture + ukuran awal enp0s9 ----------
rec ""
rec "## 3. Sensor capture aktif + ukuran enp0s9 awal"
act=$(dr "$USER_SEN@192.168.56.20" "$PASS_SEN" "systemctl is-active pcap-capture@enp0s9")
rec "    enp0s9 is-active: $(echo "$act" | tr '\n' ' ')"
echo "$act" | grep -q '^active' && PASS "tcpdump enp0s9 active" || FAIL "tcpdump enp0s9 tidak active"
PRE=$(dr "$USER_SEN@192.168.56.20" "$PASS_SEN" "f=\$(ls -t /var/log/pcap/enp0s9/*.pcap 2>/dev/null | head -1); stat -c%s \"\$f\" 2>/dev/null || echo 0")
PRE=${PRE//[!0-9]/}; PRE=${PRE:-0}
rec "    pre enp0s9: $PRE byte"

# ---------- 4. trafik uji ke win-client (RDP/SMB/WinRM) + isolasi via WinRM ----------
rec ""
rec "## 4. Trafik attacker->win-client + cek dari dalam Windows"
TOUCH='echo "-- ping win --"; ping -c3 10.10.20.50; echo "-- ports --"; for p in 445 3389 5985; do nc -z -w2 10.10.20.50 $p && echo "port $p OPEN" || echo "port $p closed"; done'
o=$(jr "$USER_KALI@10.10.30.10" "$PASS_KALI" "$TOUCH")
rec "    ${o//$'\n'/$'\n'    }"
echo "$o" | grep -q "0% packet loss" && PASS "attacker->win-client ping OK (trafik segmen client)" || FAIL "ping win-client gagal"
echo "$o" | grep -q "port 3389 OPEN" && PASS "RDP 3389 terbuka" || rec "  (catatan: RDP 3389 tak terdeteksi terbuka)"
echo "$o" | grep -q "port 445 OPEN"  && PASS "SMB 445 terbuka"  || rec "  (catatan: SMB 445 tak terdeteksi terbuka)"
echo "$o" | grep -q "port 5985 OPEN" && PASS "WinRM 5985 terbuka" || rec "  (catatan: WinRM 5985 tak terdeteksi terbuka)"

rec "    -- dari dalam win-client via WinRM (nxc): reach server + isolasi internet --"
r1=$(jr "$USER_KALI@10.10.30.10" "$PASS_KALI" "nxc winrm 10.10.20.50 -u $WIN_USER -p '$WIN_PASS' -x 'ping -n 2 10.10.10.10'")
rec "    [win->srv-web] ${r1//$'\n'/$'\n    '}"
r2=$(jr "$USER_KALI@10.10.30.10" "$PASS_KALI" "nxc winrm 10.10.20.50 -u $WIN_USER -p '$WIN_PASS' -x 'ping -n 2 8.8.8.8'")
rec "    [win->8.8.8.8] ${r2//$'\n'/$'\n    '}"
if echo "$r1$r2" | grep -qi "Pinging\|Reply from\|Request timed"; then
  echo "$r1" | grep -qi "Reply from 10.10.10.10" && PASS "win-client -> srv-web reachable (inter-segmen Windows OK)" || FAIL "win-client tak bisa reach srv-web"
  echo "$r2" | grep -qi "Reply from 8.8.8.8" && FAIL "ISOLASI BOCOR: win-client bisa reach 8.8.8.8" || PASS "ISOLASI: win-client tak bisa reach 8.8.8.8"
else
  FAIL "WinRM (nxc) tak menghasilkan output ping — cek kredensial win / WinRM. Langkah dalam-Windows tak bisa dinilai."
fi

# ---------- 5. sensor enp0s9 bertambah ----------
rec ""
rec "## 5. Sensor enp0s9 menangkap trafik Windows (ukuran bertambah)"
sleep 6
POST=$(dr "$USER_SEN@192.168.56.20" "$PASS_SEN" "f=\$(ls -t /var/log/pcap/enp0s9/*.pcap 2>/dev/null | head -1); stat -c%s \"\$f\" 2>/dev/null || echo 0")
POST=${POST//[!0-9]/}; POST=${POST:-0}
rec "    post enp0s9: $POST byte (pre $PRE)"
[ "$POST" -gt "$PRE" ] && PASS "enp0s9 bertambah -> sensor menangkap trafik Windows" || FAIL "enp0s9 TIDAK bertambah"

# ---------- ringkasan ----------
rec ""
rec "## RINGKASAN"
rec "Total error: $ERR / 6"
[ "$ERR" -eq 0 ] && rec "SEMUA PASS — isolasi & baseline sensor (Windows phase) VALID." || rec "Ada $ERR temuan FAIL — lihat detail di atas."
echo; echo "Laporan: $RPT"; cat "$RPT"
