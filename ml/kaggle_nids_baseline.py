# %% [markdown]
# # Baseline ML — Synthetic NIDS Dataset 2026 (lab)
#
# Protokol evaluasi yang dipakai:
#
# * **Unit analisis**: flow jaringan (satu baris = satu flow).
# * **Fitur**: kolom UNSW-NB15 **tanpa** `srcip`/`dstip` (identifier) dan tanpa
#   `Stime`/`Ltime` (timestamp = kebocoran window label).
# * **Dua set fitur** (ablasi anti-leakage):
#   - `all`  : semua fitur tersisa, termasuk `ct_*` dan `is_sm_ips_ports`
#   - `noip` : `is_sm_ips_ports` + 9 kolom `ct_*` dibuang (fitur turunan IP/port)
# * **Validasi utama**: Leave-One-Group-Out, **group = `session_id`** (`run-1`, `run-2`).
#   Menguji generalisasi ke sesi capture yang belum dilihat; bukan split acak.
# * **Model**: Decision Tree, kNN, MLP (baseline, bukan klaim SOTA).
# * **Imbalance**: `class_weight='balanced'` untuk DT; **balanced training partition
#   (cap 15k/kelas)** untuk kNN/MLP — tanpa SMOTE.
# * **Metrik**: macro F1, per-class F1, PR-AUC macro (one-vs-rest), balanced accuracy,
#   confusion matrix, dan metrik biner attack-vs-normal (PR-AUC + recall pada FPR ≤ 1%).
#
# Dengan 2 sesi, LOGO menghasilkan 2 fold: `train run-1 → test run-2` dan sebaliknya.
# Kedua sesi memuat ketujuh kelas, sehingga tidak ada kelas yang hilang di training.

# %% [markdown]
# ## 0. Setup
#
# Upload `lab_flows.csv` (hasil `ml/prepare_kaggle_dataset.py`) sebagai dataset Kaggle
# bernama **lab-flows**. Path di bawah otomatis menyesuaikan.

# %%
import json
import os
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")

# Semua bisa di-override lewat environment variable (opsional).
SEED = 42
QUICK = False            # <-- ubah ke True untuk smoke test (~2 menit, 8k baris, 1 model)
PER_CLASS_CAP = int(os.environ.get("NIDS_CAP", 15_000))   # balanced train per kelas
KNN_MAX_TRAIN = int(os.environ.get("NIDS_KNN_MAX", 30_000))

_default_out = "/kaggle/working/results" if Path("/kaggle").exists() else "ml/results/kaggle"
OUT = Path(os.environ.get("NIDS_OUT", _default_out))
OUT.mkdir(parents=True, exist_ok=True)

CANDIDATES = [
    Path("/kaggle/input/lab-flows/lab_flows.csv"),
    Path("/kaggle/input/lab-flows/dataset/ml/lab_flows.csv"),
    Path("/kaggle/input/synthetic-nids-lab/lab_flows.csv"),
    Path("dataset/ml/lab_flows.csv"),
]
DATA_PATH = next((p for p in CANDIDATES if p.exists()), None)
assert DATA_PATH is not None, "lab_flows.csv tidak ditemukan di /kaggle/input."
print("data   :", DATA_PATH)
print("output :", OUT)

# %% [markdown]
# ## 1. Muat & audit

# %%
df = pd.read_csv(DATA_PATH, low_memory=False)
print(f"shape = {df.shape}\n")
print("kelas x sesi:")
print(pd.crosstab(df["attack_cat"], df["session_id"], margins=True, margins_name="TOTAL"))
print("\nproporsi attack per sesi:")
print(df.groupby("session_id")["label"].agg(["count", "mean"]).round(3))
print("\nnull terbanyak:")
print(df.isna().sum().sort_values(ascending=False).head(4))

# %%
import sklearn
print("pandas", pd.__version__, "| numpy", np.__version__, "| sklearn", sklearn.__version__)

# %% [markdown]
# ## 2. Definisi fitur
#
# `srcip`/`dstip` hanya dipakai untuk *labeling* di pipeline, tidak boleh jadi fitur:
# label didefinisikan lewat partisipasi IP attacker, jadi model bisa "menghafal IP" —
# itu leakage, bukan deteksi.
#
# `ct_*` dihitung dengan kunci IP (mis. `ct_srv_src` = jumlah (service, src-IP) dalam 100
# koneksi terakhir), sehingga juga bisa mengodekan identitas penyerang. Karena itu diuji
# sebagai ablasi `all` vs `noip`.

# %%
ID_COLS = ["srcip", "dstip", "Stime", "Ltime"]
LABEL_COLS = ["label", "attack_cat"]
META_COLS = ["session_id", "archive", "scenario"]
CAT_COLS = ["proto", "state", "service"]
IP_DERIVED = [
    "is_sm_ips_ports", "ct_state_ttl", "ct_srv_src", "ct_srv_dst", "ct_dst_ltm",
    "ct_src_ltm", "ct_src_dport_ltm", "ct_dst_sport_ltm", "ct_dst_src_ltm",
]

ALL_FEATURES = [c for c in df.columns if c not in ID_COLS + LABEL_COLS + META_COLS]
FEATURE_SETS = {
    "all": ALL_FEATURES,
    "noip": [c for c in ALL_FEATURES if c not in IP_DERIVED],
}
for k, v in FEATURE_SETS.items():
    print(f"features[{k}] = {len(v)} kolom")

if QUICK:
    df = df.sample(n=min(8000, len(df)), random_state=SEED).reset_index(drop=True)
    print("QUICK mode:", df.shape)

# %% [markdown]
# ## 3. Preprocessing & model
#
# Encoder/scaler ada **di dalam** Pipeline, jadi saat CV hanya di-fit pada training fold.

# %%
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.neighbors import KNeighborsClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.tree import DecisionTreeClassifier


def make_preprocessor(features):
    cats = [c for c in features if c in CAT_COLS]
    nums = [c for c in features if c not in CAT_COLS]
    return ColumnTransformer(
        [
            ("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=False), cats),
            ("num", Pipeline([("imp", SimpleImputer(strategy="median")),
                              ("sc", StandardScaler())]), nums),
        ],
        remainder="drop",
    )


def make_model(name):
    if name == "dt":
        return DecisionTreeClassifier(min_samples_leaf=5, class_weight="balanced",
                                      random_state=SEED)
    if name == "knn":
        return KNeighborsClassifier(n_neighbors=5, weights="distance", n_jobs=-1)
    if name == "mlp":
        return MLPClassifier(hidden_layer_sizes=(64, 32), alpha=1e-4, batch_size=512,
                             learning_rate_init=1e-3, max_iter=80, early_stopping=True,
                             n_iter_no_change=5, validation_fraction=0.1, random_state=SEED)
    raise ValueError(name)

# %% [markdown]
# ## 4. Balanced training partition (tanpa SMOTE)
#
# Untuk tiap fold, training partition dibuat seimbang: kelas mayoritas di-subsample,
# kelas minoritas diduplikasi acak, semuanya ke `PER_CLASS_CAP` per kelas. Duplikasi acak
# tidak menciptakan titik baru seperti SMOTE, sehingga tidak ada risiko kebocoran sintetis.

# %%
def balanced_train(idx, y, per_class=PER_CLASS_CAP):
    rng = np.random.default_rng(SEED)
    parts = []
    for c in np.unique(y[idx]):
        pool = idx[y[idx] == c]
        parts.append(rng.choice(pool, size=per_class, replace=len(pool) < per_class))
    return np.concatenate(parts)

# %% [markdown]
# ## 5. Metrik

# %%
from sklearn.metrics import (average_precision_score, balanced_accuracy_score,
                             classification_report, confusion_matrix, f1_score,
                             roc_curve)


def evaluate(y_true, y_pred, proba, classes):
    rep = classification_report(y_true, y_pred, labels=list(classes), output_dict=True,
                                zero_division=0)
    per_class = pd.DataFrame({
        "class": list(classes),
        "precision": [rep[c]["precision"] for c in classes],
        "recall": [rep[c]["recall"] for c in classes],
        "f1": [rep[c]["f1-score"] for c in classes],
        "support": [rep[c]["support"] for c in classes],
    })
    aps = {}
    for i, c in enumerate(classes):
        y_bin = (y_true == c).astype(int)
        if y_bin.sum():
            aps[c] = average_precision_score(y_bin, proba[:, i])
    return {
        "macro_f1": f1_score(y_true, y_pred, average="macro", zero_division=0),
        "weighted_f1": f1_score(y_true, y_pred, average="weighted", zero_division=0),
        "balanced_acc": balanced_accuracy_score(y_true, y_pred),
        "macro_pr_auc": float(np.mean(list(aps.values()))) if aps else np.nan,
        "per_class": per_class, "per_class_ap": aps,
        "confusion": confusion_matrix(y_true, y_pred, labels=list(classes)),
    }


def binary_view(y_bin, p_attack):
    ap = average_precision_score(y_bin, p_attack)
    fpr, tpr, _ = roc_curve(y_bin, p_attack)
    mask = fpr <= 0.01
    return {"bin_pr_auc": ap,
            "recall_at_fpr1": float(tpr[mask].max()) if mask.any() else np.nan}

# %% [markdown]
# ## 6. Protokol CV: Leave-One-Session-Out

# %%
from sklearn.model_selection import LeaveOneGroupOut

y = df["attack_cat"].astype(str).values
groups = df["session_id"].values
classes = np.array(sorted(df["attack_cat"].astype(str).unique()))
y_bin = df["label"].values

splits = list(LeaveOneGroupOut().split(df, y, groups))
for tr, te in splits:
    print(f"train={groups[tr][0]:<6} ({len(tr):>6})  test={groups[te][0]:<6} ({len(te):>6})")

# %% [markdown]
# ## 7. Jalankan matriks eksperimen
#
# 3 model × 2 set fitur × 2 fold. Perkiraan di CPU Kaggle: DT < 2 mnt, kNN ~10 mnt,
# MLP ~5 mnt per set fitur.

# %%
MODELS = ["dt"] if QUICK else ["dt", "knn", "mlp"]
FSETS = ["all"] if QUICK else ["all", "noip"]

rows, per_class_rows, ap_rows, confusions = [], [], [], {}

for fs in FSETS:
    feats = FEATURE_SETS[fs]
    X = df[feats]
    for fold, (tr, te) in enumerate(splits):
        for mname in MODELS:
            tr_use = tr if mname == "dt" else balanced_train(tr, y)
            if mname == "knn" and len(tr_use) > KNN_MAX_TRAIN:
                tr_use = np.random.default_rng(SEED).choice(tr_use, KNN_MAX_TRAIN, replace=False)

            pipe = Pipeline([("prep", make_preprocessor(feats)), ("clf", make_model(mname))])
            pipe.fit(X.iloc[tr_use], y[tr_use])

            order = list(pipe.classes_)
            proba = pipe.predict_proba(X.iloc[te])[:, [order.index(c) for c in classes]]
            pred = classes[proba.argmax(1)]

            res = evaluate(y[te], pred, proba, classes)
            bin_res = binary_view(y_bin[te], 1.0 - proba[:, list(classes).index("Normal")])
            tag = f"{mname}-{fs}-{groups[te][0]}"
            rows.append({"model": mname, "features": fs, "fold": fold,
                         "train_session": groups[tr][0], "test_session": groups[te][0],
                         "n_train": len(tr_use), "n_test": len(te),
                         **{k: res[k] for k in ("macro_f1", "weighted_f1",
                                                "balanced_acc", "macro_pr_auc")},
                         **bin_res})
            pc = res["per_class"].copy()
            pc["model"] = mname
            pc["features"] = fs
            pc["test_session"] = groups[te][0]
            per_class_rows.append(pc)
            ap_rows.append({"model": mname, "features": fs, "test_session": groups[te][0],
                            **{f"ap_{k}": v for k, v in res["per_class_ap"].items()}})
            confusions[tag] = res["confusion"]
            print(f"{tag:<22} macroF1={res['macro_f1']:.3f} "
                  f"macroPR-AUC={res['macro_pr_auc']:.3f} "
                  f"rec@FPR1%={bin_res['recall_at_fpr1']:.3f}")

metrics = pd.DataFrame(rows)
per_class = pd.concat(per_class_rows, ignore_index=True)
metrics.to_csv(OUT / "metrics_by_fold.csv", index=False)
per_class.to_csv(OUT / "per_class_by_fold.csv", index=False)
pd.DataFrame(ap_rows).to_csv(OUT / "per_class_ap_by_fold.csv", index=False)

cols = ["macro_f1", "weighted_f1", "balanced_acc", "macro_pr_auc",
        "bin_pr_auc", "recall_at_fpr1"]
summary = metrics.groupby(["model", "features"])[cols].agg(["mean", "std"]).round(4)
summary.to_csv(OUT / "metrics_summary.csv")
print("\n=== ringkasan (mean / std antar sesi) ===")
print(summary.to_string())

# %% [markdown]
# ## 8. Tabel & gambar untuk artikel

# %%
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

best_key = metrics.groupby(["model", "features"])["macro_pr_auc"].mean().idxmax()
print("model terbaik (macro PR-AUC):", best_key)

sel = per_class[(per_class.model == best_key[0]) & (per_class.features == best_key[1])]
piv = sel.pivot_table(index="class", columns="test_session", values="f1").round(3)
piv["mean"] = piv.mean(axis=1).round(3)
piv.to_csv(OUT / "table_per_class_best.csv")

md = ["| class | " + " | ".join(map(str, piv.columns)) + " |",
      "|---" * (len(piv.columns) + 1) + "|"]
for cls, r in piv.iterrows():
    md.append(f"| {cls} | " + " | ".join(f"{v:.3f}" for v in r.values) + " |")
(OUT / "table_per_class_best.md").write_text("\n".join(md), encoding="utf-8")
print("\n".join(md))

for tag, cm in confusions.items():
    fig, ax = plt.subplots(figsize=(6.6, 5.6))
    cmn = cm / np.clip(cm.sum(axis=1, keepdims=True), 1, None)
    im = ax.imshow(cmn, cmap="Blues", vmin=0, vmax=1)
    ax.set_xticks(range(len(classes)), classes, rotation=45, ha="right")
    ax.set_yticks(range(len(classes)), classes)
    ax.set_xlabel("predicted"); ax.set_ylabel("actual")
    for i in range(len(classes)):
        for j in range(len(classes)):
            ax.text(j, i, f"{cmn[i, j]:.2f}", ha="center", va="center", fontsize=7,
                    color="white" if cmn[i, j] > 0.55 else "black")
    fig.colorbar(im, ax=ax, fraction=0.046)
    fig.tight_layout()
    fig.savefig(OUT / f"confusion_{tag}.png", dpi=160)
    plt.close(fig)

(OUT / "run_manifest.json").write_text(json.dumps({
    "data": str(DATA_PATH), "seed": SEED, "per_class_cap": PER_CLASS_CAP,
    "knn_max_train": KNN_MAX_TRAIN, "models": MODELS, "feature_sets": FSETS,
    "n_rows": int(len(df)), "sklearn": sklearn.__version__,
}, indent=2), encoding="utf-8")

print("selesai ->", OUT)

# %% [markdown]
# ## 9. Cara membaca hasil (bahan Bab 4)
#
# 1. **Jangan pakai akurasi.** Normal 45% dan Reconnaissance 31% dari dataset; akurasi tinggi
#    bisa berarti model hanya menebak dua kelas itu. Pakai macro F1 dan PR-AUC.
# 2. **Bandingkan `all` vs `noip`.** Jika `all` jauh lebih tinggi, model memanfaatkan jejak
#    IP (`ct_*`), bukan perilaku. Angka `noip` adalah klaim yang bisa dipertahankan.
# 3. **Bandingkan kedua arah fold.** Selisih besar = distribusi antar-sesi tidak seragam
#    (Normal: 9.357 di run-1 vs 66.025 di run-2). Laporkan sebagai temuan + support per kelas,
#    bukan disembunyikan.
# 4. **`recall_at_fpr1`** adalah angka paling relevan untuk operasi SOC; sebutkan ambangnya.
# 5. **Jangan klaim SOTA.** Tulis: "baseline yang menunjukkan dataset dapat dipakai untuk
#    klasifikasi, dengan batasan generalisasi antar-sesi."

# %% [markdown]
# ## 10. (Opsional) Cross-dataset dengan UNSW-NB15
#
# Langkah: tambahkan dataset Kaggle UNSW-NB15, samakan nama kolom (`attack_cat`, `label`),
# ambil irisan fitur (drop IP), harmonisasi `proto`/`service`/`state`, lalu jalankan dua arah
# `train UNSW → test lab` dan `train lab → test UNSW`. Laporkan hanya **shared classes**
# (6 + Normal); Brute Force, Fuzzers, Generic, Shellcode, Worms dilaporkan sebagai *unseen*.
#
# ```python
# shared = [c for c in FEATURE_SETS["noip"] if c in unsw.columns and c != "ct_flw_http_mthd"]
# pipe = Pipeline([("prep", make_preprocessor(shared)), ("clf", make_model("dt"))])
# pipe.fit(unsw[shared], unsw["attack_cat"])
# proba = pipe.predict_proba(lab[shared])   # kolom mengikuti pipe.classes_
# ```
