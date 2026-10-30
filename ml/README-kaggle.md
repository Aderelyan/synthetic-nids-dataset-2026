# Panduan uji coba ML di Kaggle — Synthetic NIDS Dataset 2026

Dokumen ini memandu langkah percobaan machine learning **sesuai blueprint** (Bab 3.13–3.14):
Decision Tree / kNN / MLP, evaluasi bebas kebocoran skenario, metrik untuk data timpang, dan
ablasi fitur turunan IP.

Semua pelatihan dijalankan **di Kaggle**; repo ini hanya menyiapkan dataset dan notebook.

---

## 0. Artefak yang sudah disiapkan

| Berkas | Isi | Ukuran |
|---|---|---|
| `dataset/ml/lab_flows.csv` | 167.568 flow, 49 kolom UNSW + `session_id`, `archive`, `scenario` | ~49 MB |
| `dataset/ml/data_card.md` | distribusi kelas per sesi, cek kualitas | kecil |
| `ml/prepare_kaggle_dataset.py` | skrip pembentuk dataset di atas (reproducible) | — |
| `ml/kaggle_nids_baseline.ipynb` | notebook siap unggah ke Kaggle (22 sel) | — |
| `ml/kaggle_nids_baseline.py` | sumber notebook (format `# %%`, versi teks) | — |

Regenerasi dataset bila arsip bertambah:

```powershell
python ml/prepare_kaggle_dataset.py     # butuh pandas
```

---

## 1. Peta arsip → run (terverifikasi)

Urut `LastWriteTime` naik di `raw-archive/research`; **3 folder pertama = run-1**, sisanya run-2
termasuk capture Normal tambahan.

| # | Arsip | Sesi | Skenario di marker | Baris terekstrak |
|---|---|---|---|---|
| 1 | `linux-20261022-094511` | run-1 | S01 S02 S04 S08 + 2×N01 | 37.110 |
| 2 | `linux-20261023-082131` | run-1 | S03 S09 S10 S11 S12 + 2×N01 | 13.142 |
| 3 | `windows-20261023-120511` | run-1 | N01 S05 S06 S07 | 5.716 |
| 4 | `windows-20261024-051115` | run-2 | N01 S05 S06 S07 | 3.782 |
| 5 | `normal-windows-20261024-072559` | run-2 | N01 | 7.552 |
| 6 | `normal-linux-20261026-062948` | run-2 | N01 | 18.281 |
| 7 | `linux-20261026-103227` | run-2 | S01 S02 S04 S08 + 2×N01 | 53.151 |
| 8 | `linux-20261027-082533` | run-2 | S03 S09 S10 S11 S12 + 2×N01 | 28.834 |

Kedua sesi memuat **ketujuh kelas**, dan kedua belas skenario muncul di masing-masing sesi.
Inilah yang membuat evaluasi *session-disjoint* layak: tiap fold tetap punya semua kelas di
training, termasuk kelas yang hanya berasal dari satu skenario (S01, S04, S11, S12).

Distribusi kelas:

| Kelas | run-1 | run-2 | total |
|---|---|---|---|
| Normal | 9.357 | 66.025 | 75.382 |
| Reconnaissance | 26.204 | 26.449 | 52.653 |
| Backdoor | 8.664 | 7.682 | 16.346 |
| Brute Force | 4.682 | 4.343 | 9.025 |
| DoS | 2.571 | 2.614 | 5.185 |
| Exploits | 2.554 | 2.558 | 5.112 |
| Analysis | 1.936 | 1.929 | 3.865 |
| **Total** | **55.968** | **111.600** | **167.568** |

**Temuan yang harus masuk Bab 4:** volume Normal tidak seragam antar-run (9.357 vs 66.025).
Run-2 memuat dua capture Normal tambahan (25.833 flow) dan window N01 Linux-nya sendiri
menghasilkan ~19 ribu flow vs ~3,5 ribu di run-1. Akibatnya laju serangan berbeda jauh
(83% vs 41%). Ini keterbatasan reproduktifitas generator Normal — jangan disembunyikan.

---

## 2. Langkah di Kaggle (7 langkah)

### Langkah 1 — buat Dataset
1. Kaggle → **Datasets** → *New Dataset*.
2. Unggah `dataset/ml/lab_flows.csv`.
3. Beri judul/nama dataset: **`lab-flows`** → *slug* jadi `lab-flows` (dipakai path di notebook).
4. Visibilitas *Private* sampai paper selesai.

### Langkah 2 — buat Notebook
1. Kaggle → **Code** → *New Notebook*.
2. Menu **File → Import Notebook** → unggah `ml/kaggle_nids_baseline.ipynb`.
3. Panel kanan **Add Input → Datasets → lab-flows**.

### Langkah 3 — smoke test dulu
Di sel Setup, ubah:

```python
QUICK = True
```

Run All. Target: selesai < 3 menit tanpa error, menghasilkan `macro F1` dan `PR-AUC` (angkanya
belum layak dilaporkan — hanya 8.000 baris dan 1 model). Kalau sel ini error, perbaiki dulu
sebelum lanjut.

### Langkah 4 — jalankan protokol penuh
Kembalikan `QUICK = False`, lalu *Run All*. Perkiraan waktu CPU Kaggle:

| Model | Perkiraan |
|---|---|
| Decision Tree (2 fold × 2 set fitur) | < 2 menit |
| kNN (train 30k, test 56k–111k) | 10–20 menit |
| MLP (balanced 105k) | 10–25 menit |
| **Total** | **± 30–45 menit** |

GPU tidak diperlukan (DT/kNN/MLP sklearn tidak memanfaatkannya). Pilih CPU agar tidak kena
batas kuota GPU.

### Langkah 5 — periksa output
Semua di `/kaggle/working/results/`:

- `metrics_by_fold.csv` — metrik per fold (4 baris per model bila 2 set fitur).
- `metrics_summary.csv` — mean/std antar sesi.
- `per_class_by_fold.csv`, `per_class_ap_by_fold.csv`, `table_per_class_best.csv/.md`.
- `confusion_<model>-<fitur>-<sesi>.png` — 12 gambar.
- `run_manifest.json` — konfigurasi + versi library untuk reprodusibilitas.

### Langkah 6 — unduh & simpan
Unduh folder `results/` ke `ml/results/kaggle-<tanggal>/` agar bisa dilampirkan sebagai
supplementary dan dijadikan tabel paper.

### Langkah 7 — (opsional) cross-dataset UNSW-NB15
Tambahkan dataset publik UNSW-NB15 di Kaggle, lalu ikuti Sel 10. Laporkan hanya *shared
classes* (6 + Normal).

---

## 3. Protokol yang dijalankan notebook

| Aspek | Keputusan | Alasan |
|---|---|---|
| Unit analisis | flow jaringan | sesuai skema UNSW-NB15 |
| Split | **Leave-One-Session-Out** (`group = session_id`) | mencegah flow dari sesi yang sama muncul di train & test |
| Fitur | tanpa `srcip`, `dstip`, `Stime`, `Ltime` | IP = identifier; label didefinisikan lewat IP attacker → akan bocor |
| Ablasi | `all` vs `noip` (drop `is_sm_ips_ports` + 9 `ct_*`) | `ct_*` berkunci IP/port, bisa mengodekan identitas penyerang |
| Imbalance | DT `class_weight='balanced'`; kNN/MLP balanced partition (cap 15k/kelas) | tanpa SMOTE: tidak ada titik sintetis yang bisa bocor |
| Scaling/encoding | di dalam Pipeline (fit hanya pada train fold) | mencegah statistik test masuk ke train |
| Metrik utama | macro F1, per-class F1, macro PR-AUC, balanced accuracy | akurasi menyesatkan (Normal 45%, Recon 31%) |
| Metrik operasional | PR-AUC biner + recall pada FPR ≤ 1% | angka yang relevan untuk SOC |
| Model | DT, kNN, MLP | baseline sesuai blueprint; bukan klaim SOTA |

Catatan penting: dengan 2 sesi, LOGO = **2 fold**, sehingga std antar-fold hanya informatif.
Laporkan per fold (`metrics_by_fold.csv`), bukan hanya rata-rata.

---

## 4. Cara membaca hasil (bahan Bab 4)

1. **Urutan yang benar**: lihat `noip` dulu. Kalau `all` jauh lebih tinggi, model memakai jejak
   IP/`ct_*` — bukan perilaku serangan. `noip` adalah klaim yang bisa dipertahankan.
2. **Bandingkan dua fold.** `train=run-1 → test=run-2` dan sebaliknya. Selisih besar =
   *distribution shift* antar-sesi; itu temuan (bukan bug), terangkan bersama tabel support.
3. **Perhatikan kelas minoritas**: Analysis (3.865) dan DoS (5.185) paling mudah jatuh ke F1
   rendah; laporkan per kelas, jangan sembunyikan di rata-rata.
4. **Recall@FPR1%** mendekati kondisi operasi: sebutkan ambang probabilitas yang dipakai.
5. **Jangan klaim SOTA.** Kalimat aman: *"baseline ini menunjukkan dataset dapat dipakai untuk
   klasifikasi, dengan batasan generalisasi antar-sesi."*

### Tabel yang disarankan untuk paper

| Tabel | Isi | Sumber file |
|---|---|---|
| T1 | Distribusi kelas × sesi | `data_card.md` |
| T2 | Jumlah flow & skenario per sesi | `data_card.md` |
| T3 | Macro F1 / PR-AUC per model × fitur × fold | `metrics_by_fold.csv` |
| T4 | Ringkasan mean±std | `metrics_summary.csv` |
| T5 | Per-class F1 model terbaik | `table_per_class_best.md` |
| Fig | Confusion matrix + (opsional) PR curve | `confusion_*.png` |

---

## 5. Pitfalls yang harus dihindari

1. **Jangan split acak.** Kalau memakai `train_test_split` biasa, flow dari sesi yang sama
   masuk ke train dan test → skor melonjak artifisial. Notebook sudah memakai LOGO.
2. **Jangan memakai `srcip`/`dstip` sebagai fitur.** Label dibentuk dari IP attacker; model
   akan "menghafal" IP. Ini kesalahan paling sering ditolak reviewer NIDS.
3. **Jangan SMOTE sebelum split.** Notebook memakai oversampling acak di dalam training fold.
4. **Jangan laporkan akurasi saja.** Dengan Normal 45% dan Recon 31%, akurasi 0,9 bisa berarti
   model buta pada 5 kelas lain.
5. **Jangan gabungkan `attack_cat` dan `label` sebagai dua target sekaligus.** Notebook memakai
   `attack_cat` (7 kelas) untuk multiclass dan `label` untuk metrik biner.
6. **Jangan menambah `session_id`/`scenario` sebagai fitur.** Notebook hanya memakainya sebagai
   group/metadata.

---

## 6. Batasan yang wajib ditulis (threats to validity)

1. Hanya **2 sesi** → 2 fold; varians estimasi besar.
2. Kedua sesi berbagi snapshot, tool, dan topologi yang sama → bukan run independen penuh.
3. Volume dan komposisi Normal berbeda antar-run (lihat §1) → *class prior* tidak stabil.
4. Attacker tunggal (10.10.30.10); tidak ada multi-vektor.
5. Label berbasis window + partisipasi IP attacker, bukan *ground truth* generator.
6. `ct_*` bukan bit-identik dengan UNSW-NB15 dan berpotensi membawa jejak IP.
7. Fitur timing (`Sjit`, `Djit`, `Sintpkt`, `Dintpkt`, `tcprtt`) banyak bernilai nol; `Djit`
   null pada 11.010 baris (diimputasi median).
8. Model hanya baseline; tidak ada tuning agresif — dan itu memang tujuannya.

---

## 7. Catatan teknis tentang repo ini

- Notebook **belum pernah dieksekusi** di mesin lokal: sandbox menolak akses ke scikit-learn
  yang saya pasang untuk uji. Sintaks sudah divalidasi (`py_compile`), logika sudah ditelaah,
  tetapi **jalankan `QUICK = True` lebih dulu** di Kaggle untuk menangkap kesalahan runtime
  (nama kolom, versi pandas/sklearn) sebelum run penuh.
- Folder `.vendor/` (sisa instalasi uji) gagal dihapus dari dalam sandbox. Hapus manual:
  ```powershell
  Remove-Item -Recurse -Force .vendor
  ```
  Folder ini sudah masuk `.gitignore`.
- `dataset/ml/lab_flows.csv` juga di-`.gitignore` (49 MB). Simpan di Kaggle Dataset atau
  regenerasi dengan `ml/prepare_kaggle_dataset.py`.
