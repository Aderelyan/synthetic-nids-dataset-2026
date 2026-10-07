# Skenario Serangan S01–S12 — Panduan Penggunaan

Paket skrip untuk membangkitkan trafik serangan berlabel di lab NIDS terisolasi
(UNSW-NB15 style). Semua skrip dijalankan **dari VM `attacker` (Kali, 10.10.30.10)**,
menargetkan **VM milik sendiri di lab tertutup** (tanpa internet). Tiap skrip
menulis penanda waktu UTC ke `~/attack-markers.csv` untuk pelabelan `attack_cat`.

> Lab ini terisolasi total (lihat `docs/topology.md`). Skrip menolak target di
> luar range `10.10.0.0/16` / `192.168.56.0/24`.

## 1. Struktur

```
scenarios/
  _lib/
    targets.env     # IP, service, kredensial lab (sintetis) — ubah di sini
    common.sh       # fungsi bersama: marker UTC, guard IP, ping-check, need_tool
    users.txt       # userlist brute force
    pass.txt        # passlist brute force (berisi password lab asli -> ada sampel "berhasil")
  sNN-*/run.sh      # satu skrip per skenario
  .gitignore        # output run (hash/bukti) tidak ikut ter-commit
```

## 2. Deploy ke attacker

Dari host (git-bash), salin folder `scenarios/` ke attacker lewat jump router:

```bash
export PATH="/c/msys64/usr/bin:/c/Program Files/Oracle/VirtualBox:$PATH"
O="-o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# attacker user = kali/kali (sesuaikan), jump router root/root
SSH_AUTH_SOCK= tar czf - -C infra ../scenarios 2>/dev/null  # ATAU pakai scp di bawah
scp $O -o ProxyCommand="sshpass -p 'root' ssh $O -W %h:%p root@192.168.56.10" \
    -r scenarios kali@10.10.30.10:~/
```

Di attacker:
```bash
cd ~/scenarios
chmod +x _lib/common.sh s*/run.sh
```

## 3. Urutan & fase

VM yang **selalu nyala**: router, srv-web, srv-file, attacker, sensor.
`client-1`/`client-2` (Linux phase) dan `win-client` (Windows phase)
**tidak pernah nyala bersamaan** — ganti fase via `infra/vagrant/switch-phase/`.

| # | Skenario | Target | Fase | attack_cat | Tool |
|---|----------|--------|------|-----------|------|
| S01 | Port scan / recon | server (+client/win bila nyala) | any | Reconnaissance | nmap |
| S02 | Brute force SSH/FTP | srv-file | any | Brute Force | hydra |
| S03 | Password spraying | srv-file (+win) | linux/windows | Brute Force | hydra, nxc |
| S04 | Web injection (SQLi/CMDi) | srv-web DVWA | any | Exploits | sqlmap, curl |
| S05 | RDP brute force | win-client | **windows** | Brute Force | hydra |
| S06 | WinRM lateral movement | win-client | **windows** | Backdoor | nxc, evil-winrm |
| S07 | SAM/LSA dump + PTH | win-client | **windows** | Backdoor* | impacket, nxc |
| S08 | SSH lateral chain 2+ hop | client-1→client-2→srv-file | **linux** | Backdoor | ssh, sshpass |
| S09 | DNS tunneling (iodine) | srv-file (iodined) | linux | Backdoor | iodine |
| S10 | Ransomware SMB sim | srv-file labshare | any | Backdoor | smbclient |
| S11 | DoS (SYN flood) | srv-web | any | DoS | hping3 |
| S12 | Data exfil multi-channel | client-1→attacker | **linux** | Analysis* | ssh, curl, nc |

Saran urutan perekaman (per fase, jangan tumpang tindih window):
- **Linux phase:** S01 → S02 → S03(ssh) → S04 → S08 → S09 → S10 → S11 → S12
- **Windows phase:** S01 → S03(smb/rdp) → S05 → S06 → S07

Jalankan satu per satu, tunggu selesai (`<<< END`) sebelum skenario berikutnya,
supaya window waktu tiap serangan terpisah bersih di pcap.

## 4. Menjalankan

```bash
cd ~/scenarios
./s01-port-scanning/run.sh
./s02-bruteforce-ssh-ftp/run.sh
# dst, sesuai fase & urutan di atas
```

Beberapa skrip menerima argumen opsional:
- `./s03-password-spraying/run.sh "P@ssw0rd123"`  (password yang disemprot)
- `./s09-dns-tunneling-doh/run.sh 90`             (durasi tunnel, detik)
- `./s10-ransomware-smb-sim/run.sh 60`            (jumlah file burst)
- `./s11-dos-ddos-hping3/run.sh 10.10.10.10 80 30`(target port durasi)

## 5. Marker → pelabelan attack_cat

Tiap run menambah 1 baris ke `~/attack-markers.csv`:
```
scenario,attack_cat,phase,target,start_utc,end_utc
S02,Brute Force,any,10.10.10.11,2026-10-07T09:12:03Z,2026-10-07T09:14:51Z
```
Window `[start_utc, end_utc]` inilah yang dipakai
`pipeline/labeling/label_by_scenario_window.py` untuk memberi `attack_cat` pada
flow hasil Zeek/Argus. Setelah sesi perekaman, tarik file ini ke host:
```bash
scp $O -o ProxyCommand="sshpass -p 'root' ssh $O -W %h:%p root@192.168.56.10" \
    kali@10.10.30.10:~/attack-markers.csv dataset/
```

> **Jam harus sinkron.** Marker UTC dari attacker vs timestamp pcap dari sensor
> hanya cocok kalau semua VM se-UTC (sudah dibereskan 2026-10-06, lihat
> `phase2-opnsense-setup.md` §11). Cek ulang sebelum perekaman besar.

## 6. Catatan per skenario (prasyarat penting)

- **S04 (SQLi):** untuk sqlmap ber-auth, isi `DVWA_COOKIE` di `targets.env`
  (login DVWA → set DVWA Security = *Low* → ambil `PHPSESSID` + `security=low`).
  Kosong = hanya burst payload via curl (tetap ada trafik injection).
- **S07 (PTH):** `s07-secretsdump.txt` berisi hash — **jangan di-commit**
  (sudah di `.gitignore`). `attack_cat` bisa diubah ke `Exploits` bila dosen minta.
- **S08:** sekali push SSH key ke tiap hop (via sshpass, auth password lab),
  lalu chain berbasis key. Butuh `sshpass` di attacker.
- **S09 (iodine):** **PREREQUISITE** — `iodined` harus jalan dulu di `srv-file`
  (root): `sudo iodined -f -c -P labtunnel 172.16.254.1 tunnel.lab.local`.
  iodined belum terpasang di lab → pasang saat ada window instalasi. Kalau
  tunnel gagal terbentuk, skrip **berhenti** dan lapor (tidak improvisasi).
  DoH dikeluarkan dari scope (terenkripsi, bukan bagian UNSW-NB15).
- **S10:** simulasi pola burst SMB, **tanpa enkripsi data nyata**; hanya file
  sintetis yang dibuat skrip di subfolder sementara, lalu dibersihkan.
- **S11:** `--flood` membebani CPU attacker; durasi dibatasi `timeout`.
  Varian low-rate: ganti `--flood` → `-i u1000`.

## 7. Keamanan & etika

- Semua kredensial (`labadmin`, `P@ssw0rd123`, `Admin@2024`, dst.) **sintetis,
  khusus lab terisolasi**, bukan kredensial produksi.
- Skrip hanya untuk lab tertutup milik sendiri, untuk riset dataset NIDS.
  Jangan dipakai di jaringan/sistem lain.
- `common.sh` menolak target di luar range lab sebagai pengaman.

*) `attack_cat` S07 & S12 ditandai sesuai `docs/threat-references.md`
("Backdoor/Exploits", "Analysis/Backdoor"); label final bisa disesuaikan ke
taksonomi UNSW-NB15 saat pelabelan.
