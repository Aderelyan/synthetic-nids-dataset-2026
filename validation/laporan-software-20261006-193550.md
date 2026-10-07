# Laporan Cek Software VM (READ-ONLY)

Dibuat: 2026-10-06 12:35:50Z (UTC host)

> router-opnsense dilewati (shell OPNsense = menu). Layanan Unbound (DNS) & ntpd sudah divalidasi terpisah.
> win-client (Windows) dicek manual — lihat pesan chat.

## sensor (192.168.56.20)

```
Warning: Permanently added '192.168.56.20' (ED25519) to the list of known hosts.
bin tcpdump: OK
bin suricata: OK
bin argus: MISSING
bin ra: OK
svc suricata: active
bin zeek: OK (/opt/zeek/bin)
```

## srv-web (10.10.10.10)

```
KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual.
```

## srv-file (10.10.10.11)

```
KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual.
```

## client-1 (10.10.20.20)

```
KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual.
```

## client-2 (10.10.20.21)

```
KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual.
```

## attacker (10.10.30.10)

```
KONEKSI/LOGIN GAGAL setelah ~5 menit — cek manual.
```

## Ringkasan yang perlu dipasang (harapan awal)
- srv-file: **smbd (samba)** dan **vsftpd** → kemungkinan MISSING, memang belum dipasang.
- attacker: **iodine** (S09) dan **evil-winrm**/**nxc** (S06) → kemungkinan MISSING.
- client-1/2: **curl** → kalau MISSING, perlu untuk generator traffic normal.
- Baris bertanda MISSING / svc inactive = kandidat instalasi tahap berikutnya.
