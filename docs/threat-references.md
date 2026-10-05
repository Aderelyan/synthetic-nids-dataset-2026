# Threat References

Referensi paper/report 2024–2026 yang mendasari tiap skenario serangan (S01–S12).
Diambil dari `blueprint-v2-windows-client.md` INSTRUKSI 2 dan `blueprint-v3-updated.md`.
Detail lengkap tiap skenario (tools, resource cost, relevansi) ada di
`scenarios/sXX-*/README.md` masing-masing (format: `scenario-template.md`).

| Scenario | Technique | Reference | Notes |
| --- | --- | --- | --- |
| S01 | Port scanning / Reconnaissance | Bagui et al. (2022), *Sensors* 22(20):7999, [DOI:10.3390/s22207999](https://doi.org/10.3390/s22207999); direplikasi di UWF-ZeekDataFall22 (2023) | Kategori UNSW-NB15: Reconnaissance. Zeek `conn.log` cukup untuk deteksi akurasi tinggi (Random Forest) |
| S02 | SSH/FTP brute force | Chethana Datta et al. (2025), LNICST Vol. 601; Cisco/SecurityWeek (Apr 2024) "Multiple VPN, SSH Services Targeted in Mass Brute-Force Attacks" | Kategori: Brute Force. Teknik volume tertinggi di dataset NIDS modern |
| S03 | Password spraying (SSH/SMB/RDP) | Microsoft Digital Defense Report 2025 ("97% identity attacks = password spray"); MDDR 2024 pp.39–41 | Kategori: Brute Force (low-and-slow). Diperluas ke SMB/RDP Windows di Phase Windows |
| S04 | SQL injection / Command injection | OWASP Top 10:2025 (A05 Injection); Springer 2024, ICCCN, LNNS vol.1293 | Kategori: Exploits. Target: DVWA/Juice Shop di srv-web |
| S05 | RDP brute force | Scientific Reports 2025, [DOI:10.1038/s41598-025-01080-5](https://doi.org/10.1038/s41598-025-01080-5); Splunk Security Content (May 2026) | Kategori: Brute Force (Windows-specific). Precursor umum untuk ransomware deployment |
| S06 | WinRM lateral movement | cybersecuritynews.com (2025); Nathan Berg (2025); MITRE ATT&CK T1021.006 | Kategori: Backdoor/Lateral Movement. Terdeteksi via WinRM Event ID 6 & 91, Zeek conn.log port 5985/5986 |
| S07 | LSASS dump / pass-the-hash | Verizon DBIR 2025; CISA Advisory AA24-109A (update Jan 2026); MITRE T1003.001, T1550.002 | Kategori: Backdoor/Exploits. Gunakan `secretsdump.py`/`pypykatz` (bukan Mimikatz binary) |
| S08 | SSH lateral movement (chain) | LMDG, arxiv:2508.02942 (2025); MITRE ATT&CK T1021.004 | Kategori: Backdoor/Lateral Movement. Chain 2+ hop, source IP berubah tiap hop |
| S09 | DNS tunneling / DoH C2 | Dataset DNS-Tunnel (Des 2025); MTL-DoHTA dataset (2025) | Kategori: Backdoor/Worms (covert channel). Terdeteksi via Zeek `dns.log`, Suricata |
| S10 | SMB ransomware simulation | MLRan (2025); RanSMAP (2024); MDDR 2025 | Kategori: Backdoor (SMB burst pattern). Simulasi perilaku tanpa payload enkripsi sungguhan |
| S11 | DoS / DDoS (hping3) | CIC-DDoS2024 (benchmark); CrowdStrike 2026 Global Threat Report | Kategori: DoS. Fitur ML terkuat: `sload`, `dload`, `rate`, `sintpkt` |
| S12 | Data exfiltration (multi-channel) | Mandiant M-Trends 2025 ("40% incidents involve data theft"); M-Trends 2026 | Kategori: Analysis/Backdoor. Channel: Netcat, ICMP payload, HTTP POST |

## Catatan

- Daftar ini final per `blueprint-v3-updated.md` §4 (12 skenario, S01–S12). Daftar skenario versi lama (termasuk Kerberoasting) sudah tidak dipakai — lihat `blueprint-v2-windows-client.md` INSTRUKSI 3 untuk alasan penggantian.
- Referensi tambahan framework (MITRE ATT&CK, Microsoft Learn, VirtualBox Manual) ada di tabel "Referensi Final" pada `blueprint-v2-windows-client.md`.
