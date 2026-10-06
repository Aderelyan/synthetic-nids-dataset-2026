# Phase 4 — Windows Client Provisioning (SELESAI — dieksekusi 2026-10-05)

> **Status: DONE.** VM `win-client` sudah di-build, dikonfigurasi, divalidasi, dan
> golden snapshot sudah diambil. Dokumen ini awalnya rencana/spec konsolidasi
> dari `blueprint-v2-windows-client.md` §1.1–1.3 + `blueprint-v3-updated.md`
> (deviation log #6) — sekarang sudah diisi dengan hasil eksekusi aktual di
> setiap bagian (ditandai dari rencana murni menjadi hasil nyata).

## 1. Spesifikasi Terkunci (v3) — Hasil Aktual

| Parameter | Nilai Rencana | Hasil Aktual | Sumber |
|---|---|---|---|
| Nama VM | win-client | **win-client** (di-rename dari default `DESKTOP-HPI81HO` via `Rename-Computer`, 2026-10-05) | v2 §1.2 |
| OS | Windows 11 IoT Enterprise LTSC 2024 (debloated) | Build `26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_IOT_LTSC_EVAL_x64FRE_en-us` (EVAL — berlaku ~90 hari, lihat CAVEAT §8) | v2 §1.1 |
| vCPU | 2 | 2 ✅ | v3 §2 |
| RAM | 4096 MB | 4096 MB ✅ | v3 §2 |
| Disk | 60 GB | 60 GB ✅ | v3 §2 |
| NIC 1 | intnet-client, IP statis 10.10.20.50/24, gateway 10.10.20.1 | ✅ — nama adapter Windows: **`Ethernet 2`** (MAC `08-00-27-52-44-4D`), dikonfirmasi cross-reference MAC vs `VBoxManage showvminfo` | v2 §1.3, v3 §2 |
| NIC 2 | **hostonly** (RDP/mgmt langsung dari host) — dikunci 2026-10-01 | ✅ — nama adapter Windows: **`Ethernet`** (MAC `08-00-27-56-71-63`), IP **192.168.56.50/24 (tanpa gateway)** — IP dikunci 2026-10-05 saat eksekusi | v3 deviation log #6 |
| Chipset | PIIX3 default cukup | ✅ dikonfirmasi — `nic1="intnet"`, `nic2="hostonly"`, `nic3`–`nic8="none"` | — |
| Workgroup | `LABWORKGROUP` (tanpa Active Directory) | ✅ dikonfirmasi via `(Get-CimInstance Win32_ComputerSystem).Workgroup` | v2 §1.3 |

**Catatan penting — mapping NIC Windows ↔ VirtualBox tidak bisa diasumsikan dari urutan nama.**
Windows menamai NIC `Ethernet` dan `Ethernet 2` tanpa jaminan urutan ini cocok
dengan `nic1`/`nic2` di VirtualBox (pola yang sama persis seperti masalah PCI
slot non-sequential di sensor — lihat `blueprint-v3-updated.md` deviation log
#13). Cara pasti: cross-reference MAC address dari kedua sisi:

```powershell
# Di dalam VM
Get-NetAdapter | Format-Table Name, MacAddress
```
```cmd
:: Di host
VBoxManage showvminfo "win-client" --machinereadable | findstr /I "macaddress"
```

Hasil aktual: `macaddress1` (NIC1/intnet-client) = `08002752444D` → cocok
`Ethernet 2`. `macaddress2` (NIC2/hostonly) = `080027567163` → cocok
`Ethernet`. **Urutan ini terbalik dari asumsi awal dokumen** (yang menulis
`"Ethernet"` untuk NIC1) — sudah dikoreksi di §4.

## 2. Provisioning VM (perintah aktual)

Mengikuti pola `createvm`/`modifyvm` yang dipakai di Phase 1 dan Phase 5
(lihat `phase1-network-setup.md` §7, `phase5-sensor.md` §1):

```cmd
VBoxManage createvm --name "win-client" --ostype "Windows11_64" --register
VBoxManage modifyvm "win-client" --cpus 2 --memory 4096 --firmware bios
VBoxManage modifyvm "win-client" --nic1 intnet --intnet1 "intnet-client"
VBoxManage modifyvm "win-client" --nic2 hostonly --hostonlyadapter2 "VirtualBox Host-Only Ethernet Adapter"
VBoxManage createmedium disk --filename "C:\Users\Aderelyan\VirtualBox VMs\win-client\win-client.vdi" --size 61440 --variant Standard
VBoxManage storagectl "win-client" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "win-client" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\Aderelyan\VirtualBox VMs\win-client\win-client.vdi"
VBoxManage storagectl "win-client" --name "IDE" --add ide
VBoxManage storageattach "win-client" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_IOT_LTSC_EVAL_x64FRE_en-us.iso"
VBoxManage modifyvm "win-client" --boot1 dvd --boot2 disk --boot3 none --boot4 none
```

Konfirmasi final NIC (`VBoxManage showvminfo "win-client" --machinereadable | findstr nic`):
```
nic1="intnet"
nictype1="82540EM"
nic2="hostonly"
nictype2="82540EM"
nic3="none"  (dst. — tidak ada NAT NIC sisa, tidak perlu dilepas sebelum Phase 6)
```

**Setup OOBE:** instalasi Windows Setup minta "connect to network" sebelum bisa
lanjut ke desktop (expected — VM ini isolated, tanpa NAT temp). Bypass pakai
link **"I don't have internet" → "Continue with limited setup"** di layar
tersebut (alternatif: `Shift+F10` lalu `oobe\bypassnro` dari command prompt).

Guest Additions: ✅ sudah di-install (via *Devices → Insert Guest Additions
CD* di menu VirtualBox).

## 3. Debloating (PowerShell, pasca-install, sebagai Administrator) — Hasil Aktual

```powershell
DISM /Online /Disable-Feature /FeatureName:Internet-Explorer-Optional-amd64 /NoRestart
DISM /Online /Disable-Feature /FeatureName:WindowsMediaPlayer /NoRestart

$svc_off = @('DiagTrack','dmwappushservice','SysMain','WSearch','XblAuthManager')
$svc_off | ForEach-Object { Stop-Service $_ -Force -EA SilentlyContinue
                             Set-Service $_ -StartupType Disabled -EA SilentlyContinue }

Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2
```

**Hasil aktual:**
| Step | Hasil |
|---|---|
| `Disable-Feature Internet-Explorer-Optional-amd64` | ❌ **Error 0x800f080c "Feature name is unknown"** — build Windows 11 IoT LTSC 2024 ini sudah **tidak membawa legacy IE sama sekali** (feature-nya sudah dihapus dari image, bukan cuma perlu di-disable). Bukan kegagalan eksekusi — deviation yang aman diabaikan. |
| `Disable-Feature WindowsMediaPlayer` | ✅ "The operation completed successfully" |
| 5 service di-disable (`DiagTrack`, dst.) | ✅ tidak ada error |
| Visual effects → performance mode | ✅ |

> Catatan: `infra/windows/debloat-ltsc2024.ps1` sudah diisi 2026-10-05 —
> berisi script di atas tanpa baris IE yang tidak applicable.

## 4. Jaringan, Workgroup & Akun Lokal — Hasil Aktual

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.10.20.50 -PrefixLength 24 -DefaultGateway 10.10.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses 10.10.20.1

New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.56.50 -PrefixLength 24

Add-Computer -WorkgroupName "LABWORKGROUP" -Restart

New-LocalUser -Name "labuser" -Password (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force) -FullName "Lab User"
New-LocalUser -Name "admin_lab" -Password (ConvertTo-SecureString "Admin@2024" -AsPlainText -Force) -FullName "Lab Admin"
Add-LocalGroupMember -Group "Administrators" -Member "admin_lab"

Rename-Computer -NewName "win-client" -Restart
```

> **Koreksi penting dari rencana awal:** dokumen semula menulis
> `-InterfaceAlias "Ethernet"` untuk NIC1 (intnet-client) — ini **salah**,
> lihat mapping MAC di §1. Alias yang benar untuk NIC1/intnet-client adalah
> **`"Ethernet 2"`**, dan NIC2/hostonly adalah **`"Ethernet"`**.

**Hasil aktual:**
```
PS> ipconfig /all
Ethernet 2: 10.10.20.50/24, Gateway 10.10.20.1   — OK
Ethernet:   192.168.56.50/24, no gateway          — OK
PS> hostname
win-client
PS> (Get-CimInstance Win32_ComputerSystem).Workgroup
LABWORKGROUP
```

Kredensial (`P@ssw0rd123`, `Admin@2024`) sudah ditulis apa adanya di
`blueprint-v2-windows-client.md` sebagai akun sintetis khusus lab terisolasi
(target brute force/credential dumping) — bukan kredensial produksi apa pun.

## 5. NTP Setup (Windows-specific) — baru, dieksekusi 2026-10-05

Windows pakai mekanisme sendiri (`W32Time`), bukan `systemd-timesyncd` seperti
VM Linux lain (lihat `phase2-opnsense-setup.md` §11). Ini **tidak otomatis
ikut** saat NTP server OPNsense dibangun 2026-10-03, karena `win-client`
belum ada saat itu — jadi perlu dikonfigurasi terpisah.

```powershell
# W32Time default-nya StartupType Manual & belum pernah di-trigger
Set-Service W32Time -StartupType Automatic
Start-Service W32Time

w32tm /config /manualpeerlist:"10.10.20.1" /syncfromflags:manual /reliable:NO /update
Restart-Service W32Time
w32tm /resync /force
w32tm /query /status
```

> **[RIWAYAT — gejala bug router, JANGAN DIULANG] (ditandai 2026-10-06)**
> Offset +25197 detik dan langkah `Set-Date` di bawah ini adalah catatan
> kejadian 2026-10-05, bukan prosedur. Offset ~7 jam itu bukan sifat lab,
> melainkan akibat bug VirtualBox: VM `router-opnsense` memakai
> `rtcuseutc=off`, sehingga jam WIB host dibaca OPNsense sebagai UTC (jam
> router maju 7 jam). Dibetulkan 2026-10-06 dengan
> `VBoxManage modifyvm "router-opnsense" --rtcuseutc on` — lihat
> `phase2-opnsense-setup.md` §11. Jam lab sekarang = UTC asli, jadi offset
> sebesar ini tidak akan muncul lagi dan `Set-Date` manual tidak diperlukan.
> Kalau offset besar muncul lagi, periksa `rtcuseutc` router dulu.

**Riwayat (2026-10-05) — "large phase offset" membuat `/resync` gagal silent:**
Clock VM baru (`win-client`) berselisih besar dari clock OPNsense
(`10.10.20.1`) — offset terukur **+25197.7 detik (~7 jam)**, konsisten di
setiap pengukuran `w32tm /stripchart`. `W32Time` Windows menolak melakukan
*step correction* otomatis untuk offset sebesar ini (`LargePhaseOffset`
threshold default ~5 detik memicu "spike watch" yang menahan koreksi besar
tanpa pesan error yang jelas — `/resync` terus melaporkan "no time data
available" walau `Source`/`Last Successful Sync Time` di `/query /status`
menunjukkan komunikasi ke server sebenarnya berhasil).

**Fix saat itu (riwayat, jangan diulang):** set manual jam lokal mendekati target (pakai offset hasil
`stripchart`), baru `/resync` — ini membawa selisih ke bawah threshold
spike-watch sehingga sync berjalan normal:

```powershell
$offset = 25197.714   # dari w32tm /stripchart /computer:10.10.20.1 /samples:3 /dataonly
Set-Date -Date (Get-Date).AddSeconds($offset)
w32tm /resync /force
w32tm /query /status
```

**Hasil akhir (2026-10-05):**
```
Leap Indicator: 0(no warning)
Stratum: 12 (secondary reference - syncd by (S)NTP)
Root Dispersion: 7.79s (menyusut lebih lanjut seiring polling berikutnya)
ReferenceId: 0x0A0A1401 (source IP: 10.10.20.1)
Source: 10.10.20.1
```

> **Status jam per 2026-10-06:** jam `win-client` = UTC asli, sama dengan 7 VM
> lain. Jam 8 VM dicek ulang 2026-10-06 dan semuanya cocok dengan UTC host
> (selisih hanya hitungan detik). Sumber waktu tetap OPNsense (`10.10.20.1`).

## 6. Layanan untuk Skenario Serangan (SMB, WinRM, RDP, Firewall Logging) — Hasil Aktual

```powershell
# SMB Share (untuk S-07, S-10 lateral movement/ransomware sim)
New-Item -Path "C:\LabData" -ItemType Directory -Force
New-SmbShare -Name "LabShare" -Path "C:\LabData" -FullAccess "labuser","admin_lab"

# Network profile harus Private dulu — Public memblokir WinRM/RDP firewall exception
Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
Set-NetConnectionProfile -InterfaceAlias "Ethernet 2" -NetworkCategory Private

# WinRM (untuk S-06)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# RDP (untuk S-05, sekaligus dipakai sebagai mgmt channel menggantikan console VirtualBox)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Firewall logging (untuk dataset — pfirewall.log)
Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -LogMaxSizeKilobytes 4096 -LogAllowed True -LogBlocked True
```

**Known issues & fix selama eksekusi:**

| Issue | Penyebab | Fix |
|---|---|---|
| `Enable-PSRemoting -Force` error "WinRM firewall exception will not work since one of the network connection types on this machine is set to Public" | NIC di VM intnet/hostonly otomatis kedetect `Public` oleh Windows (tidak bisa identifikasi domain controller/gateway dikenal) | `Set-NetConnectionProfile -NetworkCategory Private` untuk kedua NIC, baru ulangi `Enable-PSRemoting -Force` |
| `New-SmbShare` error "The name has already been shared" | Share `LabShare` sudah ke-create otomatis dari percobaan sebelumnya yang gagal di tengah (bukan corrupt) | Tidak perlu fix — `Get-SmbShareAccess` konfirmasi permission `Full` untuk `labuser`+`admin_lab` sudah benar dari awal |
| `Set-NetFirewallProfile ... -LogFileName "..." \`-LogBlocked True` error "positional parameter cannot be found" | Backtick line-continuation (`` ` ``) rusak saat paste dari chat ke VM (trailing whitespace tersisip) | Tulis ulang sebagai **command satu baris** (tanpa backtick) — lihat blok command di atas |

**Hasil validasi:**
```
Get-NetConnectionProfile → Ethernet: Private, Ethernet 2: Private
fDenyTSConnections → 0
Remote Desktop firewall rules → semua Enabled: True
WinRM service → Running, StartType Automatic
Get-SmbShareAccess "LabShare" → labuser: Full, admin_lab: Full
Get-NetFirewallProfile → LogAllowed/LogBlocked True, LogFileName benar, semua 3 profile
```

RDP tervalidasi jalan — `mstsc /v:192.168.56.50` dari host berhasil connect,
dipakai sebagai mgmt channel utama menggantikan console VirtualBox untuk
sisa setup (lebih cepat, bisa paste).

> `infra/windows/enable-winrm-rdp-smb.ps1` dan `infra/windows/firewall-logging.ps1`
> sudah diisi 2026-10-05 dengan blok di atas.

## 7. Hasil Validasi Aktual

| Check | Command | Hasil Aktual |
|---|---|---|
| Isolasi — tidak ada NAT/bridged | `VBoxManage showvminfo "win-client" \| findstr nic` | ✅ hanya `nic1=intnet`, `nic2=hostonly` |
| DNS lab resolve | `nslookup web01.lab.local` | ✅ → `10.10.10.10` |
| DNS publik gagal (isolasi) | `nslookup google.com` | ✅ → `Server failed` (bukti isolasi lebih kuat dari sekadar NXDOMAIN) |
| Clock sync (W32Time) | `w32tm /query /status` | ✅ `Leap Indicator: 0`, `Source: 10.10.20.1` — lihat §5 |
| RDP terdeteksi di sensor | Zeek `conn.log` port 3389 | *(belum — nunggu sensor capture aktif di Phase 6/7)* |
| SMB terdeteksi di sensor | Zeek `smb_cmd.log` | *(belum — sama seperti di atas)* |
| WinRM terdeteksi di sensor | Zeek `conn.log` port 5985 | *(belum — sama seperti di atas)* |
| Snapshot golden dibuat | `VBoxManage snapshot "win-client" take golden` | ✅ UUID `6a291dd9-aa9b-4737-bfcd-5c2ffb7d7935` — **diambil ulang 2026-10-05 setelah NTP fix** (snapshot pertama diambil sebelum NTP dikonfigurasi, dihapus & diganti supaya golden state punya clock yang sudah sinkron). Bersamaan dengan ini, 7 VM lain juga diambil golden snapshot-nya di hari yang sama — **8/8 VM lab kini punya golden snapshot**, lihat `blueprint-v3-updated.md` §5 poin 3. |

Validasi RDP/SMB/WinRM via sensor sengaja ditunda ke Phase 6/7 — butuh sensor
capture (Zeek) aktif, bukan blocker untuk menyatakan Phase 4 selesai.

## 8. Dependensi & Urutan

- **Prasyarat:** Phase 1 (network) ✅, Phase 2 (OPNsense) ✅ — keduanya sudah selesai.
- Phase 4 **selesai 2026-10-05** — tidak lagi bergantung pada Phase 5 (sensor) untuk VM ini bisa dibuild; validasi §7 baris RDP/SMB/WinRM via sensor masih menunggu sensor capture jalan (Phase 6/7).
- Setelah Phase 4 selesai dan golden snapshot dibuat → lanjut Phase 6 (isolasi & baseline validation, diperluas ke Linux+Windows, termasuk clock-sync check) sebelum Phase 7 (eksekusi 12 skenario).

**CAVEAT:**
- OS build yang dipakai adalah **EVAL edition** (`..._CLIENT_IOT_LTSC_EVAL_...`) — biasanya expire ~90 hari dengan watermark desktop. Deadline tugas akhir 31 Okt 2026 masih jauh di bawah window itu (terhitung dari install ~5 Okt 2026), tapi dicatat sebagai risiko kalau project molor.
- Golden snapshot **harus** diambil ulang kalau ada perubahan state signifikan lagi setelah ini (mis. install tooling tambahan) — snapshot saat ini merepresentasikan state pasca-NTP-fix, pre-first-attack-scenario.
