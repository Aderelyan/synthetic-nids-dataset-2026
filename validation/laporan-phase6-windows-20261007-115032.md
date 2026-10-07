# Laporan Phase 6 (Windows phase) — Isolasi + Baseline Sensor

Dibuat (UTC): 2026-10-07 11:50:32Z

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
    pre enp0s9: 51531 byte

## 4. Trafik attacker->win-client + cek dari dalam Windows
    -- ping win --
    PING 10.10.20.50 (10.10.20.50) 56(84) bytes of data.
    64 bytes from 10.10.20.50: icmp_seq=1 ttl=127 time=0.674 ms
    64 bytes from 10.10.20.50: icmp_seq=2 ttl=127 time=0.847 ms
    64 bytes from 10.10.20.50: icmp_seq=3 ttl=127 time=1.68 ms
    
    --- 10.10.20.50 ping statistics ---
    3 packets transmitted, 3 received, 0% packet loss, time 2245ms
    rtt min/avg/max/mdev = 0.674/1.067/1.681/0.439 ms
    -- ports --
    port 445 OPEN
    port 3389 OPEN
    port 5985 closed
  PASS: attacker->win-client ping OK (trafik segmen client)
  PASS: RDP 3389 terbuka
  PASS: SMB 445 terbuka
  (catatan: WinRM 5985 tak terdeteksi terbuka)
    -- dari dalam win-client via WinRM (nxc): reach server + isolasi internet --
    [win->srv-web] [*] First time use detected
    [*] Creating home directory structure
    [*] Creating missing folder logs
    [*] Creating missing folder modules
    [*] Creating missing folder workspaces
    [*] Creating missing folder obfuscated_scripts
    [*] Creating missing folder screenshots
    [*] Creating missing folder logs/sam
    [*] Creating missing folder logs/lsa
    [*] Creating missing folder logs/ntds
    [*] Creating missing folder logs/dpapi
    [*] Creating default workspace
    [*] Initializing VNC protocol database
    [*] Initializing SSH protocol database
    [*] Initializing WINRM protocol database
    [*] Initializing RDP protocol database
    [*] Initializing SMB protocol database
    [*] Initializing WMI protocol database
    [*] Initializing LDAP protocol database
    [*] Initializing FTP protocol database
    [*] Initializing NFS protocol database
    [*] Initializing MSSQL protocol database
    [*] Copying default configuration file
    [win->8.8.8.8] 
  FAIL (1/6): WinRM (nxc) tak menghasilkan output ping — cek kredensial win / WinRM. Langkah dalam-Windows tak bisa dinilai.

## 5. Sensor enp0s9 menangkap trafik Windows (ukuran bertambah)
    post enp0s9: 58117 byte (pre 51531)
  PASS: enp0s9 bertambah -> sensor menangkap trafik Windows

## RINGKASAN
Total error: 1 / 6
Ada 1 temuan FAIL — lihat detail di atas.
