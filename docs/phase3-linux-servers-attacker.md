# Phase 3 (Part 3) — Linux Server Provisioning: attacker

Dokumentasi VM `attacker`: import Kali Linux (official OVA), konfigurasi jaringan
single-NIC `intnet-attacker`, inventaris tooling serangan, dan hasil validasi
isolasi. Host: Windows, VirtualBox 7.2.12.

## 1. VM Provisioning — Import OVA

Berbeda dari srv-web/srv-file (install dari ISO), `attacker` diprovision dengan
**import OVA resmi Kali Linux** (bukan `createvm`/`modifyvm` dari nol):

```cmd
VBoxManage import "C:\ISO\kali-linux-<versi>-virtualbox-amd64.ova" --vsys 0 --vmname "attacker"
VBoxManage modifyvm "attacker" --memory 4096 --cpus 2
VBoxManage modifyvm "attacker" --nic1 intnet --intnet1 "intnet-attacker"
```

**Konfirmasi aktual** (`VBoxManage showvminfo "attacker" --machinereadable`):

```
memory=4096
cpus=2
nic1="intnet"
intnet1="intnet-attacker"
nictype1="82540EM"
nic2="none"  (dst. — hanya 1 NIC, tidak ada NIC temporary NAT)
```

Tidak seperti srv-web/srv-file/client-1/client-2, `attacker` **tidak memakai NIC
NAT sementara** untuk instalasi — OVA Kali sudah membawa seluruh tooling
offensive bawaan sejak awal, sehingga tidak perlu `apt install` tambahan lewat
internet saat provisioning.

## 2. OS & Kernel

```
PRETTY_NAME="Kali GNU/Linux Rolling"
VERSION_ID="2026.2"
VERSION_CODENAME=kali-rolling
```
```
Linux attacker 6.19.14+kali-amd64 #1 SMP PREEMPT_DYNAMIC Kali 6.19.14-1+kali1 (2026-05-05) x86_64 GNU/Linux
```

## 3. Jaringan

Single-NIC, static, tanpa default route ke luar (konsisten dengan prinsip
isolasi — lihat `topology.md`):

```
eth0: 10.10.30.10/24 brd 10.10.30.255
```

```bash
ip route
# 10.10.30.0/24 dev eth0 proto kernel scope link src 10.10.30.10 metric 100
```

Tidak ada baris `default via ...` sama sekali — berbeda dari pola srv-web/srv-file
yang masih punya default route lewat NIC NAT temporary saat tahap ini. Konfirmasi
kuat untuk isolasi: `ping 8.8.8.8` gagal dengan `Network is unreachable` (bukan
sekadar timeout) karena memang tidak ada default gateway ke internet sama sekali.

## 4. Validasi Konektivitas & DNS

| Check | Command | Hasil |
|---|---|---|
| Gateway reachable | `ping -c 3 10.10.30.1` | 0% loss |
| DNS lab (Unbound) | `drill attacker.lab.local` | `10.10.30.10` — resolve benar |
| Isolasi internet | `ping -c 2 8.8.8.8` | **Network is unreachable** (no default route — lebih kuat dari sekadar DNS gagal) |

## 5. Inventaris Tooling Serangan

Dibawa langsung dari OVA Kali (tidak ada instalasi tambahan manual):

| Tool | Status | Dipakai untuk |
|---|---|---|
| `nmap` | ✅ terpasang | S-01 (reconnaissance/port scanning) |
| `hydra` | ✅ terpasang | S-02, S-03, S-05 (brute force SSH/FTP/RDP, password spraying) |
| `impacket-secretsdump` (paket `impacket` 0.14.0.dev0) | ✅ terpasang | S-07 (LSASS dump / pass-the-hash) — pengganti Mimikatz, lihat `threat-references.md` S07 |
| `pypykatz` | ✅ terpasang | S-07 (alternatif/pelengkap impacket-secretsdump) |
| `hping3` | ✅ terpasang | S-11 (DoS/DDoS) |
| `nc` (netcat) | ✅ terpasang | S-12 (data exfiltration — channel netcat) |

**Catatan:** `secretsdump.py` sebagai nama file script berdiri sendiri tidak
ditemukan via `which` — tapi fungsinya tersedia lewat `impacket-secretsdump`
(wrapper resmi dari paket `impacket` yang sama persis). Dokumen lain
(`phase4-windows-client.md`, `threat-references.md` S07) yang menyebut
"`secretsdump.py`" merujuk ke tool yang sama ini, bukan tool berbeda.

## 6. Known Issues

| Issue | Status | Catatan |
|---|---|---|
| NTP inactive, clock belum tersinkronisasi | ✅ **Selesai 2026-10-03** | NTP server lokal dibangun di OPNsense (`phase2-opnsense-setup.md` §11), attacker diarahkan ke gateway `10.10.30.1`. `timedatectl` sekarang: `System clock synchronized: yes`, `NTP service: active`. (Catatan kecil: `/etc/hosts` attacker awalnya belum punya entry `127.0.1.1 attacker`, menyebabkan warning `sudo: unable to resolve host` — sudah ditambal, lihat §3.) |
| Golden snapshot belum dibuat | ✅ **Selesai 2026-10-05** | `VBoxManage snapshot "attacker" take "golden"` → UUID `423dc313-f5fe-4b10-9f24-42af1ed43fdb`. Diambil bersamaan dengan 6 VM Linux/OPNsense lain + win-client — semua 8 VM lab kini punya golden snapshot (`blueprint-v3-updated.md` §5 poin 3). |

## 7. Final Validation Results

| Check | Command | Hasil Aktual |
|---|---|---|
| Spesifikasi VM | `VBoxManage showvminfo` | 2 vCPU, 4096 MB RAM — sesuai `blueprint-v3-updated.md` §2 |
| Static IP | `ip a show eth0` | `10.10.30.10/24` |
| Tidak ada default route | `ip route` | hanya route lokal `10.10.30.0/24`, tidak ada `default via` |
| Reachability ke gateway | `ping -c 3 10.10.30.1` | 0% loss |
| DNS lab resolve | `drill attacker.lab.local` | `10.10.30.10` |
| Isolasi internet | `ping -c 2 8.8.8.8` | Network is unreachable |
| Timezone & sync | `timedatectl` | `Etc/UTC`, **synchronized: yes**, NTP service active (gateway `10.10.30.1`, fixed 2026-10-03 — lihat §6) |
| Golden snapshot | `VBoxManage snapshot "attacker" list` | ✅ `golden` — UUID `423dc313-f5fe-4b10-9f24-42af1ed43fdb` (2026-10-05) |

## 8. Notes / Pending

- Semua blocker sebelum Phase 6 untuk VM ini sudah selesai: NTP (§6) dan golden snapshot (di atas). Tidak ada item pending tersisa khusus `attacker`.
- Tidak ada "Known Issues" terkait instalasi (berbeda dari srv-web/srv-file) karena jalur OVA import melewati seluruh masalah minimal-install (dhclient, sudo, openssh-server) yang dialami VM berbasis ISO Debian/Ubuntu.
