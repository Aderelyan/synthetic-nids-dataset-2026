# Laporan Phase 6 (Windows phase) — Isolasi + Baseline Sensor

Dibuat (UTC): 2026-10-09 08:53:42Z

## 1. Sapuan isolasi NIC (host)
  PASS: router-opnsense: hanya intnet/hostonly/none
  PASS: srv-web: hanya intnet/hostonly/none
  PASS: srv-file: hanya intnet/hostonly/none
  PASS: client-1: hanya intnet/hostonly/none
  PASS: client-2: hanya intnet/hostonly/none
  PASS: win-client: hanya intnet/hostonly/none
  PASS: attacker: hanya intnet/hostonly/none
  PASS: sensor: hanya intnet/hostonly/none

## 2. Phase switch: win-client ON, client-1/2 OFF
    menunggu boot 75s...
  PASS: client-1 mati (phase switching benar)
  PASS: client-2 mati (phase switching benar)
  PASS: win-client nyala
    menunggu win-client reachable dari attacker...
  PASS: win-client reachable (routing Windows OK)

## 3. Sensor capture aktif + ukuran enp0s9 awal
    enp0s9 is-active: active 
  PASS: tcpdump enp0s9 active
    pre enp0s9: 31135 byte

## 4. Trafik attacker->win-client + cek dari dalam Windows
    -- ping win --
    PING 10.10.20.50 (10.10.20.50) 56(84) bytes of data.
    64 bytes from 10.10.20.50: icmp_seq=1 ttl=127 time=0.439 ms
    64 bytes from 10.10.20.50: icmp_seq=2 ttl=127 time=2.20 ms
    64 bytes from 10.10.20.50: icmp_seq=3 ttl=127 time=1.08 ms
    
    --- 10.10.20.50 ping statistics ---
    3 packets transmitted, 3 received, 0% packet loss, time 2024ms
    rtt min/avg/max/mdev = 0.439/1.240/2.203/0.729 ms
    -- ports --
    port 445 OPEN
    port 3389 OPEN
    port 5985 closed
  PASS: attacker->win-client ping OK (trafik segmen client)
  PASS: RDP 3389 terbuka
  PASS: SMB 445 terbuka
  (catatan: WinRM 5985 tak terdeteksi terbuka)
    -- dari dalam win-client via WinRM (nxc): reach server + isolasi internet --
    [win->srv-web] 
    [win->8.8.8.8] 
  FAIL (1/6): WinRM (nxc) tak menghasilkan output ping — cek kredensial win / WinRM. Langkah dalam-Windows tak bisa dinilai.

## 5. Sensor enp0s9 menangkap trafik Windows (ukuran bertambah)
    post enp0s9: 37601 byte (pre 31135)
  PASS: enp0s9 bertambah -> sensor menangkap trafik Windows

## RINGKASAN
Total error: 1 / 6
Ada 1 temuan FAIL — lihat detail di atas.
