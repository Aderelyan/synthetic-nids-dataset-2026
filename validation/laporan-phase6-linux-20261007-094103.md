# Laporan Phase 6 (Linux phase) — Isolasi + Baseline Sensor

Dibuat (UTC): 2026-10-07 09:41:03Z

## 1. Sapuan isolasi NIC (host)
  PASS: router-opnsense: hanya intnet/hostonly/none
  PASS: srv-web: hanya intnet/hostonly/none
  PASS: srv-file: hanya intnet/hostonly/none
  PASS: client-1: hanya intnet/hostonly/none
    nic2="natnetwork"
  FAIL (1/6): client-2: ADA NIC non-isolasi (nat/bridged/natnetwork)
  PASS: win-client: hanya intnet/hostonly/none
  PASS: attacker: hanya intnet/hostonly/none
  PASS: sensor: hanya intnet/hostonly/none

## 2. Nyalakan Linux phase + sensor, matikan win-client
    menunggu boot 45s...
  PASS: win-client mati (phase switching benar)

## 3. journald permanen di srv-file
    Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
    Warning: Permanently added '10.10.10.11' (ED25519) to the list of known hosts.
    [sudo] password for labadmin: /usr/lib/tmpfiles.d/vsftpd.conf:1: Line references path below legacy directory /var/run/, updating /var/run/vsftpd/empty → /run/vsftpd/empty; please update the tmpfiles.d/ drop-in file accordingly.
    Archived and active journals take up 32M in the file system.
  PASS: journald persisten aktif

## 4. Sensor capture aktif + ukuran pcap awal
    is-active: Warning: Permanently added '192.168.56.20' (ED25519) to the list of known hosts. active active active 
  PASS: 3 instance tcpdump active
    pre enp0s8: 19216856202551929712 byte
    pre enp0s9: 1921685620255191910 byte
    pre enp0s10: 192168562025519702 byte

## 5. Trafik uji dari attacker + uji isolasi
    Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
    Connection timed out during banner exchange
    Connection to UNKNOWN port 65535 timed out
  FAIL (2/6): ping srv-web gagal dari attacker
  FAIL (3/6): ping client-1 gagal dari attacker
  FAIL (4/6): ISOLASI BOCOR: 8.8.8.8 terjangkau dari attacker
  (catatan: verifikasi resolve DNS lab manual)

## 6. Sensor menangkap 3 segmen (ukuran pcap bertambah)
    post enp0s8: 19216856202551934991 byte (pre 19216856202551929712)
  FAIL (5/6): enp0s8: pcap TIDAK bertambah (segmen ini tak tertangkap?)
    post enp0s9: 1921685620255192340 byte (pre 1921685620255191910)
  PASS: enp0s9: pcap bertambah -> menangkap trafik
    post enp0s10: 1921685620255191092 byte (pre 192168562025519702)
  PASS: enp0s10: pcap bertambah -> menangkap trafik

## RINGKASAN
Total error: 5 / 6
Ada 5 temuan FAIL — lihat detail di atas.

## Lanjutan MANUAL (opsional, butuh sudo di sensor) — bukti flow terekstrak:
  ssh sensor@192.168.56.20
  sudo -s
  P=$(ls -t /var/log/pcap/enp0s8/*.pcap | head -1)
  mkdir -p /tmp/zk && cd /tmp/zk && /opt/zeek/bin/zeek -r "$P" local && head -5 conn.log
  argus -r "$P" -w /tmp/t.argus -P 0 && ra -M nomar -r /tmp/t.argus -c , -s stime,proto,saddr,daddr,state | head -5
  tail -3 /var/log/suricata/eve.json
