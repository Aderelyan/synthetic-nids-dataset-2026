"""Baseline ML untuk dataset lab.

Pelatihan TIDAK dijalankan di repo ini: eksperimen dilakukan di Kaggle (CPU), sesuai
kesepakatan. Berkas ini hanya penunjuk agar tidak menyesatkan.

Pakai:
  1. python ml/prepare_kaggle_dataset.py      -> dataset/ml/lab_flows.csv
  2. unggah lab_flows.csv sebagai Kaggle Dataset bernama "lab-flows"
  3. buka ml/kaggle_nids_baseline.ipynb di Kaggle (QUICK=True dulu, lalu False)

Protokol lengkap ada di ml/README-kaggle.md (Leave-One-Session-Out, DT/kNN/MLP,
ablasi fitur turunan IP, macro F1 + PR-AUC + recall@FPR1%).
"""
from pathlib import Path

if __name__ == "__main__":
    print(__doc__)
    print("notebook:", Path(__file__).with_name("kaggle_nids_baseline.ipynb").resolve())
