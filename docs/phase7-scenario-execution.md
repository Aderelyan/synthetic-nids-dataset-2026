# Phase 7 — Eksekusi Skenario Serangan (IN PROGRESS, mulai 2026-10-08)

Eksekusi 12 skenario (S01–S12) dari attacker → capture di sensor → ekstraksi →
pipeline CSV final UNSW-NB15. Dokumen ini pegangan operasional + catatan masalah
yang sudah ditemukan & solusinya.

## Status ringkas

| Item | Status |
|---|---|
| S01 dry-run (recon) | ✅ SELESAI & terverifikasi 2026-10-08 (no leakage, sesuai blueprint) |
| Prasyarat eksekusi (iodined, sshpass, NOPASSWD, deploy scenarios) | ✅ beres 2026-10-09 |
| Smoke-test batch Linux (S01–S04, S08–S12) | ✅ SELESAI 2026-10-10 — 9/9 `RC=0`; S08 diperbaiki (§S08) |
| Smoke-test Windows (S05–S07) | ✅ SELESAI 2026-10-12 — skrip dibuat + 3/3 `RC=0` (§Windows) |
| Golden attacker + client + win-client (helper ter-bake) | ✅ re-bake 2026-10-12 (run-1h.sh, run-linux.sh, gen-normal.ps1, S11 Opsi B); win-client re-bake 2026-10-14 (wlms disabled, §GOTCHA 14); **srv-web re-bake 2026-10-15 `f389a32f` (netplan route + dvwa-ensure.service, §GOTCHA 17/18)** |
| Pipeline CSV final 49 kolom + label | ✅ DIBANGUN + diuji 2026-10-12 (`pipeline/`) — lihat §Pipeline |
| Orkestrasi capture+ekstraksi Linux & Windows (`infra/`) | ✅ DIBANGUN + divalidasi end-to-end (Linux 2026-10-12, Windows 2026-10-13) |
| Capture penuh + transfer | ⏳ **Windows SUDAH** (arsip `windows-20261014-061544`) + **Linux hari-1 SUDAH** (arsip `linux-20261014-092351`; S04 VOID → diulang hari-2); **Linux hari-2 pending** |

## Skrip skenario (`scenarios/`)

Dijalankan DARI attacker (`~/scenarios`), menulis marker UTC ke
`~/attack-markers.csv`. Detail di `scenarios/README.md`. Fase: Linux (client-1/2
nyala) vs Windows (win-client nyala) — tak pernah bareng.

| #                      | Target              | Fase      | attack_cat     | Butuh                              | Smoke-test                   |
| ---------------------- | ------------------- | --------- | -------------- | ---------------------------------- | ---------------------------- |
| S01 recon              | server+client       | any       | Reconnaissance | sudo (nmap)                        | ✅ RC=0                       |
| S02 brute SSH/FTP      | srv-file            | any       | Brute Force    | hydra                              | ✅ RC=0 (crack FTP)           |
| S03 spray              | srv-file (+win)     | linux/win | Brute Force    | hydra, nxc                         | ✅ RC=0                       |
| S04 SQLi               | srv-web DVWA        | any       | Exploits       | curl (+sqlmap)                     | ✅ RC=0                       |
| S05 RDP brute          | win-client          | **win**   | Brute Force    | hydra                              | ✅ RC=0 (crack labadmin)      |
| S06 WinRM              | win-client          | **win**   | Backdoor       | nxc; **WinRM scope=Any** (Phase 6) | ✅ RC=0 (Pwn3d!)              |
| S07 SAM/PTH            | win-client          | **win**   | Backdoor       | impacket, nxc                      | ✅ RC=0 (dump hash)           |
| S08 SSH lateral        | client-1→2→srv-file | **linux** | Backdoor       | **sshpass**, ssh-keygen            | ✅ RC=0 (HOP-FINAL)           |
| S09 DNS tunnel         | srv-file            | linux     | Backdoor       | iodine; **iodined di srv-file**    | ✅ RC=0                       |
| S10 SMB ransomware-sim | srv-file            | any       | Backdoor       | smbclient                          | ✅ RC=0                       |
| S11 DoS                | srv-web             | any       | DoS            | hping3 (sudo)                      | ✅ RC=0 (Opsi B rotasi sport) |
| S12 exfil              | client-1→attacker   | **linux** | Analysis       | **sshpass**, nc                    | ✅ RC=0                       |

Label serangan di dataset = **6 attack_cat** (+ Normal): Reconnaissance (S01), Brute Force
(S02/S03/S05), Exploits (S04), Backdoor (S06/S07/S08/S09/S10), DoS (S11), Analysis (S12).
"Brute Force" bukan kategori asli UNSW-NB15 → diselaraskan saat cross-dataset (phase8 L6).

## §Orkestrasi capture + ekstraksi (`infra/`)

File menjalankan 1 sesi penuh dari HOST (git-bash) tanpa Hermes. Semua label diambil
dari window yang DITULIS skrip, bukan ditebak.

| File | Fungsi |
|---|---|
| `infra/capture-session.sh` | FASE LINUX: clean+start pcap → Normal 1 jam (client-1/2) → skenario Linux (DURMAP, `run-1h.sh`, +iodined S09) → stop pcap → **ARSIP pcap+marker → sensor:`~/pcap-archive/linux-<stamp>`**. Env `SCN_LIST="..."` pilih subset skenario; `SKIP_NORMAL=1` lewati Normal (untuk SPLIT 2-hari) |
| `infra/capture-session-windows.sh` | FASE WINDOWS: win-client NYALA, client-1/2 MATI. Normal via **guestcontrol** (gen-normal.ps1) + S05/S06/S07 dari attacker → **ARSIP → sensor:`~/pcap-archive/windows-<stamp>`** |
| `infra/extract-session.sh <TAG>` | ekstrak SATU arsip: `extract-build.sh` di sensor atas `~/pcap-archive/<TAG>` → CSV ke `extract-out/<TAG>/`. Tanpa arg = daftar arsip |
| `infra/check-overlap.py [dir]` | verifikasi window TIME-DISJOINT + 0 flow di >1 window + FLOW PER-SKENARIO (`Stime`). Pakai `extract-out/<TAG>` |

**Alur (arsip per-sesi → aman lintas-hari, pcap TAK hilang):**
```bash
# CAPTURE — tiap sesi mengarsipkan pcap+marker sendiri (tag=<fase>-<waktu>); JANGAN extract dulu
bash infra/capture-session-windows.sh                 # REAL Windows (~3,5 jam)
# --- ganti fase VM: win-client OFF, client-1/2 ON ---
# Linux DIPECAH 2 hari via SCN_LIST + SKIP_NORMAL. PENTING git-bash: WAJIB `export` di baris
# terpisah (prefix `VAR=val bash` TIDAK diwarisi — GOTCHA 16). Cek baris pertama log:
#   `SCNS=[...] | Normal=...`.
# Hari-1 (SUDAH dijalankan 2026-10-14 -> arsip linux-20261014-092351; +Normal, ~3,9 jam):
export SCN_LIST="s01-port-scanning s02-bruteforce-ssh-ftp s04-web-injection-sqli s08-ssh-lateral-movement s10-ransomware-smb-sim"
bash infra/capture-session.sh
#   CATATAN: S04 hari-1 VOID (srv-web tanpa route, 0 flow — GOTCHA 17) -> S04 DIPINDAH ke Hari-2.
# Hari-2 (tanpa Normal, ~3,9 jam) — S04 ikut di sini:
export SKIP_NORMAL=1
export SCN_LIST="s03-password-spraying s04-web-injection-sqli s09-dns-tunneling-doh s11-dos-ddos-hping3 s12-data-exfiltration"
bash infra/capture-session.sh
unset SKIP_NORMAL SCN_LIST                             # biar tak kebawa run berikutnya
#   (1 sesi penuh tanpa split: bash infra/capture-session.sh ; UJI cepat: bash infra/capture-session.sh 120 15)

# EKSTRAK tiap arsip SETELAH semua capture, lalu verifikasi:
bash infra/extract-session.sh                          # daftar TAG
bash infra/extract-session.sh <TAG> ; python infra/check-overlap.py extract-out/<TAG>
```
Gabung semua `extract-out/<TAG>/unsw.csv` (Windows + Linux hari-1 + hari-2) → dataset final (phase8 L4).
S04 di arsip hari-1 kosong (void) → sumber S04 = arsip hari-2.

**Arsip & rotasi pcap:** unit tcpdump pakai `-G 3600` → capture panjang terpecah per jam jadi
banyak file. Tiap capture **mv** semua file rotasi per-iface ke `~/pcap-archive/<TAG>/<if>/` + markers.csv;
`extract-build.sh` **menggabung** file rotasi jadi 1 pcap (potong header 24B, tanpa mergecap) sebelum
zeek/argus. clean-di-awal sesi berikut HANYA sentuh working dir `/var/log/pcap/<if>/` → arsip (termasuk
sesi hari sebelumnya) AMAN. **Jangan restore sensor** (arsip di situ); pantau disk sensor.

**DURMAP Linux (`capture-session.sh`)** — DIKALIBRASI capture BERSIH 2026-10-12 (overlap=0).
Target ~2500 flow/kelas, floor 300s, cap 3600s. Rate single-view (fl/s); recon & S10 → floor:

| Skenario | rate | durasi | est flow |
|---|---|---|---|
| S01 port-scan | 120.6 | 300s (floor) | ~36000 (dominan; TtV#9) |
| S10 ransomware-smb | 8.15 | 300s (floor) | ~2445 |
| S08 ssh-lateral | 1.92 | 1300s | ~2500 |
| S11 dos-hping3 | 0.90 | 2800s | ~2520 |
| S09 dns-tunnel | 0.88 | 2850s | ~2510 |
| S02 brute ssh/ftp | 0.71 | 3600s (cap) | ~2560 |
| S04 web-sqli | 0.69 | 3600s (cap) | ~2480 |
| S12 data-exfil | 0.55 | 3600s (cap) | ~1980 |
| S03 password-spray | 0.27 | 3600s (cap) | ~970 |

Normal 3600s. Total fase Linux ≈ ~8 jam. Recon tetap mayoritas (wajar; UNSW juga timpang)
→ imbalance ditangani di ML.

**DURMAP Windows (`capture-session-windows.sh`)** — kalibrasi capture bersih 2026-10-13:

| Skenario | rate | durasi | est flow |
|---|---|---|---|
| S05 RDP brute | 2.13 | 1200s | ~2560 |
| S06 WinRM | 0.68 | 3600s (cap) | ~2450 |
| S07 SAM/PTH | 0.37 | 3600s (cap) | ~1330 |
| N01 Normal (win) | 0.33 | 3600s | ~1190 |

Total fase Windows ≈ ~3,5 jam. **Fase Linux & Windows dijalankan TERPISAH** (client vs
win-client tak pernah bareng); hasil CSV keduanya + normal digabung jadi 1 dataset (phase8 L4).

## §Validasi pipeline end-to-end — LULUS

Divalidasi via orkestrator (uji 120s/window) + `check-overlap.py`.
- Schema single-view 49 kolom (=UNSW) + multi-view 50 (+`vantage`).
- Label: 0 flow `label=1` tanpa IP attacker; 0 flow di >1 window beda-label.
- **Time-disjoint TERKONFIRMASI** (fix poll baris-data): capture bersih berturut → OVERLAP=0.
  (Overlap N01×N01 = client-1/2 paralel, label sama Normal, aman.)
- Rate per-skenario bersih terukur → dasar DURMAP di atas.
- **Fase Windows divalidasi 2026-10-13** (S05/S06/S07 + N01-win via guestcontrol): VERDICT
  LULUS, overlap 0, label {Normal, Brute Force (S05), Backdoor (S06/S07)} benar.
- **S04 end-to-end via orkestrator divalidasi 2026-10-14** (setelah fix route srv-web, uji 120s):
  window penuh 122s, 1 marker, flow Exploits > 0 — tak lagi abort 30s.

**S11 DoS — rotasi source-port (Opsi B, 2026-10-12):** `s11/run.sh` kini pakai ~400
source-port berbeda (src IP TETAP attacker → label aman), tiap port 1 koneksi bervolume,
rate terkontrol. Ganti flood 1-tuple → variasi koneksi DoS nyata; multi-view DoS turun
**86%→41%**. (Repo S11 sempat stale `--flood --rand-source` — sudah disinkron + re-bake golden.)

**CAVEAT tersisa:**
- **`Sload/Dload/Sjit/Sintpkt/tcprtt` ≈ 0** — argus config default tak hitung timing (TtV#7).
  Keputusan: aktifkan timing argus (recapture) atau terima subset + catat TtV.

## §Pipeline CSV final 49 kolom (DIBANGUN + diuji, 2026-10-12)

Folder `pipeline/` — 2 tahap, lihat `pipeline/README.md` untuk detail.

| Tahap | Skrip | Butuh | Jalan di |
|---|---|---|---|
| A — re-export argus 49-field | `ra_export.sh` | **`ra` v5** (argus-client v5) | **sensor** (argus 5.0.2) atau mesin ber-`ra` v5 |
| B — merge Zeek + ct_* + label | `build_dataset.py` | Python 3 **stdlib** (tanpa pandas) | di mana saja (host Windows OK) |

`extract-build.sh` (di sensor, dipanggil `extract-session.sh`): pcap (merge file rotasi) →
zeek+argus offline → Tahap A → Tahap B single-view (`--dedup dest`) + multi-view
(`--dedup off --add-vantage`). Progress tiap 10s tanpa timeout-kill.

- Tahap A: `.argus` biner → `<iface>_argus49.csv` (32 field argus, epoch, `-M nomar`).
  **`ra` v3 TIDAK bisa baca file argus v5** — wajib v5.
- Tahap B: gabung `service` (Zeek conn.log), http/ftp; hitung 7 `ct_*` sliding-window
  (default 100 koneksi), `ct_state_ttl`, `is_sm_ips_ports`; label per marker window
  (`--attacker-ip 10.10.30.10`). Dedup `dest` = ambil baris sensor di segmen IP tujuan.

**CAVEAT pipeline:**
- `Sjit`/`Djit`/`Sintpkt`/`Dintpkt`/`tcprtt` **kosong→0** (argus timing default). Lihat §Validasi.
- `ct_flw_http_mthd` = flag per-flow (ada GET/POST), bukan sliding-window.
- Reproduksi level-**skema** (nama+arti kolom); generator C asli UNSW tak dirilis publik.

## §Windows — smoke-test S05/S06/S07 (2026-10-12)

**Temuan awal:** `run.sh` S05/S06/S07 belum pernah ter-commit (hanya versi outputs
sesi lama) → golden lama tak punya. Dibuat & di-commit 2026-10-12, lalu diuji.

- **S05 RDP brute (hydra `rdp://win`):** `RC=0`. crack `labadmin:labadmin`. `-t 2 -f`.
- **S06 WinRM (nxc + evil-winrm):** `RC=0`, `admin_lab:Admin@2024 (Pwn3d!)`. **Fix:**
  `nxc winrm -x` jalan di **cmd** → pemisah perintah `&` bukan `;`
  (`whoami & hostname & ipconfig`).
- **S07 SAM/LSA dump + PTH:** `RC=0`. Hash NTLM ter-dump; `Administrator` blank → PTH
  dilewati (by design). **Output `s07-secretsdump.txt` berisi hash sintetis — JANGAN
  commit** (di `.gitignore`), bersihkan sebelum bake golden.

Semua skrip Windows pakai guard `ensure_up "$WIN"` → fase salah = skrip STOP.

## §S08 — fix ProxyJump host-key (2026-10-10)

**Gejala:** chain `ssh -o ProxyJump=c1,c2 srv-file` gagal `Host key verification
failed` meski `-o StrictHostKeyChecking=no` dipasang.
**Sebab:** opsi `-o` command-line hanya ke host TUJUAN, tak merambat ke jump host.
**Fix:** `s08/run.sh` buat ssh-config sementara (`mktemp`) blok `Host *` → `ssh -F`.
Deteksi `S08-OK`/`S08-FAIL` via `PIPESTATUS` + `grep HOP-FINAL`.

## Prasyarat eksekusi + skrip install (`infra/install/`)

Semua installer berpola sama: NIC NAT sementara → `apt` → lepas NAT → golden ulang;
aturan 3-strike STOP; tidak mengubah isolasi permanen.

| Prasyarat | Untuk | Skrip |
|---|---|---|
| samba+vsftpd / docker+DVWA / sudo+curl | target | `run-install.sh` + `setup-*.sh` |
| iodined (srv-file) | S09 | `install-iodined.sh` + `setup-iodined.sh` (unit disabled, start manual) |
| sshpass + NOPASSWD (attacker) | S08, S12 | `install-sshpass-attacker.sh` + `setup-sshpass.sh` |
| DVWA auto-serve (srv-web) | S04 | `dvwa-ensure.{sh,service}` (boot-time; §GOTCHA 18) |
| scenarios/ + helper di attacker | semua | ter-bake golden (hilang tiap restore) |

## GOTCHA lab-ops (jangan terulang)

1. **Restore-golden me-revert semua perubahan pasca-golden** → bake ke golden; bersihkan
   artefak runtime sebelum bake.
2. **NatNetwork-temp DNS tak resolve di Kali** → set `nameserver 8.8.8.8` sementara.
3. **State `Saved` memblok `modifyvm`** → `discardstate` dulu.
4. **iodined bisa ter-`masked`** → `systemctl unmask iodined` sebelum S09.
5. **sudo attacker minta password** → NOPASSWD sudoers di-bake.
6. **ProxyJump tak merambat opsi host-key** (S08) → ssh-config `Host *`.
7. **`nxc winrm -x` jalan di cmd** (S06) → pemisah `&`, bukan `;`.
8. **device_commit_files silent-overwrite** → setelah commit, SELALU re-stage + cek isi
   (OneDrive sering me-revert tulisan PERTAMA; commit ulang + verifikasi ukuran/isi).
9. **`ra` v3 ≠ v5** — `.argus` v5 hanya terbaca `ra` v5.
10. **Window overlap dari poll hitung header** (2026-10-12) → poll orkestrator HARUS
    hitung baris DATA (`grep -vc '^scenario,'`), bukan header yang ditulis `run-1h.sh`
    saat mulai; kalau tidak, skenario berikut start terlalu cepat → window bertumpuk →
    label ambigu. Verifikasi tiap capture dgn `check-overlap.py` (overlap WAJIB 0).
11. **S11 DoS `--flood --rand-source`** → argus OOM/hang (jutaan micro-flow). Pakai rate
    terkontrol + **rotasi ~400 source-port** (Opsi B), src IP TETAP attacker (label aman).
12. **git-bash**: `export PATH="/c/msys64/usr/bin:…"` dulu (sshpass); `$HOME` MSYS ≠
    `C:\Users\…` → output pakai `$(pwd)`; `~` di argumen di-expand LOKAL (bukan di sensor) →
    bangun `~/` di dalam string SSH; paste heredoc kadang garbled → pakai file skrip.
13. **guestcontrol win-client via git-bash** (2026-10-13): (a) `copyto` FILE→FILE sempat HANG →
    pakai `--target-directory "C:\LabData\\"`; (b) `copyfrom` TAK suka `--target-directory`
    (error "is a directory") → pakai path file tujuan langsung; (c) argumen ber-`/` kena munging
    → `export MSYS_NO_PATHCONV=1`; (d) path host ke VBoxManage.exe harus absolut Windows via
    `cygpath -w` (dan QUOTE path ber-backslash, jangan telanjang — bash makan `\`). Guest Additions +
    profil admin_lab ada → process-exec & file-copy jalan.
14. **win-client EVAL expired → shutdown ~tiap 1 jam** (2026-10-14): Win11 IoT LTSC **EVAL** grace
    habis (`slmgr /dli` → License Status **Notification**, `0xC004F009 grace time expired`) → service
    **`wlms`** memaksa reboot ~hourly → capture >1 jam MATI di tengah. `slmgr /rearm` **tak** mereset
    (dan jatah habis = 0). FIX (lab-only): disable `wlms`. Admin ditolak `Set-Service`/`reg add` (service
    terproteksi TrustedInstaller) → tulis `HKLM\SYSTEM\CurrentControlSet\Services\wlms\Start=4` lewat
    **scheduled task ber-UserId SYSTEM** (RunLevel Highest) → reboot → `Get-Service wlms` = Stopped/Disabled.
    **Bake golden win-client** setelahnya (restore golden lama = expired lagi). Tak memengaruhi dataset
    (trafik ≠ lisensi OS); catat sbg caveat ops. Darurat bila gagal: reinstall dari ISO eval baru (reset 90 hari).
15. **pcap rotasi (`-G 3600`) & arsip** (2026-10-13): capture panjang terpecah per jam → JANGAN ambil
    "file terbaru" saja (hilang data). Arsip simpan SEMUA file rotasi; `extract-build.sh` menggabung.
    Arsip per-TAG di `sensor:~/pcap-archive` membuat pcap AMAN lintas-sesi/hari (clean hanya working dir).
16. **env-prefix TIDAK diwarisi di git-bash** (2026-10-14): `SCN_LIST=... SKIP_NORMAL=1 bash capture-session.sh`
    membuat skrip MENGABAIKAN keduanya → jalan SEMUA skenario + Normal (~10 jam, bukan yang dimaksud).
    WAJIB `export` di baris terpisah dulu, lalu `bash ...`. Verifikasi baris pertama log:
    `SCNS=[...] | Normal=lewati`. Selesai → `unset SKIP_NORMAL SCN_LIST`.
17. **srv-web default-route kambuh** (2026-10-14): golden srv-web aktif TANPA default route
    (`lab-defroute.service` tak efektif di golden itu) → attacker `http 000` ke DVWA, S04 0 flow &
    abort 30s (srv-file .11 tetap jalan, jadi hanya S04 terdampak). FIX: tanam rute di **netplan**
    (`routes: - to: default / via: 10.10.10.1`) → `ip route` `proto static`, attacker `http 200`; lalu
    **re-golden** srv-web. Container DVWA juga butuh `docker update --restart unless-stopped dvwa`
    (tak auto-start setelah reboot/restore). Detail `phase3-...-srv-web.md` §11, `phase6` Temuan#1.
18. **DVWA "Up" tapi tak melayani :80 pasca host-reboot** (2026-10-15): container `vulnerables/web-dvwa`
    auto-start (restart policy) tapi apache/mysql gagal init → `:80 connection refused` (lokal & dari
    attacker) walau `docker ps` = `Up`. `--restart` TAK cukup. Gejala khas: attacker `http 000`, srv-web
    `curl localhost` kosong, `ss` tetap tampak `0.0.0.0:80` (docker-proxy) → forward ke container ditolak.
    FIX manual: `docker restart dvwa` + tunggu ~20s. FIX permanen: **`dvwa-ensure.service`**
    (`infra/install/dvwa-ensure.{sh,service}`) boot-time poll `:80` + `docker restart dvwa` bila perlu;
    ter-bake golden `f389a32f`. Verifikasi: `VBoxManage controlvm srv-web reset` → attacker `http 200`
    tanpa intervensi.

## §Verifikasi S01 (2026-10-08) — PASS, NO LEAKAGE

Output host `NIDS/extract-s01/`. Kebocoran NOL: `known_hosts`/conn.log/argus/dns hanya
IP lab; DNS hanya `*.lab.local` via Unbound lab; checksum pcap host = sensor. Sesuai
blueprint pcap-first (tcpdump 3 segmen + Zeek + Argus offline).

## Rencana lanjut

1. ✅ Smoke-test Linux + Windows (12/12 `RC=0`); pipeline + orkestrasi (2 fase) siap & tervalidasi.
2. ✅ Uji-bersih → overlap 0 (VERDICT LULUS). ✅ Kalibrasi DURMAP Linux & Windows.
3. ✅ S11 Opsi B (rotasi sport) + re-bake golden. ✅ win-client eval fix (wlms disabled) + re-bake.
   ✅ srv-web route fix (netplan, §GOTCHA 17) + DVWA auto-serve (`dvwa-ensure.service`, §GOTCHA 18) + re-bake `f389a32f` (terverifikasi lintas-reboot).
4. **Capture penuh** per fase, diarsip per-TAG. Status: ✅ Windows (`windows-20261014-061544`),
   ✅ Linux hari-1 (`linux-20261014-092351`; S04 void → ulang hari-2), ⬜ Linux hari-2
   (`s03 s04 s09 s11 s12`) → ekstrak tiap TAG + `check-overlap.py` (overlap WAJIB 0) → gabung
   semua `extract-out/<TAG>/unsw.csv` → 1 dataset (`dataset/unsw-lab-full.csv`). Lanjut ML
   (DT/kNN/MLP) + cross-dataset UNSW-NB15 (phase8).
5. (Opsional) putuskan fitur timing argus (`Sload/Sjit/...`): recapture dgn timing atau terima subset + TtV.
