# Laporan Phase 6 (Linux phase) — Isolasi + Baseline Sensor

Dibuat (UTC): 2026-10-07 09:49:05Z

## 1. Sapuan isolasi NIC (host)
  PASS: router-opnsense: hanya intnet/hostonly/none
  PASS: srv-web: hanya intnet/hostonly/none
  PASS: srv-file: hanya intnet/hostonly/none
  PASS: client-1: hanya intnet/hostonly/none
  PASS: client-2: hanya intnet/hostonly/none
  PASS: win-client: hanya intnet/hostonly/none
  PASS: attacker: hanya intnet/hostonly/none
  PASS: sensor: hanya intnet/hostonly/none

## 2. Nyalakan Linux phase + sensor, matikan win-client
    menunggu boot 60s...
  PASS: win-client mati (phase switching benar)
    menunggu attacker siap SSH...
    attacker siap.

## 3. journald permanen di srv-file
    [sudo] password for labadmin: /usr/lib/tmpfiles.d/vsftpd.conf:1: Line references path below legacy directory /var/run/, updating /var/run/vsftpd/empty → /run/vsftpd/empty; please update the tmpfiles.d/ drop-in file accordingly.
    Archived and active journals take up 32M in the file system.
  PASS: journald persisten aktif

## 4. Sensor capture aktif + ukuran pcap awal
    is-active: active active active 
  PASS: 3 instance tcpdump active
    pre enp0s8: 52502 byte
    pre enp0s9: 6188 byte
    pre enp0s10: 13333 byte

## 5. Trafik uji dari attacker + uji isolasi
    ping 10.10.10.10 GAGAL
    ping 10.10.10.11 GAGAL
    ping 10.10.20.20 GAGAL
    ping 10.10.20.21 GAGAL
    web_http=000
    ISO-PING:
    ping: connect: Network is unreachable
    ISO-DNSPUB:
    ** server can't find google.com: SERVFAIL
    
    ISO-DNSLAB:
    Address: 10.10.10.10
  FAIL (1/6): ping srv-web gagal dari attacker
  FAIL (2/6): ping client-1 gagal dari attacker
  PASS: ISOLASI: internet (8.8.8.8) TIDAK terjangkau
  (catatan: cek baris ISO-DNSLAB di atas — web01.lab.local harus resolve ke 10.10.10.10)

## 6. Sensor menangkap 3 segmen (ukuran pcap bertambah)
    post enp0s8: 52588 byte (pre 52502)
  PASS: enp0s8: pcap bertambah -> menangkap trafik
    post enp0s9: 6188 byte (pre 6188)
  FAIL (3/6): enp0s9: pcap TIDAK bertambah (segmen ini tak tertangkap?)
    post enp0s10: 27352 byte (pre 13333)
  PASS: enp0s10: pcap bertambah -> menangkap trafik

## RINGKASAN
Total error: 3 / 6
Ada 3 temuan FAIL — lihat detail di atas.

## Lanjutan MANUAL (opsional, butuh sudo di sensor) — bukti flow terekstrak:
  ssh sensor@192.168.56.20
  sudo -s
  P=$(ls -t /var/log/pcap/enp0s8/*.pcap | head -1)
  mkdir -p /tmp/zk && cd /tmp/zk && /opt/zeek/bin/zeek -r "$P" local && head -5 conn.log
  argus -r "$P" -w /tmp/t.argus -P 0 && ra -M nomar -r /tmp/t.argus -c , -s stime,proto,saddr,daddr,state | head -5
  tail -3 /var/log/suricata/eve.json
