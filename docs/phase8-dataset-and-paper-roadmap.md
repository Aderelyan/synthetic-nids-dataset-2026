# Phase 8 — Roadmap Dataset Final & Paper (target Scopus)

Status per 2026-10-12. Dokumen pegangan: apa yang sudah siap, apa yang belum, dan
langkah berurutan menuju dataset final + paper Scopus. Melengkapi
`phase7-scenario-execution.md` (eksekusi & pipeline) dan `blueprint-v3-updated.md` (keputusan).

## Verdict kesiapan Scopus (jujur)

**Infrastruktur SIAP + tervalidasi. Penelitian BELUM.** Fondasi beres (lab 8 VM, isolasi,
12 skenario RC=0, pipeline 49-kolom, orkestrasi 1-file, overlap fix TERKONFIRMASI, generator
normal). Yang **belum ada** dan **wajib** untuk Scopus:

| Wajib utk Scopus | Status |
|---|---|
| Dataset penuh (bukan uji 120s) | ⬜ belum capture real |
| Trafik normal terstruktur di dataset | ✅ generator jalan di orkestrator; tinggal capture real |
| Eksperimen baseline ML (classifier + metrik) | ⬜ belum |
| Perbandingan + cross-dataset vs UNSW-NB15 asli | ⬜ belum |
| Tulisan paper (kontribusi + metodologi + TtV eksplisit) | ⬜ belum |

Kesimpulan: blocker teknis **sudah lewat**; sisa = capture real → eksperimen → tulisan.

## Positioning & kontribusi (framing paper)

Jangan jual sebagai "UNSW-NB15 baru". Jual sebagai:
1. **Metodologi open & reproducible** — IXIA PerfectStorm (UNSW) mahal/tertutup; lab ini
   VM + golden snapshot + skrip terbuka. **Kontribusi terkuat.**
2. **TTP & tooling kontemporer (2024–2026)** + **MITRE ATT&CK** — nxc/evil-winrm/impacket/PtH
   di Win11 LTSC. (Klaim "modern" paling kuat di rantai lateral Windows; scan/brute-force
   timeless — jangan overclaim.)
3. **Multi-vantage capture** (3 titik sensor) — varian dataset yang UNSW tak punya.
4. **Schema-compatible UNSW-NB15** (49 kolom identik) → cross-dataset / transfer learning.

## Keputusan dataset & eksperimen (2026-10-12)

- **Dua varian** dari pipeline sama (`pipeline/build_dataset.py`):
  - **SINGLE-VIEW = dataset UTAMA** (`--dedup dest`, default) — 1 flow/koneksi, 49 kolom.
  - **MULTI-VIEW = varian/kontribusi** (`--dedup off --add-vantage`) — semua vantage +`vantage`, 50 kolom.
- Dedup `dest`: flow lintas-segmen (tanpa SNAT, 5-tuple sama) disatukan, ambil baris sensor
  di segmen IP tujuan. Key = `(proto,saddr,sport,daddr,dport, round(stime/2))`.
- **S11 DoS = rotasi source-port** (Opsi B, `scenarios/s11/run.sh`): ~400 source-port berbeda,
  **src IP tetap attacker** (label by-attacker-IP aman), tiap port 1 koneksi bervolume
  (BURST). Ganti flood 1-tuple → variasi koneksi DoS nyata; multi-view DoS turun **86%→41%**.
  Rate terkontrol (BUKAN `--flood --rand-source` yg bikin argus OOM).
- **Durasi capture PER-SKENARIO** — DIKALIBRASI dari capture **BERSIH** 2026-10-12 (overlap=0).
  Target ~2500 flow/kelas, floor 300s, cap 3600s (`DURMAP` di `infra/capture-session.sh`).
  Rate single-view terukur:

  | Skenario | rate (fl/s) | durasi | est flow |
  |---|---|---|---|
  | S01 port-scan | 120.6 | 300s (floor) | ~36000 (tetap dominan; lihat TtV#9) |
  | S10 ransomware-smb | 8.15 | 300s (floor) | ~2445 |
  | S08 ssh-lateral | 1.92 | 1300s | ~2500 |
  | S11 dos-hping3 | 0.90 | 2800s | ~2520 |
  | S09 dns-tunnel | 0.88 | 2850s | ~2510 |
  | S02 brute ssh/ftp | 0.71 | 3600s (cap) | ~2560 |
  | S04 web-sqli | 0.69 | 3600s (cap) | ~2480 |
  | S12 data-exfil | 0.55 | 3600s (cap) | ~1980 |
  | S03 password-spray | 0.27 | 3600s (cap) | ~970 (inheren jarang) |

  Normal 3600s. Total fase Linux ≈ **6,1 jam attack + gap + 1 jam normal ≈ ~8 jam** (lebih
  singkat dari rencana awal seragam-1-jam). Recon tetap mayoritas (wajar; UNSW juga timpang)
  → imbalance ditangani di ML (class_weight/SMOTE post-split), bukan dipaksa seimbang.
- **Classifier: Decision Tree, kNN, MLP**. Fokus validasi + komparabilitas, bukan SOTA.
- **Akhir: cross-dataset** vs UNSW-NB15 asli (Langkah 6).

## Validasi pipeline end-to-end (2026-10-12) — LULUS

Divalidasi via orkestrator 1-file (uji 120s/window) + `infra/check-overlap.py`:
- **Schema**: single-view 49 kolom (urutan+nama = UNSW); multi-view 50 (+`vantage`).
- **Label**: 0 flow `label=1` tanpa IP attacker; 0 flow di >1 window beda-label.
- **Time-disjoint: TERKONFIRMASI** (fix poll baris-data). Dua capture bersih berturut →
  VERDICT LULUS, OVERLAP=0. (Overlap N01×N01 = client-1/2 paralel, label sama Normal, aman.)
- **Nilai fitur**: `service/state/proto` wajar; `ct_*` cap 100; DoS `Sload` tinggi.
- **Rate per-skenario bersih** terukur → dasar kalibrasi DURMAP di atas.

**CAVEAT tersisa:**
1. **`Sload/Dload/Sjit/Sintpkt/tcprtt` ≈ 0** (argus config default tak hitung timing, TtV#7).
   Opsi: aktifkan timing argus (recapture) atau terima subset + catat TtV. Belum diputuskan.

## Threats to Validity (konsolidasi — wajib di paper)

Dibanding UNSW-NB15 (45 IP / 3 network / IXIA / capture teragregasi di router,
[arXiv:1811.05372](https://arxiv.org/pdf/1811.05372)):
1. **Generator beda** — VM/OS/service nyata vs IXIA sintetis (unggul fidelity, kalah skala).
2. **Skala kecil** — 8 VM vs 45 IP.
3. **Attacker tunggal 1 titik** (10.10.30.10) — bukan multi-vector/distributed.
4. **Label beda** — UNSW: ground-truth generator; lab: window waktu + partisipasi IP attacker.
5. **`ct_*` tak bit-identik** — generator C asli UNSW tak dirilis; reproduksi level-skema.
6. **Normal class** bergantung generator (`scenarios/normal/`), bukan trafik organik nyata.
7. **`Sjit/Djit/Sintpkt/Dintpkt/tcprtt` → 0** bila argus config default. **Terkonfirmasi.**
8. **Waktu absolut lab arbitrer** (NTP stratum-10 lokal) — konsistensi relatif OK.
9. **Durasi capture per-skenario** → volume kelas hasil setelan durasi, bukan murni intensitas
   alami; recon tetap dominan. Dicatat eksplisit + distribusi dilaporkan.

Catatan: TtV bukan aib — reviewer Scopus menuntutnya eksplisit (VUSec; Arp et al. P9).

## Roadmap langkah demi langkah

### Langkah 0 — sinkron skrip ke sensor — SELESAI
Pipeline (dedup + extract-build) di sensor, teruji.

### Langkah 1 — normal traffic — SIAP
`run-linux.sh` (client-1/2) + `gen-normal.ps1` (win-client) ter-bake golden, dijalankan
otomatis oleh orkestrator (Langkah 2), 1 jam, window terpisah dari attack.

### Langkah 2 — capture penuh per fase — SIAP DIJALANKAN
```bash
bash infra/capture-session.sh          # REAL: DURMAP per-skenario + normal 1 jam (~8 jam)
bash infra/capture-session.sh 120 15   # UJI : seragam 120s
```
Time-disjoint dijaga poll **baris data** (overlap fix, terkonfirmasi). win-client (fase
Windows) terpisah. Sensor TIDAK di-restore. Label = `~/capture-windows.csv` (attacker) +
`~/normal-markers.csv` (client/win).

### Langkah 3 — ekstraksi + verifikasi — SIAP
```bash
bash infra/extract-session.sh          # marker → sensor → extract-build.sh → tarik CSV
python infra/check-overlap.py          # WAJIB: OVERLAP=0, VERDICT LULUS sebelum pakai data
```
Hasil: `extract-out/unsw.csv` (utama) + `unsw_multi.csv` + `markers.csv`.

### Langkah 4 — gabung semua sesi + schema
Gabung CSV semua sesi (Linux + Windows + normal) → `dataset/unsw-lab-full.csv`.
`dataset/schema.md`: 49 kolom + definisi + sumber + distribusi kelas.

### Langkah 5 — eksperimen baseline ML (WAJIB)
- **Decision Tree, kNN, MLP**. Split: `GroupShuffleSplit` per `scenario_id` + temporal.
- MinMaxScaler + encoding (proto/state/service); SMOTE/class_weight **post-split**.
- Metrik per-kelas (precision/recall/F1, confusion matrix); laporan distribusi pre/post-SMOTE.

### Langkah 6 — cross-dataset vs UNSW-NB15
Banding distribusi & fitur; satukan skema (49 kolom), selaraskan `attack_cat` ke 9 kelas UNSW;
latih-UNSW→uji-lab (dan sebaliknya) + uji gabungan. Normalisasi `service`/`state`/`proto`.

### Langkah 7 — tulis paper
Intro (gap) · Related work · Metodologi (reproducible) · Dataset (schema, statistik) ·
Eksperimen (DT/kNN/MLP + cross-dataset) · **Threats to Validity** · Kesimpulan.
Target realistis (deadline 31 Okt): **proceeding ter-index Scopus**.

## Catatan deadline
Deadline 31 Okt 2026. Langkah 1–4 (dataset) bisa cepat; 5–7 (eksperimen + tulisan) beban
terbesar. Prioritas: dataset final → eksperimen minimal kredibel → tulisan dgn TtV kuat.
