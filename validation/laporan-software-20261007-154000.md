# Laporan Cek Software VM (READ-ONLY)

Dibuat: 2026-10-07 08:40:01Z (UTC host)

> router-opnsense dilewati (shell OPNsense = menu). Layanan Unbound (DNS) & ntpd sudah divalidasi terpisah.
> win-client (Windows) dicek manual — lihat pesan chat.

## sensor (192.168.56.20)

```
Warning: Permanently added '192.168.56.20' (ED25519) to the list of known hosts.
bin tcpdump: OK
bin suricata: OK
bin argus: OK (sbin)
bin ra: OK
svc suricata: active
bin zeek: OK (/opt/zeek/bin)
```

## srv-web (10.10.10.10)

```
Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
Warning: Permanently added '10.10.10.10' (ED25519) to the list of known hosts.
bin docker: OK
bin curl: OK
svc ssh: active
svc docker: active
catatan: container DVWA cek manual: sudo docker ps --filter name=dvwa
```

## srv-file (10.10.10.11)

```
Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
Warning: Permanently added '10.10.10.11' (ED25519) to the list of known hosts.
bin sudo: OK
bin smbd: OK (sbin)
bin vsftpd: OK (sbin)
svc ssh: active
svc rsyslog: inactive
(?)
svc smbd: active
svc vsftpd: active
```

## client-1 (10.10.20.20)

```
Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
Warning: Permanently added '10.10.20.20' (ED25519) to the list of known hosts.
bin sudo: OK
bin curl: OK
bin python3: OK
svc ssh: active
```

## client-2 (10.10.20.21)

```
Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
Warning: Permanently added '10.10.20.21' (ED25519) to the list of known hosts.
bin sudo: OK
bin curl: OK
bin python3: OK
svc ssh: active
```

## attacker (10.10.30.10)

```
Warning: Permanently added '192.168.56.10' (ED25519) to the list of known hosts.
Warning: Permanently added '10.10.30.10' (ED25519) to the list of known hosts.
bin nmap: OK
bin hydra: OK
bin hping3: OK
bin nc: OK
bin impacket-secretsdump: OK
bin pypykatz: OK
bin sqlmap: OK
bin iodine: OK
bin evil-winrm: OK
bin nxc: OK
bin crackmapexec: MISSING
```

## Ringkasan yang perlu dipasang (harapan awal)
- srv-file: **smbd (samba)** dan **vsftpd** → kemungkinan MISSING, memang belum dipasang.
- attacker: **iodine** (S09) dan **evil-winrm**/**nxc** (S06) → kemungkinan MISSING.
- client-1/2: **curl** → kalau MISSING, perlu untuk generator traffic normal.
- Baris bertanda MISSING / svc inactive = kandidat instalasi tahap berikutnya.
