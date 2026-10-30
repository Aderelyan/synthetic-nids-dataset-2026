# Phase 6 — Validasi Isolasi & Baseline (SELESAI 2026-10-07: Linux + Windows)

Validasi pra-eksekusi skenario: (A) isolasi lab dari internet + antar-segmen,
(B) baseline sensor benar-benar menangkap trafik di 3 segmen intnet.
Dilakukan per-fase (Linux & Windows) karena client-1/2 dan win-client tidak
pernah menyala bersamaan.

Skrip (host-side, READ-ONLY selain nyala/mati VM; penghitung 6-error → STOP;
laporan otomatis): `validation/phase6-linux.sh`, `validation/phase6-windows.sh`.

## Status

| Fase | Status | Hasil |
|---|---|---|
| Linux phase | ✅ **SELESAI 2026-10-07** | `laporan-phase6-linux-20261007-110052.md` — **0 error** |
| Windows phase | ✅ **SELESAI 2026-10-07** | `laporan-phase6-windows-20261007-115032.md` — 1 FAIL (WinRM scope, sudah diperbaiki) |

## Temuan besar #1: semua VM Linux tidak punya default route (ROOT CAUSE)

Gejala awal: attacker tak bisa menjangkau segmen lain, `connect: Network is
unreachable` **langsung** di host → host memang **tidak punya `default` route**
(hanya tahu /24-nya). Bukan firewall OPNsense. Ini juga yang (keliru) tampak
seperti "isolasi internet": host tak punya jalan keluar sama sekali.

Konsekuensi: lab **belum pernah** bisa komunikasi antar-segmen — wajib untuk
semua trafik dataset (normal maupun serangan). Ketahuan tepat di Phase 6.

Konfigurasi: attacker (Kali) = NetworkManager; client-1/2, srv-file = ifupdown
(`/etc/network/interfaces`, stanza `enp0s3` tanpa `gateway`); srv-web (Ubuntu) =
netplan. Semua tanpa default route. `win-client` sudah punya gateway (Phase 4);
`sensor` sengaja tanpa (node pasif).

### Perbaikan (permanen, 2026-10-07)

| VM | Metode | Gateway |
|---|---|---|
| attacker | `nmcli con mod "Wired connection 1" ipv4.gateway 10.10.30.1` | 10.10.30.1 |
| client-1 | systemd oneshot `lab-defroute.service` | 10.10.20.1 |
| client-2 | systemd oneshot `lab-defroute.service` | 10.10.20.1 |
| srv-file | systemd oneshot `lab-defroute.service` | 10.10.10.1 |
| srv-web | systemd oneshot `lab-defroute.service` | 10.10.10.1 |

`lab-defroute.service` (oneshot, `After/Wants=network-online.target`):
`ExecStart=/usr/sbin/ip route replace default via <gw>`, `RemainAfterExit=yes`.
Dipilih seragam untuk client/srv (idempoten, tak menyentuh config jaringan asli
yang beda-beda, mudah dibatalkan `systemctl disable`); attacker pakai nmcli native.

Isolasi internet tetap utuh: OPNsense tak punya WAN. `ping 8.8.8.8` kini `100%
packet loss`, DNS publik SERVFAIL. **OPNsense tidak diubah** (routing antar-interface
sudah benar; `ttl=63` membuktikan 1 hop router).

### ⚠️ Kambuh di srv-web (2026-10-14) + hardening netplan

Saat capture Linux hari-1 (2026-10-14) srv-web **lagi-lagi tanpa default route**
(`ip route` cuma /24 lokal + docker0; `ping 10.10.30.10` → `Network is unreachable`)
→ S04 (SQLi) gagal, `http 000` dari attacker walau DVWA `Up`. `lab-defroute.service`
untuk srv-web **tak efektif** pada golden yang aktif saat itu (kemungkinan service
tak ter-enable di golden yang kebetulan dijalankan, atau gagal timing
`network-online`). srv-file (.11) — yang sama-sama pakai service — tetap punya rute,
jadi scenario ke .11 (S02/S08/S10) normal; hanya srv-web terdampak.

**Hardening:** rute srv-web ditanam langsung di **netplan** (level boot
systemd-networkd, independen dari `lab-defroute.service`) → lihat
`phase3-linux-servers-srv-web.md` §11. Dengan ini default route srv-web tak lagi
bergantung service oneshot. Divalidasi dari attacker `http 200`, lalu **re-golden
srv-web offline** (UUID baru di tabel golden bawah).

## Temuan besar #2: WinRM 5985 difirewall ke Local Subnet (blok S06)

Phase 6 Windows: dari attacker, port **5985 closed** padahal 3389/445 OPEN.
Sebab: aturan firewall default **WinRM-HTTP-In hanya mengizinkan Local Subnet**;
attacker beda segmen (10.10.30.x) → ditolak. Ini akan memblokir **S06 (WinRM
lateral movement)** karena attacker memang di segmen berbeda.

### Perbaikan (win-client, via RDP PowerShell, 2026-10-07)
```powershell
Get-NetFirewallRule -DisplayGroup "Windows Remote Management" | Set-NetFirewallRule -RemoteAddress Any
Set-Service WinRM -StartupType Automatic; Start-Service WinRM
```
Diverifikasi dari dalam Windows: `ping 10.10.10.10` → Reply (inter-segmen OK),
`ping 8.8.8.8` → gagal (isolasi utuh). Dari attacker: 5985 OPEN + nxc winrm OK.
win-client golden diambil ulang setelah perbaikan ini.

## Perbaikan sampingan (Linux phase)

- **DVWA (srv-web):** container `dvwa` sempat `Exited (137)`. Diperbaiki:
  `docker update --restart unless-stopped dvwa` + start. Kini `Up`, http `302`.
  **2026-10-15:** ditemukan container `Up` tapi apache/mysql **tak melayani** :80 setelah
  host reboot (`connection refused` lokal & dari attacker) — `--restart` saja tak cukup.
  Fix permanen: **`dvwa-ensure.service`** (boot-time, `infra/install/dvwa-ensure.{sh,service}`)
  yang poll `:80` dan `docker restart dvwa` bila belum melayani. Terverifikasi lintas-reboot
  (`VBoxManage controlvm srv-web reset` → attacker `http 200` tanpa intervensi) → di-bake golden.
- **journald srv-file:** dibuat persisten (`/var/log/journal`).

## Golden snapshot — tabel OTORITATIF (live `VBoxManage snapshot list`, 2026-10-09; srv-web di-update 2026-10-14)

Sumber kebenaran tunggal untuk UUID golden = daftar live di host. Menggantikan
nilai di dokumen lain (`blueprint-v3-updated.md` §5, `phase3-*-attacker.md`) bila
berbeda.

| VM | Golden UUID | Perubahan terakhir |
|---|---|---|
| router-opnsense | `aff872ec-1a0b-4aab-8b78-fa5c7efd74e4` | 2026-10-06 |
| srv-web | `f389a32f-a94f-469f-b3f2-39af5365e4a2` | **2026-10-15 (dvwa-ensure.service + netplan route; TERVERIFIKASI lintas-reboot)** — supersede `a6e88dfb`→`07a55c0f` |
| srv-file | `8dc66325-fd15-4d5e-a29a-4ed60d590487` | **2026-10-08 (install iodined)** — supersede `59fe7ba9` |
| client-1 | `8987bd93-2ca1-46fc-a831-947e60008946` | 2026-10-07 (gateway) |
| client-2 | `a881dd51-9b7f-4976-a88d-d9608e6ed6f3` | 2026-10-07 (gateway) |
| win-client | `9c0d4eab-2f3c-43e9-a897-c673a6e67af5` | **2026-10-09 (WinRM scope fix)** |
| attacker | `47060ef0-89dd-4113-95d7-fc402cccfd6a` | **2026-10-09 (sshpass + NOPASSWD + scenarios)** — supersede `f3c4067d`→`423dc313` |
| sensor | `2aade3df-a88e-46d6-96a6-c68b1de619d8` | 2026-10-06 |

> Catatan: UUID golden berubah tiap re-bake. Selalu anggap `VBoxManage snapshot <vm> list`
> di host sebagai sumber kebenaran, bukan nilai historis. Golden srv-web **terkini = `f389a32f`**.
> Jangan pakai yang lama: `07a55c0f` (tanpa default route) RUSAK; `a6e88dfb` (route OK, tapi DVWA
> bisa gagal melayani :80 pasca-reboot) usang — hanya `f389a32f` yang lengkap (route + dvwa-ensure).

## Checklist — LULUS

Linux phase:
- [x] Isolasi NIC 8/8 (tak ada nat/bridged)
- [x] Phase switching (win-client mati)
- [x] journald persisten (srv-file)
- [x] Sensor `pcap-capture@{enp0s8,enp0s9,enp0s10}` 3/3 aktif
- [x] Inter-segmen: attacker→srv-web/srv-file/client-1/client-2 reachable
- [x] DVWA melayani (http 302)
- [x] Isolasi internet (8.8.8.8 gagal, DNS publik gagal, DNS lab resolve)
- [x] Sensor menangkap trafik di ketiga segmen (pcap bertambah)

Windows phase:
- [x] Isolasi NIC 8/8
- [x] Phase switching (client-1/2 mati, win-client nyala & reachable)
- [x] Port RDP 3389 & SMB 445 terbuka
- [x] WinRM 5985 terbuka setelah scope diperbaiki (prasyarat S06)
- [x] win-client → srv-web reachable; win-client → 8.8.8.8 terisolasi
- [x] Sensor enp0s9 menangkap trafik Windows

## Lab siap untuk Phase 7 (eksekusi 12 skenario)

Lanjutan Phase 7 dipindah ke `docs/phase7-scenario-execution.md`. Ringkas status:
- ✅ `iodined` terpasang di srv-file (S09) — golden srv-file `8dc66325` (10-08).
- ✅ `sshpass` + NOPASSWD + `~/scenarios` ter-bake di attacker (S08/S12) — golden
  attacker `47060ef0` (10-09).
- ✅ S01 dry-run end-to-end terverifikasi (no leakage) — lihat phase7 doc.
- ✅ srv-web default-route (netplan) + DVWA auto-serve (`dvwa-ensure.service`) di-hardening & terverifikasi lintas-reboot → re-golden `f389a32f` (10-15; supersede `a6e88dfb`).
- ⏳ Smoke-test batch Linux (cek error per skrip) & capture penuh — in progress.
- ⬜ Pipeline CSV final 49 kolom + label — belum dibangun (lihat phase7 doc §GAP).
