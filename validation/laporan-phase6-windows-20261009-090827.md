# Laporan Phase 6 (Windows phase) — Isolasi + Baseline Sensor

Dibuat (UTC): 2026-10-09 09:08:27Z

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
    pre enp0s9: 35307 byte

## 4. Trafik attacker->win-client + cek dari dalam Windows
    -- ping win --
    PING 10.10.20.50 (10.10.20.50) 56(84) bytes of data.
    64 bytes from 10.10.20.50: icmp_seq=1 ttl=127 time=0.742 ms
    64 bytes from 10.10.20.50: icmp_seq=2 ttl=127 time=1.33 ms
    64 bytes from 10.10.20.50: icmp_seq=3 ttl=127 time=3.20 ms
    
    --- 10.10.20.50 ping statistics ---
    3 packets transmitted, 3 received, 0% packet loss, time 2006ms
    rtt min/avg/max/mdev = 0.742/1.758/3.201/1.048 ms
    -- ports --
    port 445 OPEN
    port 3389 OPEN
    port 5985 OPEN
  PASS: attacker->win-client ping OK (trafik segmen client)
  PASS: RDP 3389 terbuka
  PASS: SMB 445 terbuka
  PASS: WinRM 5985 terbuka
    -- dari dalam win-client via WinRM (nxc): reach server + isolasi internet --
    [win->srv-web] WINRM                    10.10.20.50     5985   WIN-CLIENT       [*] Windows 11 / Server 2025 Build 26100 (name:WIN-CLIENT) (domain:win-client) 
    WINRM                    10.10.20.50     5985   WIN-CLIENT       [+] win-client\admin_lab:Admin@2024 (Pwn3d!)
    WINRM                    10.10.20.50     5985   WIN-CLIENT       [+] Executed command (shell type: cmd)
    WINRM                    10.10.20.50     5985   WIN-CLIENT       
    WINRM                    10.10.20.50     5985   WIN-CLIENT       Pinging 10.10.10.10 with 32 bytes of data:
    WINRM                    10.10.20.50     5985   WIN-CLIENT       Reply from 10.10.10.10: bytes=32 time=1ms TTL=63
    WINRM                    10.10.20.50     5985   WIN-CLIENT       Reply from 10.10.10.10: bytes=32 time<1ms TTL=63
    WINRM                    10.10.20.50     5985   WIN-CLIENT       
    WINRM                    10.10.20.50     5985   WIN-CLIENT       Ping statistics for 10.10.10.10:
    WINRM                    10.10.20.50     5985   WIN-CLIENT           Packets: Sent = 2, Received = 2, Lost = 0 (0% loss),
    WINRM                    10.10.20.50     5985   WIN-CLIENT       Approximate round trip times in milli-seconds:
    WINRM                    10.10.20.50     5985   WIN-CLIENT           Minimum = 0ms, Maximum = 1ms, Average = 0ms
    [win->8.8.8.8] WINRM                    10.10.20.50     5985   WIN-CLIENT       [*] Windows 11 / Server 2025 Build 26100 (name:WIN-CLIENT) (domain:win-client) 
    WINRM                    10.10.20.50     5985   WIN-CLIENT       [+] win-client\admin_lab:Admin@2024 (Pwn3d!)
    WINRM                    10.10.20.50     5985   WIN-CLIENT       [+] Executed command (shell type: cmd)
  PASS: win-client -> srv-web reachable (inter-segmen Windows OK)
  PASS: ISOLASI: win-client tak bisa reach 8.8.8.8

## 5. Sensor enp0s9 menangkap trafik Windows (ukuran bertambah)
    post enp0s9: 107608 byte (pre 35307)
  PASS: enp0s9 bertambah -> sensor menangkap trafik Windows

## RINGKASAN
Total error: 0 / 6
SEMUA PASS — isolasi & baseline sensor (Windows phase) VALID.
