# Blueprint Lab Jaringan Virtual v2 — Integrasi Windows Client (Workgroup) + Skenario Serangan 2024–2026

> Versi 2.0 | Update dari blueprint sebelumnya | Constraint: TANPA Windows Server / Active Directory
> Semua skenario serangan berbasis paper/report 2024–2026

---

## INSTRUKSI 1: Integrasi Windows Client & Strategi Optimasi Resource

### 1.1 Pilihan OS: Windows 11 IoT Enterprise LTSC 2024

Windows 11 IoT Enterprise LTSC 2024 dipilih atas Windows 10 LTSC karena:
- **TPM dan Secure Boot tidak diwajibkan** — bisa langsung di-install di VirtualBox tanpa workaround.
- **Lifecycle 10 tahun** (support hingga 2034) — stabil untuk lab jangka panjang.
- **Strip konsumer apps bawaan** — tidak ada Microsoft Store, Cortana, OneDrive, Teams built-in; footprint RAM jauh lebih kecil.
- **Debloating resmi via DISM** didukung penuh oleh Microsoft Learn.
- Referensi resmi: [Windows IoT Enterprise — Device Optimization Overview](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/overview)

Alternatif yang lebih ringan: **Windows 10 LTSC 2021** (build lebih tua, support hingga 2027, RAM baseline lebih rendah ±600 MB vs ±900 MB untuk Windows 11).

### 1.2 Spesifikasi VM Windows Client

| Parameter | Nilai | Catatan |
|---|---|---|
| **Nama VM** | win-client | |
| **OS** | Windows 11 IoT Enterprise LTSC 2024 (debloated) | Atau Win10 LTSC 2021 |
| **vCPU** | 2 | Cukup untuk endpoint behavior simulation |
| **RAM** | 4 GB | Minimum agar Windows 11 responsif; Win10 LTSC bisa 3 GB |
| **Disk** | 60 GB (dinamis) | LTSC jauh lebih kecil dari full Windows 11 (~15 GB setelah install) |
| **NIC** | intnet-client (10.10.20.x/24) | Satu segmen dengan Linux clients |
| **NIC 2 (opsional)** | hostonly vboxnet0 | Untuk RDP/management dari host; non-mandatory |
| **VirtualBox config** | EFI disable, Guest Additions install | Guest Additions diperlukan untuk shared clipboard & drag-drop file |

**Perintah VBoxManage:**
```bash
VBoxManage createvm --name "win-client" --ostype "Windows11_64" --register
VBoxManage modifyvm "win-client" \
  --cpus 2 --memory 4096 \
  --firmware bios \
  --nic1 intnet --intnet1 "intnet-client"
VBoxManage createhd --filename "win-client.vdi" --size 61440 --variant Standard
VBoxManage storagectl "win-client" --name "SATA" --add sata
VBoxManage storageattach "win-client" --storagectl "SATA" --port 0 \
  --device 0 --type hdd --medium "win-client.vdi"
```

**Debloating pasca-install via PowerShell (dijalankan sebagai Administrator):**
```powershell
# Hapus feature tidak dibutuhkan
DISM /Online /Disable-Feature /FeatureName:Internet-Explorer-Optional-amd64 /NoRestart
DISM /Online /Disable-Feature /FeatureName:WindowsMediaPlayer /NoRestart

# Matikan service tidak diperlukan
$svc_off = @('DiagTrack','dmwappushservice','SysMain','WSearch','XblAuthManager')
$svc_off | ForEach-Object { Stop-Service $_ -Force -EA SilentlyContinue
                             Set-Service $_ -StartupType Disabled -EA SilentlyContinue }

# Matikan visual effects (hemat RAM)
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2
```

### 1.3 Konfigurasi Workgroup (tanpa Active Directory)

**DNS:** Windows client memakai resolver Unbound di OPNsense (192.168.10.1) yang sudah dikonfigurasi dengan host override domain lab lokal (`web01.lab.local`, `files01.lab.local`, dll.). Tidak ada DNS Active Directory yang dibutuhkan.

**IP dan Workgroup:**
```powershell
# Set IP statis di Windows client (PowerShell, admin)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.20.50 `
  -PrefixLength 24 -DefaultGateway 10.10.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.10.20.1

# Set Workgroup
Add-Computer -WorkgroupName "LABWORKGROUP"
```

**Local Users untuk skenario serangan:**
```powershell
# Buat user lokal (target brute force, credential dumping)
New-LocalUser -Name "labuser" -Password (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force) -FullName "Lab User"
New-LocalUser -Name "admin_lab" -Password (ConvertTo-SecureString "Admin@2024" -AsPlainText -Force) -FullName "Lab Admin"
Add-LocalGroupMember -Group "Administrators" -Member "admin_lab"
```

**SMB Share untuk lateral movement traffic:**
```powershell
New-SmbShare -Name "LabShare" -Path "C:\LabData" -FullAccess "labuser","admin_lab"
# Referensi: https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare
```

**WinRM untuk remote management / lateral movement simulation:**
```powershell
# Enable WinRM (port 5985 HTTP, 5986 HTTPS)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
# Referensi: https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management
```

**RDP enable:**
```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
  -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
# Referensi: https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/remote-desktop-allow-access
```

**Windows Defender/Firewall logging untuk dataset:**
```powershell
# Aktifkan firewall logging
Set-NetFirewallProfile -Profile Domain,Public,Private `
  -LogFileName "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" `
  -LogMaxSizeKilobytes 4096 -LogAllowed True -LogBlocked True
```

### 1.4 Strategi Phase & Manajemen RAM

**Filosofi:** tidak semua VM perlu nyala bersamaan. Bagi eksekusi lab ke dua phase berdasarkan fokus skenario.

#### Tabel Estimasi RAM Semua VM

| VM | RAM | Keterangan |
|---|---|---|
| router-opnsense | 2 GB | Selalu aktif |
| srv-web | 2 GB | Aktif di kedua phase |
| srv-file | 2 GB | Aktif di kedua phase |
| client-1 (Linux) | 3 GB | Phase Linux saja |
| client-2 (Linux) | 2 GB | Phase Linux saja |
| win-client | 4 GB | Phase Windows saja |
| attacker (Kali) | 4 GB | Aktif di kedua phase |
| sensor | 4 GB | Selalu aktif |
| **TOTAL PHASE LINUX** | **19 GB** | Tanpa win-client |
| **TOTAL PHASE WINDOWS** | **18 GB** | Tanpa client-1, client-2 |
| **Hard limit host** | 38 GB | ✅ Kedua phase jauh di bawah batas |

> **Catatan (v3):** nilai RAM di atas sudah di-update di `blueprint-v3-updated.md` §2 (OPNsense naik ke 3072 MB, total Phase Linux → 20 GB, Phase Windows → 19 GB). Tabel ini dipertahankan sebagai referensi historis v2.

#### Phase Linux (Fokus: serangan berbasis CLI, web, DNS, network-level)
**VM aktif:** router, srv-web, srv-file, client-1, client-2, attacker, sensor = **19 GB**
**Skenario:** Reconnaissance, Brute Force SSH, SQLi, DNS Tunneling, DGA C2, DoS, Reverse Shell, Lateral Movement SSH

#### Phase Windows (Fokus: serangan endpoint Windows, RDP, WinRM, SMB, Credential Dumping)
**VM aktif:** router, srv-web, srv-file, win-client, attacker, sensor = **18 GB**
**Skenario:** RDP Brute Force, WinRM Lateral Movement, SMB Lateral Movement, LSASS Credential Dumping (via pypykatz untuk analisis offline), Password Spraying ke Windows local accounts

**Script pergantian phase:**
```bash
#!/usr/bin/env bash
# switch-to-windows-phase.sh
set -e
echo "[*] Mematikan Linux clients..."
VBoxManage controlvm "client-1" savestate
VBoxManage controlvm "client-2" savestate

echo "[*] Restore snapshot Windows client (golden state)..."
VBoxManage snapshot "win-client" restore "golden"

echo "[*] Menyalakan Windows client (headless)..."
VBoxManage startvm "win-client" --type headless
echo "[+] Windows phase aktif. RAM terpakai: ~18 GB"
```

---

## INSTRUKSI 2: 10 Skenario Serangan Terpilih (2024–2026)

> Semua bisa dijalankan di topologi Linux-only + 1 Windows Workgroup Client, tanpa AD.
> Di v3, daftar ini difinalisasi menjadi 12 skenario (S-01–S-12) — lihat `blueprint-v3-updated.md` §4 dan folder `scenarios/`.

### S-01: Port Scanning / Reconnaissance
- **Kategori UNSW-NB15:** Reconnaissance
- **Paper/Report:** Bagui et al. (2022), *"Detecting Reconnaissance and Discovery Tactics from the MITRE ATT&CK Framework in Zeek Conn Logs"*, Sensors 22(20):7999 — [DOI: 10.3390/s22207999](https://doi.org/10.3390/s22207999). Direplikasi di UWF-ZeekDataFall22 (2023).
- **Relevansi 2024–2026:** Reconnaissance adalah taktik *entry-point* untuk semua breach. M-Trends 2026 mencatat exploits (sering diawali scanning) masih jadi initial access vector #1 (32%). UWF-ZeekData22 membuktikan bahwa fitur `conn.log` Zeek sudah cukup untuk mendeteksi teknik ini dengan akurasi tinggi menggunakan Random Forest — metodologinya identik dengan pipeline kita.
- **Tools simulasi legal:** `nmap -sS` (SYN scan), `nmap -sU` (UDP), `nmap -O` (OS detection), `nikto` (web vulnerability scan)
- **Resource cost:** Rendah

### S-02: Brute Force SSH & FTP (Hydra)
- **Kategori UNSW-NB15:** Brute Force
- **Paper/Report:** Chethana Datta et al. (2025), *"Framework for brute-force attack detection using federated learning"*, LNICST Vol. 601. Dikonfirmasi Cisco security report 2024: "Multiple VPN, SSH Services Targeted in Mass Brute-Force Attacks" (April 2024, SecurityWeek).
- **Relevansi 2024–2026:** Brute force terhadap layanan remote (SSH, RDP, FTP) masih teknik volume tertinggi dalam dataset NIDS modern. Fitur flow yang dihasilkan (connection rate tinggi, small payload, port 22 destination, burst pattern) sangat mudah dibedakan secara statistik — ideal untuk baseline classifier.
- **Tools simulasi legal:** `hydra -L users.txt -P pass.txt ssh://target`, `hydra ftp://target`
- **Resource cost:** Sedang (CPU attacker)

### S-03: Password Spraying (SSH, Web Login, SMB Windows)
- **Kategori UNSW-NB15:** Brute Force (subkategori "Low-and-Slow")
- **Paper/Report:** Microsoft Digital Defense Report 2025 — *"97% of identity attacks were password spray attacks"*. Dikonfirmasi MDDR 2024 (pages 39–41): password spray adalah teknik dominan dalam kategori password attacks, berbeda pola dari brute force konvensional.
- **Relevansi 2024–2026:** MDDR 2025 menegaskan bahwa spray tetap jadi teknik identitas #1 karena menghindari lockout. Dengan Windows client di Phase Windows, kita bisa spray ke SMB lokal dan RDP — menghasilkan trafik yang lebih realistis dari sekadar HTTP.
- **Tools simulasi legal:** `crackmapexec smb 10.10.20.50 -u users.txt -p "Password123" --continue-on-success`, `hydra -L users.txt -p "Summer2024" rdp://win-client`
- **Resource cost:** Rendah–Sedang

### S-04: Web Application Injection (SQLi + Command Injection)
- **Kategori UNSW-NB15:** Exploits
- **Paper/Report:** OWASP Top 10:2025 (rilis resmi 2025) — Injection kategori A05, 100% aplikasi terujung memiliki risiko ini, jumlah CVE tertinggi dari semua kategori. Dikonfirmasi Springer 2024: *"A Novel Framework for SQL Injection Attack Detection"* (ICCCN 2024, Lecture Notes Networks and Systems vol. 1293).
- **Relevansi 2024–2026:** SQLi tetap menjadi ancaman aktif. OWASP 2025 menyebutkan lebih dari 14.000 CVE untuk SQL Injection — jauh lebih banyak dari kategori lain. Target: DVWA atau Juice Shop (vulnerable-by-design) di srv-web.
- **Tools simulasi legal:** `sqlmap -u "http://web01.lab.local/page?id=1" --dbs`, `curl` manual dengan payload XSS/LFI, DVWA sebagai target.
- **Resource cost:** Rendah

### S-05: RDP Brute Force & Credential-based RDP Access (Windows Phase)
- **Kategori UNSW-NB15:** Brute Force (baru, spesifik Windows)
- **Paper/Report:** Scientific Reports 2025 — *"Brute-force attack mitigation on remote access services via software-defined perimeter"* ([nature.com/s41598-025-01080-5](https://doi.org/10.1038/s41598-025-01080-5)). Splunk Security Content (updated May 2026): deteksi berdasarkan >10 koneksi ke port 3389 dalam 1 jam dari sumber yang sama.
- **Relevansi 2024–2026:** RDP brute force adalah *pre-cursor* paling umum untuk ransomware deployment — MDDR 2024 mencatat 2.75x peningkatan ransomware encounter, mayoritas dimulai dari RDP compromise. Menghasilkan traffic signatures yang sangat khas di port 3389.
- **Tools simulasi legal:** `hydra -L users.txt -P pass.txt rdp://10.10.20.50`, `ncrack -p 3389 --user labuser -P pass.txt 10.10.20.50`
- **Resource cost:** Sedang

### S-06: WinRM Lateral Movement (Windows Phase)
- **Kategori UNSW-NB15:** Backdoor (atau buat kategori baru: Lateral Movement)
- **Paper/Report:** Cybersecuritynews.com (2025): *"Detecting Lateral Movement in Windows-Based Network Infrastructures"* — mencatat WinRM Event IDs 6 & 91. Nathan Berg (2025): *"Detecting Lateral Movement with SMB and WinRM Telemetry"* — WinRM terdeteksi di Zeek `conn.log` port 5985/5986. Dikonfirmasi MITRE ATT&CK T1021.006.
- **Relevansi 2024–2026:** CrowdStrike 2026 Global Threat Report: waktu dari initial access ke lateral movement kini rata-rata 29 menit. WinRM adalah vector lateral movement yang paling sulit dibedakan dari aktivitas admin legitimate — challenge terbesar untuk ML. Di workgroup, WinRM menggunakan NTLM authentication, tidak perlu AD.
- **Tools simulasi legal:** `evil-winrm -i 10.10.20.50 -u admin_lab -p Admin@2024`, Impacket `wmiexec.py`
- **Resource cost:** Sedang

### S-07: LSASS Credential Dumping + Pass-the-Hash via SMB (Windows Phase)
- **Kategori UNSW-NB15:** Backdoor / Exploits
- **Paper/Report:** Verizon DBIR 2025: *"54% of ransomware victims had credentials previously exposed in infostealer logs"*. CISA Advisory AA24-109A (updated Jan 2026): Mimikatz LSASS dumping dikonfirmasi aktif di kampanye Play ransomware (CISA update Juni 2025) dan Akira ransomware (November 2025). MITRE ATT&CK T1003.001 (LSASS Memory), T1550.002 (Pass-the-Hash).
- **Relevansi 2024–2026:** Tanpa AD, Mimikatz masih relevan: ia dump **SAM database** (local account hashes) dan NTLM credential yang bisa dipakai untuk Pass-the-Hash ke host Windows lain di segmen yang sama via SMB. Workgroup environment **tidak menghalangi** PTH attack karena PTH bekerja di level NTLM, bukan Kerberos. Traffic yang dihasilkan: SMB port 445 spike saat credential digunakan untuk remote access.
- **Tools simulasi legal:** Impacket `secretsdump.py` untuk dump SAM (alternatif aman dari Mimikatz yang tidak perlu binary drop ke target), `pypykatz` untuk analisis dump offline.
- **Resource cost:** Rendah (post-dump via Impacket)
- **CATATAN KEAMANAN:** Untuk lab ini, gunakan `secretsdump.py` atau `pypykatz` — tool open source research yang tidak bersifat offensive malware. Hindari drop binary Mimikatz jika tidak perlu untuk alasan keamanan lab.

### S-08: SSH Lateral Movement Berantai (Linux Phase)
- **Kategori UNSW-NB15:** Backdoor / Lateral Movement
- **Paper/Report:** LMDG: *"Advancing Lateral Movement Detection Through High-Fidelity Dataset Generation"*, arxiv:2508.02942 (2025) — paper pertama yang secara khusus menganalisis dataset lateral movement dan metodologi generasinya. MITRE ATT&CK T1021.004 (SSH).
- **Relevansi 2024–2026:** Illumio Modern Trojan Horse 2025 melaporkan bahwa 84% breach parah menggunakan LOTL; SSH key/credential reuse antar-host adalah teknik paling umum di environment Linux. Menghasilkan chain of connections yang terlihat jelas di Zeek `conn.log` (source IP berubah di tiap hop).
- **Tools simulasi legal:** `ssh -J user@pivot user@target` (ProxyJump), `ssh -L` tunneling, script otomatis dengan `sshpass`/`expect`.
- **Resource cost:** Rendah

### S-09: DNS Tunneling + DoH C2 (Linux Phase)
- **Kategori UNSW-NB15:** Backdoor / Worms (covert channel)
- **Paper/Report:** Dataset DNS-Tunnel (Desember 2025, GitHub/research community), paper deteksi DoH tunneling 2025 (MTL-DoHTA dataset). Diakui oleh Suricata dan Zeek `dns.log` sebagai signature yang bisa dideteksi.
- **Relevansi 2024–2026:** DNS tunneling adalah covert exfiltration channel yang paling umum — tidak membutuhkan koneksi internet publik kalau kita jalankan resolver sendiri. DoH C2 menghasilkan pola DNS yang sangat berbeda dari trafik normal (subdomain panjang, TTL anomali, high-entropy domain names).
- **Tools simulasi legal:** `iodine`, `dnscat2`, DNS-over-HTTPS server di VM attacker
- **Resource cost:** Rendah

### S-10: Ransomware Network Behavior Simulation (SMB Mass File Access)
- **Kategori UNSW-NB15:** Backdoor (SMB burst pattern)
- **Paper/Report:** MLRan 2025 (Machine Learning for Ransomware detection), RanSMAP 2024. Dikonfirmasi MDDR 2025: *"79% of ransomware Incident Response cases involved at least one Remote Monitoring and Management tool; attackers prioritized data theft before encryption."*
- **Relevansi 2024–2026:** Pola network dari ransomware (mass SMB file open/rename) masih bisa direpresentasikan tanpa payload enkripsi sungguhan. Script benign yang membuka/rename/timpa ratusan file di SMB share menghasilkan trafik yang identik secara network flow.
- **Tools simulasi legal:** Script bash/Python yang enumerate, buka, dan timpa file di SMB mount — tidak ada binary malware.
- **Resource cost:** Rendah

### S-11: DoS/DDoS Internal (hping3 SYN Flood, UDP Flood)
- **Kategori UNSW-NB15:** DoS
- **Paper/Report:** Dataset DoS modern 2024–2025 (CIC-DDoS2024, diakui sebagai benchmark). CrowdStrike 2026 Global Threat Report mengonfirmasi DDoS masih salah satu taktik paling sering dipakai untuk disruption sebelum ransomware deployment.
- **Relevansi 2024–2026:** DoS adalah salah satu kategori dengan feature signature paling kuat untuk ML (packet rate, byte rate, connection state distribution). Internal DoS simulation (attacker → srv-web) menghasilkan fitur UNSW-NB15-compatible: `sload`, `dload`, `rate`, `sintpkt`.
- **Tools simulasi legal:** `hping3 -S --flood -V -p 80 10.10.10.10`, `hping3 --udp -p 53 --flood 10.10.10.10`
- **Resource cost:** Tinggi (sementara, CPU/NIC spike)

### S-12: Data Exfiltration Multi-channel (Netcat, ICMP, HTTP POST)
- **Kategori UNSW-NB15:** Analysis / Backdoor
- **Paper/Report:** Mandiant M-Trends 2025: *"40% of all incidents involved data theft"* — exfiltration adalah tujuan akhir mayoritas serangan modern. M-Trends 2026 mengonfirmasi tren ini meningkat.
- **Relevansi 2024–2026:** Exfiltration menghasilkan pola trafik berbeda per channel: Netcat menghasilkan flow besar ke port tidak biasa, ICMP exfil menghasilkan oversized ICMP payload, HTTP POST exfil bercampur dengan trafik web normal (ini yang menarik untuk ML — low signal-to-noise).
- **Tools simulasi legal:** `nc`, `curl -X POST`, `ping` dengan payload ICMP, `tcpreplay` untuk HTTP exfiltration replay.
- **Resource cost:** Rendah

---

## INSTRUKSI 3: Perbandingan Daftar Serangan Lama vs Rekomendasi Baru

### 3.1 Tabel Perbandingan

| Serangan Lama | Didukung Paper/Report 2024–2026? | Status | Alasan Teknis/Akademik |
|---|---|---|---|
| **Port Scanning (Nmap)** | ✅ Ya — UWF-ZeekData22 (Bagui et al. 2022–2023, digunakan terus di penelitian 2024) | **Pertahankan** | Reconnaissance adalah entry tactic di semua APT chain; fitur flow dari scanning sangat khas dan ML-friendly. Dipertahankan sebagai S-01. |
| **SSH Brute Force (Hydra)** | ✅ Ya — Scientific Reports 2025 (Brute-force via SDP), CISA advisory 2024 (SSH mass brute force campaign) | **Pertahankan** | Brute force terhadap SSH masih teknik volume tertinggi. Dipertahankan sebagai S-02. |
| **Password Spraying** | ✅ Ya — MDDR 2025 ("97% identity attacks = password spray") | **Pertahankan + Perluas** | Diperluas ke RDP/SMB Windows di Phase Windows. S-03. |
| **SQL Injection (sqlmap)** | ✅ Ya — OWASP Top 10:2025 (A05 Injection, CVE terbanyak) | **Pertahankan** | Tetap salah satu teknik paling umum di layer aplikasi. S-04. |
| **DDoS/DoS (hping3)** | ✅ Ya — CrowdStrike 2026 Global Threat Report; CIC-DDoS2024 dataset | **Pertahankan** | DoS menghasilkan fitur ML terkuat (rate, burst). S-11. |
| **Reverse Shell (bash/netcat)** | ✅ Ya — Illumio 2025 (LOTL in 84% severe breaches); M-Trends 2025 (LOTL di top techniques) | **Pertahankan + Perluas** | Di Linux tetap via bash/nc. Di Windows Phase, perluas ke PowerShell one-liner reverse shell. Termasuk di S-08. |
| **Windows Credential Dumping (Mimikatz)** | ✅ Ya — CISA AA24-109A (update Jan 2026); DBIR 2025 (54% ransomware victims dari credential dumps) | **Pertahankan (modifikasi tools)** | **RELEVAN TANPA AD:** Mimikatz/pypykatz bisa dump SAM (local accounts) dan NTLM hashes — tidak membutuhkan domain. PTH via SMB bekerja di workgroup. Gunakan `secretsdump.py`/`pypykatz` sebagai alternatif aman. S-07. |
| **Kerberoasting (Impacket)** | ❌ Tidak berlaku — memerlukan Active Directory / KDC. Tidak ada paper yang memvalidasi Kerberoasting di workgroup. | **Hapus dari lab ini** | Kerberos hanya ada di AD environment. Di workgroup, Windows menggunakan NTLM untuk autentikasi, bukan Kerberos. Ganti dengan PTH (Pass-the-Hash) yang juga menggunakan Impacket tapi bekerja via NTLM/SMB. |
| **SMB Enumeration / Relay** | ⚠️ Sebagian — SMB enumeration ✅ valid. NTLM Relay (MitM) ⚠️ butuh kondisi spesifik. | **Pertahankan enumeration, Modifikasi relay** | **SMB enumeration** (`smbclient`, `enum4linux`, `crackmapexec`) sangat valid di workgroup dan menghasilkan trafik SMB realistis. **NTLM Relay** tanpa AD bisa dilakukan (Responder + NTLM relay ke target tanpa SMB signing) tapi lebih kompleks. Rekomendasikan: jalankan SMB lateral movement via PTH (lebih jelas polanya untuk ML). S-07 mencakup ini. |
| **DNS Tunneling (iodine)** | ✅ Ya — Dataset DNS-Tunnel Des 2025; MTL-DoHTA 2025 | **Pertahankan + Tambah DoH** | Perluas ke DoH C2 channel. S-09. |
| **Lateral Movement SSH** | ✅ Ya — LMDG arxiv:2508.02942 (2025); MITRE ATT&CK T1021.004 | **Pertahankan + Formalisasi chain** | Formalisasi sebagai chain 2+ hop (victim1 → victim2 → server). S-08. |
| **Phishing (sendemail, HTTP server)** | ⚠️ Sebagian — phishing sebagai konsep ✅ relevan (MDDR 2025: ClickFix social engineering). Tapi traffic signature di layer network sangat lemah untuk ML flow-based. | **Pertahankan terbatas / Turunkan prioritas** | Phishing menghasilkan sedikit sinyal network. Lebih cocok untuk dataset berbasis log email, bukan network flow bergaya UNSW-NB15. Jika dipertahankan, fokus pada HTTP callback / payload delivery phase, bukan social engineering. |

### 3.2 Evaluasi Khusus: Kerberoasting dan SMB Relay di Workgroup

**Kerberoasting:** Secara teknis tidak mungkin di workgroup. Kerberos membutuhkan Key Distribution Center (KDC) yang hanya ada di Active Directory Domain Services. Windows di workgroup menggunakan NTLM challenge-response. Tidak ada paper yang mendokumentasikan "Kerberoasting di workgroup" karena istilah itu secara definitif adalah AD attack. → **Hapus dan ganti dengan PTH/SAM dump.**

**NTLM Relay di Workgroup:** Berbeda dengan Kerberoasting, NTLM relay *secara teknis bisa* dilakukan di workgroup — caranya dengan Responder (racun LLMNR/NBT-NS) + ntlmrelayx.py ke target yang tidak punya SMB signing. Namun: (a) setup lebih kompleks, (b) sulit dikontrol scope-nya di lab terisolasi, (c) polanya dalam network flow tidak jauh berbeda dari SMB lateral movement biasa. **Rekomendasikan:** ganti dengan Pass-the-Hash langsung via Impacket setelah credential dump — lebih terkontrol dan fitur ML-nya lebih bersih.

### 3.3 Top 5 Serangan Wajib (Fitur ML Terbaik, Flow-based, Tanpa AD)

Ranking berdasarkan: (a) kekayaan fitur flow yang dihasilkan, (b) kemudahan labeling, (c) relevansi current threat landscape 2024–2026, (d) kesesuaian dengan skema UNSW-NB15.

| Rank | Serangan | Alasan Fitur ML-nya Kuat |
|---|---|---|
| **#1** | Port Scanning (Nmap) | Menghasilkan fitur rate, burst, dst_port_count, syn_count yang sangat distinctive; background class paling bersih untuk perbandingan |
| **#2** | Brute Force SSH + RDP (Hydra) | Connection rate tinggi, kecil payload, pola repetitif — sangat mudah dibedakan; berlaku di dua phase (Linux + Windows) |
| **#3** | DoS/DDoS (hping3) | Fitur `sload`, `dload`, `rate`, `sintpkt` adalah yang paling berbeda dari normal — classifier sederhana pun bisa membedakan |
| **#4** | SSH Lateral Movement Berantai | Menghasilkan flow chain yang visible (source IP berubah tiap hop); sulit bagi simple classifier, ideal untuk evaluasi model kompleks |
| **#5** | LSASS Dump + Pass-the-Hash → SMB (Windows Phase) | Menghasilkan spike SMB port 445 yang tiba-tiba dari source yang sebelumnya tidak aktif; behavior anomaly yang realistis dan kaya fitur |

---

## INSTRUKSI 4: Blueprint Final yang Diperbarui

> **Catatan (v3):** Topologi logis di §4.1 tetap akurat (dikonfirmasi `blueprint-v3-updated.md` §3). Tabel spesifikasi VM §4.2 sudah digantikan oleh tabel terkunci di `blueprint-v3-updated.md` §2 (RAM OPNsense naik ke 3072 MB, OS Linux upgrade ke Debian 13.7.0, win-client dapat NIC kedua hostonly untuk RDP mgmt).

### 4.1 Topologi Baru (Diagram ASCII dengan Windows Client)

```
                         HOST (VirtualBox, i7 Gen12, 40 GB RAM)
                                        |
                           [vboxnet0 - Host-Only, 192.168.56.0/24]
                                        | (MGMT only, dari host)
                              +---------+---------+
                              |   ROUTER/FIREWALL  |
                              |     OPNsense        |
                              |  NIC1: hostonly     |
                              |  NIC2: intnet-srv   |
                              |  NIC3: intnet-cli   |
                              |  NIC4: intnet-atk   |
                              +--+--------+------+--+
                                 |        |      |
     intnet-server (10.10.10.0/24)|        |      |intnet-attacker (10.10.30.0/24)
                                 |        |      |
              +------------------+        |      +------------------+
              |                           |                         |
    +-----------------+     intnet-client |             +------------------+
    |   srv-web        |     10.10.20.0/24|             |  ATTACKER (Kali) |
    |   (nginx, DVWA,  |                  |             |  10.10.30.10     |
    |   Juice Shop)    |        +---------+--------+    +------------------+
    |   10.10.10.10    |        |                  |
    +-----------------+        | LINUX Phase:      |
                               |  client-1 (.20)   |
    +-----------------+        |  client-2 (.21)   |
    |   srv-file       |        |                  |
    |   (SSH, SMB,     |        | WINDOWS Phase:   |
    |   Samba, Syslog) |        |  win-client (.50)|
    |   10.10.10.11    |        | (suspend Linux   |
    +-----------------+        |  clients saat     |
                               |  Windows aktif)   |
                               +------------------+

    +-----------------------------------------------+
    |         SENSOR / MONITOR (Debian Headless)     |
    |  NIC1: hostonly (192.168.56.20, mgmt)          |
    |  NIC2: intnet-server (promiscuous)             |
    |  NIC3: intnet-client (promiscuous)             |
    |  NIC4: intnet-attacker (promiscuous)           |
    |  Tools: Zeek, Suricata, Tranalyzer2, tcpdump  |
    +-----------------------------------------------+
```

**Segmentasi Workgroup:**
- Semua VM (Linux + Windows) berada di Workgroup `LABWORKGROUP`
- Tidak ada domain controller, tidak ada Kerberos
- Windows client bergabung ke network yang sama (intnet-client) dengan Linux clients
- DNS: semua resolusi lewat Unbound di OPNsense, host override untuk `*.lab.local`

### 4.2 Tabel Spesifikasi VM (v2 — lihat `blueprint-v3-updated.md` §2 untuk versi terkunci terbaru)

| VM | OS | vCPU | RAM | Disk | NIC | Phase |
|---|---|---|---|---|---|---|
| router-opnsense | OPNsense (FreeBSD) | 2 | 2 GB | 20 GB | hostonly + 3×intnet | Keduanya |
| srv-web | Ubuntu Server 24.04 | 2 | 2 GB | 20 GB | intnet-server | Keduanya |
| srv-file | Debian 12 | 1 | 2 GB | 20 GB | intnet-server | Keduanya |
| client-1 | Debian 12 + XFCE min | 2 | 3 GB | 20 GB | intnet-client | Linux Phase saja |
| client-2 | Debian 12 + XFCE min | 2 | 2 GB | 15 GB | intnet-client | Linux Phase saja |
| win-client | Win 11 IoT LTSC 2024 | 2 | 4 GB | 60 GB | intnet-client | Windows Phase saja |
| attacker | Kali Linux (OVA resmi) | 2 | 4 GB | 30 GB | intnet-attacker | Keduanya |
| sensor | Debian 12 headless | 2 | 4 GB | 60 GB | hostonly + 3×intnet (promisc) | Keduanya |
| **Total Linux Phase** | | **15** | **19 GB** | **185 GB** | | |
| **Total Windows Phase** | | **13** | **18 GB** | **210 GB** | | |

### 4.3 Pipeline Dataset & Fitur Baru (Spesifik Windows)

#### Capture di sensor untuk Windows traffic

```bash
# Capture traffic Windows Phase (port-port spesifik Windows)
tcpdump -i eth2 \
  "(port 3389 or port 5985 or port 5986 or port 445 or port 139 or port 135)" \
  -w /captures/windows-phase_$(date +%Y%m%d_%H%M%S).pcap
```

#### Zeek untuk Windows protocol detection

```bash
# Zeek akan otomatis mendeteksi RDP (port 3389), SMB (445), WinRM (5985/5986)
zeek -r windows-phase.pcap \
  protocols/smb/main.zeek \
  protocols/rdp/main.zeek \
  frameworks/communication/listen.zeek

# Cek log yang dihasilkan
ls -la *.log
# conn.log, smb_files.log, smb_cmd.log, rdp.log, http.log
```

#### Fitur tambahan dari Windows Protocol Logs (Zeek)

| Log File | Fitur Baru | Mapping ke UNSW-NB15 |
|---|---|---|
| `rdp.log` | `cookie`, `result`, `keyboard_layout`, `client_channels` | Tambahan ke fitur `service` |
| `smb_cmd.log` | `command`, `argument`, `status`, file access pattern | Bisa hasilkan fitur `sbytes`/`dbytes` per SMB session |
| `smb_files.log` | `action`, `path`, `size` — sangat relevan untuk ransomware detection | Fitur baru: `smb_file_ops_per_sec` |
| `ntlm.log` | `username`, `hostname`, `success` — untuk deteksi PTH | Fitur baru: `ntlm_auth_count` |

#### Ekstraksi fitur bergaya UNSW-NB15 dari Windows traffic

> **CATATAN (ditambahkan 2026-10-02):** Tranalyzer2 sudah digantikan **Argus**
> per keputusan terkunci di `blueprint-v3-updated.md` §1 log deviasi #16 dan
> `phase5-sensor.md` §7.3 (Tranalyzer2 tidak lagi maintained; UNSW-NB15 asli
> sendiri memakai Argus+Bro-IDS). Contoh di bawah adalah rencana original v2,
> dipertahankan sebagai referensi historis — untuk pipeline ekstraksi fitur
> yang aktual dipakai, lihat `phase5-sensor.md` §7 (arsitektur pcap-first).

```bash
# [HISTORIS — v2, sudah digantikan Argus, lihat catatan di atas]
# Tranalyzer2 pada Windows phase pcap
tranalyzer -r windows-phase.pcap -w /processed/windows/
# Output: flows.txt dengan fitur: dur, proto, sbytes, dbytes, sttl, dttl, sload, dload, rate, dll.

# Gabung dengan Zeek enrichment
python3 merge_zeek_tranalyzer.py \
  --flows /processed/windows/flows.txt \
  --zeek-conn /processed/windows/conn.log \
  --smb-log /processed/windows/smb_cmd.log \
  --output /processed/windows/flows_enriched.csv
```

### 4.4 Baseline Machine Learning — Multi-class dengan Class Imbalance Handling

```python
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
from imblearn.over_sampling import SMOTE
import xgboost as xgb

# === 1. Load & Cleaning ===
df = pd.read_csv("/dataset/processed/csv/all_flows.csv")
# Buang kolom identitas literal (IP address, port literal)
id_cols = ['src_ip','dst_ip','src_port','dst_port','flow_id']
df = df.drop(columns=[c for c in id_cols if c in df.columns])

# === 2. Label Encoding ===
le = LabelEncoder()
df['label_enc'] = le.fit_transform(df['attack_cat'])
# attack_cat contoh: normal, Reconnaissance, BruteForce, Exploits, DoS, Backdoor

# === 3. Feature Scaling (fit HANYA di train set!) ===
feature_cols = [c for c in df.columns if c not in ['label','label_enc','attack_cat','scenario_id']]
scaler = MinMaxScaler()

# === 4. Train/Test Split berbasis SKENARIO (bukan per-baris, cegah leakage!) ===
gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
train_idx, test_idx = next(gss.split(df, groups=df['scenario_id']))
X_train = df.iloc[train_idx][feature_cols]
X_test  = df.iloc[test_idx][feature_cols]
y_train = df.iloc[train_idx]['label_enc']
y_test  = df.iloc[test_idx]['label_enc']

X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled  = scaler.transform(X_test)  # HANYA transform, tidak fit ulang!

# === 5. Handle Class Imbalance dengan SMOTE ===
sm = SMOTE(random_state=42, k_neighbors=5)
X_res, y_res = sm.fit_resample(X_train_scaled, y_train)

# === 6. Train Model ===
# Random Forest (baseline)
rf = RandomForestClassifier(n_estimators=100, n_jobs=-1, random_state=42)
rf.fit(X_res, y_res)

# XGBoost (biasanya lebih baik untuk imbalanced)
xgb_model = xgb.XGBClassifier(
    n_estimators=200, learning_rate=0.1,
    use_label_encoder=False, eval_metric='mlogloss',
    n_jobs=-1, random_state=42
)
xgb_model.fit(X_res, y_res)

# === 7. Evaluasi ===
for name, model in [("RandomForest", rf), ("XGBoost", xgb_model)]:
    y_pred = model.predict(X_test_scaled)
    print(f"\n=== {name} ===")
    print(classification_report(y_test, y_pred,
                                  target_names=le.classes_,
                                  digits=4))
    print("Confusion Matrix:")
    print(confusion_matrix(y_test, y_pred))
    # ROC-AUC multi-class (OvR)
    y_prob = model.predict_proba(X_test_scaled)
    auc = roc_auc_score(y_test, y_prob, multi_class='ovr', average='macro')
    print(f"ROC-AUC (macro OvR): {auc:.4f}")
```

**Catatan class imbalance:** Dataset NIDS selalu sangat imbalanced (normal >> attack). Strategi:
1. SMOTE hanya pada training set (tidak pada test set!).
2. Gunakan `class_weight='balanced'` di Random Forest sebagai alternatif SMOTE.
3. Laporkan per-class F1, bukan hanya average accuracy.
4. Untuk kelas yang sangat jarang (mis. WinRM lateral movement), pertimbangkan augmentasi synthetic atau replay traffic.

### 4.5 Checklist Validasi Khusus Windows Client

```
ISOLASI JARINGAN
[ ] VBoxManage showvminfo "win-client" | grep NIC → tidak ada NAT/bridged
[ ] Dari win-client: ping 8.8.8.8 → timeout/request timed out
[ ] Dari win-client: nslookup web01.lab.local → resolve ke 10.10.10.10 (via OPNsense Unbound)
[ ] Dari win-client: nslookup google.com → NXDOMAIN atau timeout (tidak ada upstream DNS publik)

PROTOKOL WINDOWS TERDETEKSI DI SENSOR
[ ] RDP (port 3389): dari Kali ke win-client → muncul di Zeek conn.log (proto=tcp, port=3389)
[ ] SMB (port 445): win-client ↔ srv-file → muncul di Zeek smb_cmd.log
[ ] WinRM (port 5985): dari Kali ke win-client → muncul di Zeek conn.log

LOGGING WINDOWS CLIENT
[ ] C:\Windows\System32\LogFiles\Firewall\pfirewall.log → ada entri saat trafik masuk/keluar
[ ] Event Viewer → Windows Logs → Security → Event ID 4625 (failed logon) muncul saat brute force
[ ] Event Viewer → Security → Event ID 4624 (successful logon) muncul saat PTH berhasil

SINKRONISASI WAKTU
[ ] Dari win-client: w32tm /query /status → synced ke NTP server OPNsense
[ ] Dari sensor: date | Dari win-client: time → selisih < 1 detik

REPRODUCIBILITY
[ ] Restore win-client ke snapshot "golden" → jalankan RDP brute force scenario → hasil konsisten
[ ] Hash pcap dari run pertama = hash dari run kedua (setelah restore snapshot)
```

---

## Referensi Final

| Sumber | Relevansi untuk Blueprint v2 |
|---|---|
| Microsoft Learn — Windows IoT Enterprise LTSC 2024 ([learn.microsoft.com](https://learn.microsoft.com/windows/iot/iot-enterprise/whats-new/windows-11-iot-enterprise-ltsc-2024)) | Justifikasi pilihan OS Windows client |
| Microsoft Learn — Device Optimization Overview ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/overview)) | Debloating resmi via DISM |
| Microsoft Learn — WinRM Installation & Configuration ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)) | Setup WinRM untuk lateral movement simulation |
| Microsoft Learn — Allow RDP Access ([learn.microsoft.com](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/remote-desktop-allow-access)) | Enable RDP di Windows lab |
| Microsoft Learn — New-SmbShare ([learn.microsoft.com](https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare)) | Setup SMB share untuk traffic generation |
| MDDR 2024 & 2025 ([microsoft.com/security-insider](https://www.microsoft.com/en-us/security/security-insider/threat-landscape/microsoft-digital-defense-report-2025)) | Justifikasi Password Spraying, Ransomware, Infostealers |
| Mandiant M-Trends 2025 ([cloud.google.com](https://cloud.google.com/blog/topics/threat-intelligence/m-trends-2025/)) | Justifikasi Stolen Credentials (#2 initial access), LOTL |
| Mandiant M-Trends 2026 ([cloud.google.com](https://cloud.google.com/blog/topics/threat-intelligence/m-trends-2026)) | Exploits masih #1, dwell time 14 hari, voice phishing #2 |
| Verizon DBIR 2025 | Justifikasi Credential Dumping (54% ransomware dari credential exposure) |
| CISA Advisory AA24-109A (update Jan 2026) ([attackiq.com](https://www.attackiq.com/2025/11/18/updated-response-to-cisa-advisory-aa24-109a/)) | Justifikasi LSASS dump (Play ransomware chain) |
| Bagui et al. 2022, Sensors 22(20):7999 ([doi.org/10.3390/s22207999](https://doi.org/10.3390/s22207999)) | Metodologi Zeek conn.log + MITRE ATT&CK labeling (identik dengan pipeline kita) |
| LMDG arxiv:2508.02942 (2025) ([arxiv.org](https://arxiv.org/pdf/2508.02942)) | Justifikasi Lateral Movement detection & dataset generation |
| Scientific Reports 2025 ([nature.com/s41598-025-01080-5](https://doi.org/10.1038/s41598-025-01080-5)) | Justifikasi RDP brute force detection via SDP |
| OWASP Top 10:2025 ([owasp.org](https://owasp.org/Top10/2025/A05_2025-Injection/)) | Justifikasi SQL Injection (A05, CVE terbanyak) |
| Nathan Berg 2025 ([nathanberg.io](https://nathanberg.io/posts/detecting-lateral-movement-smb-winrm-telemetry/)) | WinRM terdeteksi di Zeek conn.log port 5985/5986 |
| MITRE ATT&CK T1021.004/006, T1003.001, T1550.002 ([attack.mitre.org](https://attack.mitre.org)) | Framework mapping semua teknik lateral movement & credential access |
| VirtualBox Manual Ch.6 ([virtualbox.org/manual/ch06.html](https://www.virtualbox.org/manual/ch06.html)) | Isolasi jaringan via Internal Network |
