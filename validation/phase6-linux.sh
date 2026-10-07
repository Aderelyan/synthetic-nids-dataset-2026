#!/usr/bin/env bash
# Phase 6 (LINUX PHASE) — validasi ISOLASI + BASELINE/SENSOR. READ-ONLY.
# Jalankan di git-bash HOST dari root repo:  bash validation/phase6-linux.sh
#
# ATURAN: tiap cek yang gagal dihitung 1 error. Setelah 6 error -> BERHENTI,
# tulis "===== STOP =====", simpan laporan, keluar. JANGAN improvisasi.
# SSH dibungkus timeout 150s + ServerAlive (anti-hang seperti kasus client-2).

set -uo pipefail
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
command -v sshpass >/dev/null || { echo "ERROR: sshpass tak ada di /c/msys64/usr/bin"; exit 1; }

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
asksecret(){ local v; read -r -s -p "$1 [Enter=$2]: " v; echo >&2; echo "${v:-$2}"; }
echo "Kredensial (Enter = default):"
USER_LIN=$(ask "User srv-*/client-*" labadmin);  PASS_LIN=$(asksecret "  pw" labadmin)
USER_SEN=$(ask "User sensor" sensor);            PASS_SEN=$(asksecret "  pw" sensor)
USER_KALI=$(ask "User attacker" kali);           PASS_KALI=$(asksecret "  pw" kali)
PASS_ROUTER=$(asksecret "pw router jump (root)" root)
echo

mkdir -p validation
RPT="validation/laporan-phase6-linux-$(date -u +%Y%m%d-%H%M%S).md"
O="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=2"
PROXY="sshpass -p '$PASS_ROUTER' ssh $O -W %h:%p root@192.168.56.10"
# jrun user@ip pass cmd  (lewat jump router) ; drun user@ip pass cmd (langsung, utk sensor)
jrun(){ timeout 150 env SSH_AUTH_SOCK= sshpass -p "$2" ssh $O -o ProxyCommand="$PROXY" "$1" "$3" 2>&1; }
drun(){ timeout 150 env SSH_AUTH_SOCK= sshpass -p "$2" ssh $O "$1" "$3" 2>&1; }
vmstate(){ VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | grep -i '^VMState=' | cut -d'"' -f2; }

ERR=0
rec(){ printf '%s\n' "$*" | tee -a "$RPT"; }
STOPNOW(){ rec ""; rec "================ STOP ================"; rec "$1"; rec "Sudah $ERR error. BERHENTI & lapor ke user — jangan lanjut/improvisasi."; rec ""; echo; echo "Laporan: $RPT"; cat "$RPT"; exit 1; }
PASS(){ rec "  PASS: $1"; }
FAIL(){ ERR=$((ERR+1)); rec "  FAIL ($ERR/6): $1"; [ "$ERR" -ge 6 ] && STOPNOW "Mencapai 6 error."; }

{ echo "# Laporan Phase 6 (Linux phase) — Isolasi + Baseline Sensor"; echo; echo "Dibuat (UTC): $(date -u '+%F %T')Z"; echo; } > "$RPT"

# ---------- 1. isolasi NIC (host) ----------
rec "## 1. Sapuan isolasi NIC (host)"
for v in router-opnsense srv-web srv-file client-1 client-2 win-client attacker sensor; do
  bad=$(VBoxManage showvminfo "$v" --machinereadable 2>/dev/null | grep -iE '^nic[0-9]=' | grep -viE '=\"(none|null|intnet|hostonly)\"' || true)
  if [ -z "$bad" ]; then PASS "$v: hanya intnet/hostonly/none"
  else rec "    $bad"; FAIL "$v: ADA NIC non-isolasi (nat/bridged/natnetwork)"; fi
done

# ---------- 2. phase VMs ----------
rec ""
rec "## 2. Nyalakan Linux phase + sensor, matikan win-client"
VBoxManage controlvm win-client poweroff >/dev/null 2>&1 || true
for v in router-opnsense sensor srv-web srv-file client-1 client-2 attacker; do
  [ "$(vmstate "$v")" = running ] || VBoxManage startvm "$v" --type headless >/dev/null 2>&1
done
rec "    menunggu boot 60s..."; sleep 60
if [ "$(vmstate win-client)" != running ]; then PASS "win-client mati (phase switching benar)"; else FAIL "win-client masih nyala (harus mati di Linux phase)"; fi
# tunggu attacker siap SSH (anti-gagal karena boot lambat)
rec "    menunggu attacker siap SSH..."
up=""
for n in 1 2 3 4 5 6 7 8; do
  jrun "$USER_KALI@10.10.30.10" "$PASS_KALI" "echo __UP__" | grep -q __UP__ && { up=1; break; }
  sleep 10
done
[ -n "$up" ] && rec "    attacker siap." || rec "    (attacker belum siap ~140s; langkah 5 mungkin gagal)"

# ---------- 3. journald persisten srv-file ----------
rec ""
rec "## 3. journald permanen di srv-file"
o=$(jrun "$USER_LIN@10.10.10.11" "$PASS_LIN" "echo '$PASS_LIN' | sudo -S bash -c 'mkdir -p /var/log/journal && systemd-tmpfiles --create --prefix /var/log/journal && systemctl restart systemd-journald && journalctl --disk-usage'")
rec "    ${o//$'\n'/$'\n'    }"
if echo "$o" | grep -qi "journals take"; then PASS "journald persisten aktif"; else FAIL "journald persisten gagal"; fi

# ---------- 4. sensor capture aktif + ukuran awal ----------
rec ""
rec "## 4. Sensor capture aktif + ukuran pcap awal"
act=$(drun "$USER_SEN@192.168.56.20" "$PASS_SEN" "systemctl is-active pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10")
rec "    is-active: $(echo "$act" | tr '\n' ' ')"
if [ "$(echo "$act" | grep -c '^active')" -eq 3 ]; then PASS "3 instance tcpdump active"; else FAIL "tcpdump tidak 3x active"; fi
declare -A PRE
for i in enp0s8 enp0s9 enp0s10; do
  PRE[$i]=$(drun "$USER_SEN@192.168.56.20" "$PASS_SEN" "f=\$(ls -t /var/log/pcap/$i/*.pcap 2>/dev/null | head -1); stat -c%s \"\$f\" 2>/dev/null || echo 0")
  PRE[$i]=${PRE[$i]//[!0-9]/}; PRE[$i]=${PRE[$i]:-0}
  rec "    pre $i: ${PRE[$i]} byte"
done

# ---------- 5. trafik uji (attacker) + isolasi ----------
rec ""
rec "## 5. Trafik uji dari attacker + uji isolasi"
GEN='for t in 10.10.10.10 10.10.10.11 10.10.20.20 10.10.20.21; do ping -c5 -i0.2 $t >/dev/null 2>&1 && echo "ping $t OK" || echo "ping $t GAGAL"; done; curl -s -m5 http://10.10.10.10/ -o /dev/null -w "web_http=%{http_code}\n"; echo "ISO-PING:"; ping -c2 -W2 8.8.8.8 2>&1 | tail -2; echo "ISO-DNSPUB:"; nslookup google.com 2>&1 | tail -2; echo "ISO-DNSLAB:"; nslookup web01.lab.local 2>&1 | tail -2'
o=$(jrun "$USER_KALI@10.10.30.10" "$PASS_KALI" "$GEN")
rec "    ${o//$'\n'/$'\n'    }"
if ! echo "$o" | grep -q "web_http="; then
  FAIL "generator attacker TIDAK berjalan (SSH ke attacker gagal / VM attacker mati). Langkah 5 & 6 tak bisa dinilai valid."
else
  echo "$o" | grep -q "ping 10.10.10.10 OK" && PASS "trafik segmen server tergenerate" || FAIL "ping srv-web gagal dari attacker"
  echo "$o" | grep -q "ping 10.10.20.20 OK" && PASS "trafik segmen client tergenerate" || FAIL "ping client-1 gagal dari attacker"
  if echo "$o" | grep -qiE "Network is unreachable|100% packet loss|100.0% packet loss"; then PASS "ISOLASI: internet (8.8.8.8) TIDAK terjangkau"; else FAIL "ISOLASI: 8.8.8.8 TERJANGKAU dari attacker — periksa"; fi
  rec "  (catatan: cek baris ISO-DNSLAB di atas — web01.lab.local harus resolve ke 10.10.10.10)"
fi

# ---------- 6. sensor menangkap 3 segmen (ukuran bertambah) ----------
rec ""
rec "## 6. Sensor menangkap 3 segmen (ukuran pcap bertambah)"
sleep 6
for i in enp0s8 enp0s9 enp0s10; do
  POST=$(drun "$USER_SEN@192.168.56.20" "$PASS_SEN" "f=\$(ls -t /var/log/pcap/$i/*.pcap 2>/dev/null | head -1); stat -c%s \"\$f\" 2>/dev/null || echo 0")
  POST=${POST//[!0-9]/}; POST=${POST:-0}
  rec "    post $i: $POST byte (pre ${PRE[$i]})"
  if [ "$POST" -gt "${PRE[$i]}" ]; then PASS "$i: pcap bertambah -> menangkap trafik"; else FAIL "$i: pcap TIDAK bertambah (segmen ini tak tertangkap?)"; fi
done

# ---------- ringkasan ----------
rec ""
rec "## RINGKASAN"
rec "Total error: $ERR / 6"
if [ "$ERR" -eq 0 ]; then rec "SEMUA PASS — isolasi & baseline sensor (Linux phase) VALID."; else rec "Ada $ERR temuan FAIL — lihat detail di atas."; fi
rec ""
rec "## Lanjutan MANUAL (opsional, butuh sudo di sensor) — bukti flow terekstrak:"
rec "  ssh sensor@192.168.56.20"
rec "  sudo -s"
rec "  P=\$(ls -t /var/log/pcap/enp0s8/*.pcap | head -1)"
rec "  mkdir -p /tmp/zk && cd /tmp/zk && /opt/zeek/bin/zeek -r \"\$P\" local && head -5 conn.log"
rec "  argus -r \"\$P\" -w /tmp/t.argus -P 0 && ra -M nomar -r /tmp/t.argus -c , -s stime,proto,saddr,daddr,state | head -5"
rec "  tail -3 /var/log/suricata/eve.json"

echo; echo "Laporan: $RPT"; cat "$RPT"
