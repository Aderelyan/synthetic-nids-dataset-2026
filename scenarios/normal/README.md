# scenarios/normal/ — Generator Trafik NORMAL (benign)

UNSW-NB15 asli membangkitkan trafik normal **secara eksplisit** (IXIA PerfectStorm),
bukan sekadar idle. Ini padanannya untuk lab: sesi benign acak dari **client** (bukan
attacker) ke srv-web/srv-file, dengan think-time mirip pengguna. Flow-nya tak melibatkan
IP attacker (10.10.30.10) → otomatis `label=0` / `attack_cat=Normal` di `pipeline/build_dataset.py`.

Kenapa penting: tanpa normal terstruktur, kelas `Normal` terlalu tipis/sintetik →
classifier belajar heuristik trivial "ada trafik = attack" (base-rate fallacy, Arp et al. P8).
Lihat `docs/blueprint-v3-updated.md` §5 poin 2.

## File
| File | Jalan di | Bahasa |
|---|---|---|
| `run-linux.sh` | client-1, client-2 | bash |
| `gen-normal.ps1` | win-client | PowerShell |

## Aksi yang dibangkitkan
Beberapa **worker paralel** (default 4) yang masing-masing membangkitkan, secara acak:
HTTP **page-view** (2–3 request cepat: HTML + aset, meniru browser) ke srv-web (path DVWA/
statis) · DNS lookup nama `*.lab.local` (resolver Unbound lab) · FTP list+upload kecil ke
srv-file · SSH sesi singkat (Linux, bila sshpass ada) · SMB list share (Windows) · ICMP
ringan · unduhan HTTP kecil. Think-time acak **0,5–3 dtk**.

## Kalibrasi rate (penting)
Rate normal dikendalikan oleh `--workers` / `-Workers`. Jangan naikkan tanpa verifikasi:
- `--workers 1` ≈ rate lama (~0,7 fl/s per client).
- `--workers 4` (default) ≈ beberapa kali lipat, untuk mempertebal kelas Normal.
- Setelah ganti, ukur via `python infra/check-overlap.py extract-out/<TAG>` pada bagian
  "FLOW PER-SKENARIO" dan pastikan porsi Normal tidak mendominasi berlebihan (target wajar
  ~30–50% total flow) dan window tetap time-disjoint.

## Cara pakai (window waktu terpisah dari attack — WAJIB)

Normal generator = **skenario tersendiri** di window waktu sendiri, TIDAK overlap dengan
skenario attack (basis labeling window, blueprint §9). Urutan sesi capture:
`[Normal window] → gap 2–5 mnt → [S01] → gap → [S02] → ...`

### Linux (client-1 & client-2), dari host via jump router
```bash
# deploy sekali (ganti PW sesuai lab):
sshpass -p 'root' ...   # ATAU scp manual ke tiap client
# jalankan paralel di kedua client, mis. 30 menit dengan 4 worker per client:
ssh labadmin@client-1 'bash ~/run-linux.sh --duration 1800 --workers 4' &
ssh labadmin@client-2 'bash ~/run-linux.sh --duration 1800 --workers 4' &
wait
```
(client dijangkau lewat jump OPNsense — pola sama `infra/install`.)

### Windows (win-client)
```powershell
powershell -ExecutionPolicy Bypass -File gen-normal.ps1 -Duration 1800 -Workers 4
```

## Marker & labeling
Tiap run menulis 1 baris window ke `~/normal-markers.csv` (skema sama `attack-markers.csv`):
`scenario,attack_cat,phase,target,start_utc,end_utc` → `N01,Normal,...`.
Gabungkan dengan `attack-markers.csv` saat `build_dataset.py --markers <gabungan.csv>`.
(Baris Normal sebenarnya opsional untuk label — flow non-attacker sudah jadi Normal —
tapi berguna untuk dokumentasi/analisis window.)

## Catatan
- Fase harus benar: Linux generator saat client-1/2 nyala; Windows generator saat
  win-client nyala — sama seperti aturan fase skenario attack.
- `run-linux.sh` butuh `curl` (ada di client via setup) + `getent`+`ping` (bawaan).
  FTP/SSH pakai kredensial lab `labadmin/labadmin` (sintetis, lab-only).
- Durasi: untuk dataset serius jalankan **berjam-jam** (blueprint §5 poin 2), bukan menit.
