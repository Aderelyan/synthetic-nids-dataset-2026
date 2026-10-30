# %% [markdown]
# # Validasi dataset NIDS sintetis terhadap UNSW-NB15
#
# Notebook ini menjawab satu pertanyaan: **apakah dataset kita bisa dipakai untuk ML,
# dan apakah perilakunya punya kemiripan dengan data nyata?** Bukan untuk mengejar SOTA.
#
# Urutan eksperimen:
#
# | Tahap | Train | Test | Yang dibuktikan |
# |---|---|---|---|
# | **A** | satu sesi sintetis | sesi sintetis lainnya | dataset sendiri *learnable* |
# | **B** | UNSW official train | UNSW official test | pipeline benar + baseline pembanding |
# | **C** | sintetis | UNSW | transfer sintetis → nyata |
# | **C** | UNSW | sintetis | transfer nyata → sintetis |
# | **D** | sintetis (satu sesi) + UNSW train | sesi sintetis lain + UNSW test | apakah gabungan membantu |
# | **E** | 2 dari 3 group | 1 group | variasi, supplementary saja |
#
# Aturan yang dipakai:
#
# * **Tidak ada random split.** Tahap A memakai *leave-one-session-out*; B memakai
#   split resmi UNSW; C adalah cross-domain; D memakai sesi yang belum dilihat;
#   E memakai `GroupKFold` per domain/sesi.
# * **Fitur identitas dibuang**: `srcip`, `dstip`, `Stime`, `Ltime`. Label sintetis
#   dibentuk dari window dan IP penyerang, jadi IP adalah kebocoran.
# * **Dua set fitur**: `full` (semua fitur UNSW yang tersisa) dan `core` (tanpa
#   `ct_*`, port, dan TCP sequence number). `core` adalah klaim yang lebih konservatif.
# * **Label cross-domain** hanya irisan kelas kedua dataset. Kelas yang hanya ada di
#   salah satu dataset tidak dipaksa masuk.
# * **Metrik**: macro F1, balanced accuracy, macro PR-AUC, binary PR-AUC, dan
#   recall pada FPR ≤ 1%. Akurasi tidak dipakai karena distribusi kelas timpang.
#
# > Path Kaggle: dataset biasanya di-mount di `/kaggle/input/<slug>/...`, bukan
# > `/kaggle/input/datasets/<owner>/<slug>/...` (itu URL web). Sel berikut mencari
# > beberapa kemungkinan path sekaligus.
# >
# > **Smoke test:** ubah `QUICK = False` menjadi `QUICK = True` di sel setup,
# > jalankan semua sel, lalu kembalikan ke `False` untuk run penuh.

# %% [markdown]
# ## 0. Setup dan pencarian path

# %%
import glob
import json
import os
import time
import warnings
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")

SEED = 42
QUICK = False  # <-- ubah ke True untuk smoke test ( +/- 3 menit)
if os.environ.get("NIDS_QUICK") == "1":
    QUICK = True
RUN_GROUPED_CV = True

OUT = Path(os.environ.get(
    "NIDS_OUT",
    "/kaggle/working/results" if Path("/kaggle").exists() else "ml/results/crossdataset",
))
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "confusion").mkdir(exist_ok=True)


def first_file(candidates):
    for p in candidates:
        if p and Path(p).is_file():
            return Path(p)
    return None


def glob_first(patterns):
    for pat in patterns:
        hits = sorted(glob.glob(pat, recursive=True))
        if hits:
            return Path(hits[0])
    return None


synth_candidates = [
    os.environ.get("NIDS_SYNTH_PATH"),
    "/kaggle/input/syntetic-dataset-v1/lab_flows.csv",
    "/kaggle/input/syntetic-dataset-v1/dataset/ml/lab_flows.csv",
    "/kaggle/input/datasets/renoaderelyan/syntetic-dataset-v1/lab_flows.csv",
    "/kaggle/input/synthetic-nids-lab/lab_flows.csv",
    "/kaggle/input/lab-flows/lab_flows.csv",
    "dataset/ml/lab_flows.csv",
]
SYNTH_PATH = first_file(synth_candidates) or glob_first([
    "/kaggle/input/**/lab_flows.csv",
])

unsw_dir = os.environ.get("NIDS_UNSW_DIR")
unsw_train_candidates = [
    str(Path(unsw_dir) / "UNSW_NB15_training-set.csv") if unsw_dir else None,
    "/kaggle/input/unsw-nb15/UNSW_NB15_training-set.csv",
    "/kaggle/input/datasets/mrwellsdavid/unsw-nb15/UNSW_NB15_training-set.csv",
]
unsw_test_candidates = [
    str(Path(unsw_dir) / "UNSW_NB15_testing-set.csv") if unsw_dir else None,
    "/kaggle/input/unsw-nb15/UNSW_NB15_testing-set.csv",
    "/kaggle/input/datasets/mrwellsdavid/unsw-nb15/UNSW_NB15_testing-set.csv",
]
UNSW_TRAIN_PATH = first_file(unsw_train_candidates) or glob_first([
    "/kaggle/input/**/UNSW_NB15_training-set.csv",
])
UNSW_TEST_PATH = first_file(unsw_test_candidates) or glob_first([
    "/kaggle/input/**/UNSW_NB15_testing-set.csv",
])

if SYNTH_PATH is None or UNSW_TRAIN_PATH is None or UNSW_TEST_PATH is None:
    print("Isi /kaggle/input:")
    root = Path("/kaggle/input")
    if root.exists():
        for p in sorted(root.iterdir()):
            print(" -", p)
    raise FileNotFoundError(
        "Dataset belum lengkap. Tambahkan `syntetic-dataset-v1` dan "
        "`mrwellsdavid/unsw-nb15` lewat panel Add Input."
    )

print("synthetic :", SYNTH_PATH)
print("UNSW train:", UNSW_TRAIN_PATH)
print("UNSW test :", UNSW_TEST_PATH)
print("output    :", OUT)

# %% [markdown]
# ## 1. Muat, bersihkan label, dan audit
#
# Label dinormalisasi agar variasi ejaan (`Backdoors`, ` backdoor `, `DoS`) tidak
# menghasilkan kelas palsu. Label biner selalu diturunkan dari `attack_cat`, bukan
# dari kolom `label` yang bisa tidak konsisten antar-versi dataset.

# %%
CANON = {
    "normal": "Normal",
    "analysis": "Analysis",
    "backdoor": "Backdoor",
    "back door": "Backdoor",
    "backdoors": "Backdoor",
    "dos": "DoS",
    "ddos": "DoS",
    "exploits": "Exploits",
    "exploit": "Exploits",
    "fuzzers": "Fuzzers",
    "fuzzer": "Fuzzers",
    "generic": "Generic",
    "reconnaissance": "Reconnaissance",
    "recon": "Reconnaissance",
    "shellcode": "Shellcode",
    "worms": "Worms",
    "worm": "Worms",
    "brute force": "Brute Force",
    "bruteforce": "Brute Force",
}
RENAME = {
    c.lower(): c
    for c in ["Sload", "Dload", "Spkts", "Dpkts", "Sjit", "Djit",
              "Stime", "Ltime", "Sintpkt", "Dintpkt"]
}


def canon_label(s):
    raw = s.astype("string").str.strip()
    key = (raw.str.lower()
              .str.replace(r"[\s_\-]+", " ", regex=True)
              .str.strip())
    return key.map(CANON).fillna(raw).fillna("").astype(str)


def parse_port(s):
    txt = s.astype("string").str.strip()
    out = pd.to_numeric(txt, errors="coerce")
    mask = txt.str.lower().str.startswith("0x").fillna(False)
    if mask.any():
        out.loc[mask] = txt.loc[mask].map(lambda x: int(str(x), 16))
    return out.astype(float)


def clean_frame(df, domain, session):
    df = df.copy()
    df.columns = [str(c).strip().lstrip("\ufeff") for c in df.columns]
    df = df.rename(columns={
        c: RENAME[c.lower()] for c in df.columns if c.lower() in RENAME
    })
    if "attack_cat" not in df.columns:
        raise KeyError(f"{domain}: kolom attack_cat tidak ada")
    df["attack_cat"] = canon_label(df["attack_cat"])
    df = df[df["attack_cat"].str.len() > 0].copy()
    df["label"] = (df["attack_cat"] != "Normal").astype(int)
    if "session_id" not in df.columns:
        df["session_id"] = str(session)
    else:
        df["session_id"] = df["session_id"].fillna(str(session)).astype(str)
    df["domain"] = domain
    df["group_id"] = domain + ":" + df["session_id"]
    for c in ("proto", "state", "service"):
        if c in df.columns:
            s = df[c].astype("string").str.strip().str.lower()
            df[c] = s.fillna("unknown").astype(str)
    for c in ("sport", "dsport"):
        if c in df.columns:
            df[c] = parse_port(df[c])
    return df.reset_index(drop=True)


syn = clean_frame(pd.read_csv(SYNTH_PATH, low_memory=False), "synthetic", None)
unsw_train = clean_frame(pd.read_csv(UNSW_TRAIN_PATH, low_memory=False), "unsw", "train")
unsw_test = clean_frame(pd.read_csv(UNSW_TEST_PATH, low_memory=False), "unsw", "test")

# UNSW official train/test berasal dari capture yang sama; untuk grouped CV
# keduanya diperlakukan sebagai satu group agar tidak dianggap independen.
unsw_train["group_id"] = "unsw:all"
unsw_test["group_id"] = "unsw:all"


def cap_per_class(df, n, cols):
    parts = []
    for _, g in df.groupby(cols, sort=False):
        parts.append(g.sample(n=min(len(g), n), random_state=SEED))
    return pd.concat(parts, ignore_index=True)


if QUICK:
    syn = cap_per_class(syn, 500, ["session_id", "attack_cat"])
    unsw_train = cap_per_class(unsw_train, 500, ["attack_cat"])
    unsw_test = cap_per_class(unsw_test, 250, ["attack_cat"])

print("synthetic :", syn.shape, "| sesi:", syn["session_id"].nunique())
print(pd.crosstab(syn["attack_cat"], syn["session_id"], margins=True, margins_name="TOTAL"))
print("\nUNSW train:", unsw_train.shape, "| UNSW test:", unsw_test.shape)
print("UNSW train classes:")
print(unsw_train["attack_cat"].value_counts().to_string())
print("UNSW test classes:")
print(unsw_test["attack_cat"].value_counts().to_string())
print("\nnull terbanyak (synthetic):")
print(syn.isna().sum().sort_values(ascending=False).head(5))

# %% [markdown]
# ## 2. Definisi fitur dan irisan kelas
#
# `full` memakai semua fitur numerik/kategorikal yang tersisa. `core` membuang
# fitur turunan IP (`ct_*`, `is_sm_ips_ports`), port, dan TCP sequence number.
# Perbandingan `full` vs `core` adalah ablasi anti-kebocoran, bukan tuning.

# %%
COMMON = [c for c in syn.columns if c in unsw_train.columns]
ID_COLS = ["srcip", "dstip", "Stime", "Ltime"]
LABEL_COLS = ["label", "attack_cat"]
META_COLS = ["session_id", "archive", "scenario", "domain", "group_id"]
CAT_COLS = [c for c in ["proto", "state", "service"] if c in COMMON]
ALL_FEATURES = [
    c for c in COMMON
    if c not in ID_COLS + LABEL_COLS + META_COLS
]
IP_DERIVED = [
    c for c in [
        "is_sm_ips_ports", "ct_state_ttl", "ct_srv_src", "ct_srv_dst",
        "ct_dst_ltm", "ct_src_ltm", "ct_src_dport_ltm", "ct_dst_sport_ltm",
        "ct_dst_src_ltm",
    ] if c in ALL_FEATURES
]
PORT_COLS = [c for c in ["sport", "dsport"] if c in ALL_FEATURES]
HIGH_CARD = [c for c in ["stcpb", "dtcpb"] if c in ALL_FEATURES]
NOIP = [c for c in ALL_FEATURES if c not in IP_DERIVED]
CORE = [c for c in NOIP if c not in PORT_COLS + HIGH_CARD]
FEATURE_SETS = {"full": ALL_FEATURES, "noip": NOIP, "core": CORE}
FSETS = ["full", "core"]

NUM_COLS = [c for c in ALL_FEATURES if c not in CAT_COLS]
for d in (syn, unsw_train, unsw_test):
    missing_cols = [c for c in ALL_FEATURES if c not in d.columns]
    if missing_cols:
        raise KeyError(f"Kolom fitur hilang: {missing_cols}")
    for c in NUM_COLS:
        d[c] = pd.to_numeric(d[c], errors="coerce")

SYN_CLASSES = sorted(syn["attack_cat"].unique())
UNSW_CLASSES = sorted(pd.concat([unsw_train, unsw_test], ignore_index=True)["attack_cat"].unique())
SHARED = sorted(set(SYN_CLASSES) & set(UNSW_CLASSES))

print("fitur full/noip/core:", {k: len(v) for k, v in FEATURE_SETS.items()})
print("kelas synthetic:", SYN_CLASSES)
print("kelas UNSW     :", UNSW_CLASSES)
print("irisan kelas   :", SHARED)
print("hanya synthetic:", sorted(set(SYN_CLASSES) - set(UNSW_CLASSES)))
print("hanya UNSW     :", sorted(set(UNSW_CLASSES) - set(SYN_CLASSES)))
if len(SHARED) < 2:
    raise RuntimeError("Irisan kelas terlalu kecil; cek normalisasi label.")

# %% [markdown]
# ## 3. Preprocessing, model, dan metrik
#
# Imputer/encoder berada **di dalam** `Pipeline`, jadi hanya di-fit pada train.
# Model sengaja sederhana: Decision Tree (transparan) dan Random Forest (kuat,
# tidak terlalu mahal di CPU). kNN/MLP ada di notebook baseline terpisah.

# %%
import sklearn
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    average_precision_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    roc_curve,
)
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder
from sklearn.tree import DecisionTreeClassifier

print("pandas", pd.__version__, "| numpy", np.__version__, "| sklearn", sklearn.__version__)


def make_preprocessor(features):
    cats = [c for c in features if c in CAT_COLS]
    nums = [c for c in features if c not in CAT_COLS]
    return ColumnTransformer(
        [
            ("cat", Pipeline([
                ("imp", SimpleImputer(strategy="constant", fill_value="unknown")),
                ("oh", OneHotEncoder(handle_unknown="ignore", sparse_output=True)),
            ]), cats),
            ("num", SimpleImputer(strategy="median", keep_empty_features=True), nums),
        ],
        sparse_threshold=1.0,
    )


def make_model(name):
    if name == "dt":
        return DecisionTreeClassifier(
            max_depth=14 if QUICK else None,
            min_samples_leaf=5,
            class_weight="balanced",
            random_state=SEED,
        )
    if name == "rf":
        return RandomForestClassifier(
            n_estimators=60 if QUICK else 220,
            max_depth=14 if QUICK else 22,
            min_samples_leaf=3,
            max_features="sqrt",
            class_weight="balanced_subsample",
            n_jobs=-1,
            random_state=SEED,
        )
    raise ValueError(name)


def evaluate(y_true, y_pred, proba, classes):
    labels = list(classes)
    y_true = np.asarray(y_true)
    rep = classification_report(
        y_true, y_pred, labels=labels, output_dict=True, zero_division=0
    )
    per_class = pd.DataFrame({
        "class": labels,
        "precision": [rep[c]["precision"] for c in labels],
        "recall": [rep[c]["recall"] for c in labels],
        "f1": [rep[c]["f1-score"] for c in labels],
        "support": [rep[c]["support"] for c in labels],
    })

    aps = {}
    for i, c in enumerate(labels):
        y_bin = (y_true == c).astype(int)
        if 0 < y_bin.sum() < len(y_bin):
            aps[c] = float(average_precision_score(y_bin, proba[:, i]))

    y_bin = (y_true != "Normal").astype(int)
    if "Normal" in labels:
        p_attack = 1.0 - proba[:, labels.index("Normal")]
    else:
        p_attack = np.ones(len(proba))
    if 0 < y_bin.sum() < len(y_bin):
        bin_pr_auc = float(average_precision_score(y_bin, p_attack))
        fpr, tpr, _ = roc_curve(y_bin, p_attack)
        mask = fpr <= 0.01
        recall_at_fpr1 = float(tpr[mask].max()) if mask.any() else np.nan
    else:
        bin_pr_auc = np.nan
        recall_at_fpr1 = np.nan

    return {
        "macro_f1": float(f1_score(
            y_true, y_pred, labels=labels, average="macro", zero_division=0
        )),
        "weighted_f1": float(f1_score(
            y_true, y_pred, labels=labels, average="weighted", zero_division=0
        )),
        "balanced_acc": float(balanced_accuracy_score(y_true, y_pred)),
        "macro_pr_auc": float(np.mean(list(aps.values()))) if aps else np.nan,
        "bin_pr_auc": bin_pr_auc,
        "recall_at_fpr1": recall_at_fpr1,
        "per_class": per_class,
        "per_class_ap": aps,
        "confusion": confusion_matrix(y_true, y_pred, labels=labels),
    }

# %% [markdown]
# ## 4. Runner eksperimen
#
# Satu fit = satu pasangan train/test. Semua probabilitas disusun ulang mengikuti
# urutan `classes`, sehingga kelas yang tidak ada di train tetap mendapat kolom nol
# dan tidak menggeser argmax.

# %%
ROWS = []
PER_CLASS_ROWS = []
AP_ROWS = []
CONFUSIONS = {}


def slug(s):
    return "".join(ch if ch.isalnum() or ch in "-_." else "-" for ch in str(s))


def run_one(stage, train_name, train_df, tests, features, model_name, classes, tag):
    features = list(features)
    classes = list(classes)
    Xtr = train_df[features]
    ytr = train_df["attack_cat"].to_numpy()

    pipe = Pipeline([
        ("prep", make_preprocessor(features)),
        ("clf", make_model(model_name)),
    ])
    t0 = time.time()
    pipe.fit(Xtr, ytr)
    fit_s = time.time() - t0
    train_classes = list(pipe.classes_)
    missing_train = sorted(set(classes) - set(train_classes))
    fs_name = next(
        (k for k in FEATURE_SETS if f"_{k}_" in tag or tag.endswith(f"_{k}")),
        "unknown",
    )
    print(f"[{stage}] {model_name} {tag} | n_train={len(train_df):,} "
          f"| kelas_train={len(train_classes)} | fit={fit_s:.1f}s")

    for test_name, te in tests.items():
        if te is None or len(te) == 0:
            continue
        raw = pipe.predict_proba(te[features])
        proba = np.zeros((len(te), len(classes)), dtype=float)
        for j, c in enumerate(train_classes):
            if c in classes:
                proba[:, classes.index(c)] = raw[:, j]
        pred = np.asarray(classes, dtype=object)[proba.argmax(axis=1)]
        res = evaluate(te["attack_cat"].to_numpy(), pred, proba, classes)

        run_tag = slug(f"{tag}_{test_name}")
        ROWS.append({
            "stage": stage,
            "model": model_name,
            "features": fs_name,
            "train": train_name,
            "test": test_name,
            "n_train": len(train_df),
            "n_test": len(te),
            "fit_seconds": round(fit_s, 2),
            "n_train_classes": len(train_classes),
            "missing_in_train": "|".join(missing_train),
            **{k: res[k] for k in [
                "macro_f1", "weighted_f1", "balanced_acc", "macro_pr_auc",
                "bin_pr_auc", "recall_at_fpr1",
            ]},
        })

        pc = res["per_class"].copy()
        pc["stage"] = stage
        pc["model"] = model_name
        pc["features"] = fs_name
        pc["test"] = test_name
        PER_CLASS_ROWS.append(pc)
        AP_ROWS.append({
            "stage": stage,
            "model": model_name,
            "features": fs_name,
            "test": test_name,
            **{f"ap_{k}": v for k, v in res["per_class_ap"].items()},
        })
        CONFUSIONS[run_tag] = (res["confusion"], classes, stage, model_name)

        print(f"  {test_name:<22} n={len(te):>7,} "
              f"macroF1={res['macro_f1']:.3f} "
              f"balAcc={res['balanced_acc']:.3f} "
              f"macroPR={res['macro_pr_auc']:.3f} "
              f"rec@FPR1={res['recall_at_fpr1']:.3f}")

# %% [markdown]
# ## 5. Tahap A — validasi internal dataset sintetis
#
# Leave-one-session-out: train `run-1` → test `run-2`, dan sebaliknya. Ini
# mengukur apakah model bertahan pada sesi capture yang belum dilihat, bukan pada
# flow acak dari sesi yang sama.

# %%
for fs in FSETS:
    for m in ["dt", "rf"]:
        for held in sorted(syn["session_id"].unique()):
            tr = syn[syn["session_id"] != held]
            te = syn[syn["session_id"] == held]
            if tr.empty or te.empty:
                continue
            run_one(
                "A_synthetic_internal",
                f"excl-{held}",
                tr,
                {f"syn-{held}": te},
                FEATURE_SETS[fs],
                m,
                SYN_CLASSES,
                f"A_{m}_{fs}_{held}",
            )

# %% [markdown]
# ## 6. Tahap B — validasi internal UNSW-NB15
#
# Memakai split resmi `UNSW_NB15_training-set.csv` / `UNSW_NB15_testing-set.csv`.
# Jangan menggantinya dengan `train_test_split` acak; split resmi adalah pembanding
# yang dipakai literatur, meskipun tetap punya keterbatasan (flow dari capture yang sama).

# %%
for fs in FSETS:
    for m in ["dt", "rf"]:
        run_one(
            "B_unsw_internal",
            "unsw-train",
            unsw_train,
            {"unsw-test": unsw_test},
            FEATURE_SETS[fs],
            m,
            UNSW_CLASSES,
            f"B_{m}_{fs}",
        )

# %% [markdown]
# ## 7. Tahap C — cross-domain dua arah (kelas irisan)
#
# Ini tahap paling penting. Kalau skor internal tinggi tetapi transfer jatuh ke
# level tebak-tebakan, dataset kita belum punya bukti realisme yang kuat.
# Hanya kelas yang ada di kedua dataset yang dievaluasi.

# %%
syn_s = syn[syn["attack_cat"].isin(SHARED)].copy()
unsw_tr_s = unsw_train[unsw_train["attack_cat"].isin(SHARED)].copy()
unsw_te_s = unsw_test[unsw_test["attack_cat"].isin(SHARED)].copy()
syn_sessions = sorted(syn_s["session_id"].unique())

if syn_s.empty or unsw_tr_s.empty or unsw_te_s.empty:
    raise RuntimeError("Data irisan kelas kosong.")

for fs in FSETS:
    for m in ["dt", "rf"]:
        run_one(
            "C_cross_syn_to_unsw",
            "synthetic-all",
            syn_s,
            {"unsw-test": unsw_te_s},
            FEATURE_SETS[fs],
            m,
            SHARED,
            f"C_syn2unsw_{m}_{fs}",
        )
        run_one(
            "C_cross_unsw_to_syn",
            "unsw-train",
            unsw_tr_s,
            {f"syn-{s}": syn_s[syn_s["session_id"] == s] for s in syn_sessions},
            FEATURE_SETS[fs],
            m,
            SHARED,
            f"C_unsw2syn_{m}_{fs}",
        )

# %% [markdown]
# ## 8. Tahap D — training gabungan, test per domain
#
# Train = semua sesi sintetis kecuali satu + UNSW train. Test = sesi sintetis yang
# ditahan + UNSW test. Tidak ada flow dari sesi test yang masuk ke training.
# Domain **tidak** dijadikan fitur; kalau ditambahkan, model bisa menghafal asal
# dataset dan skor gabungan menjadi menyesatkan.

# %%
if len(syn_sessions) >= 2:
    for fs in FSETS:
        for m in ["dt", "rf"]:
            for held in syn_sessions:
                tr = pd.concat(
                    [syn_s[syn_s["session_id"] != held], unsw_tr_s],
                    ignore_index=True,
                )
                tests = {
                    f"syn-{held}": syn_s[syn_s["session_id"] == held],
                    "unsw-test": unsw_te_s,
                }
                run_one(
                    "D_combined",
                    f"all-except-{held}+unsw",
                    tr,
                    tests,
                    FEATURE_SETS[fs],
                    m,
                    SHARED,
                    f"D_{m}_{fs}_{held}",
                )
else:
    print("Tahap D dilewati: butuh minimal dua sesi sintetis.")

# %% [markdown]
# ## 9. Tahap E — grouped CV (supplementary)
#
# `GroupKFold` dengan group = `synthetic:run-1`, `synthetic:run-2`, `unsw:all`.
# Hanya 3 group, jadi hasilnya hanya indikasi variasi; bukan bukti utama.
# Sengaja hanya memakai `core` agar biaya komputasi tetap wajar.

# %%
if RUN_GROUPED_CV:
    pooled = pd.concat([syn_s, unsw_tr_s, unsw_te_s], ignore_index=True)
    groups = pooled["group_id"].astype(str)
    n_splits = min(3, groups.nunique())
    if n_splits >= 2:
        gkf = GroupKFold(n_splits=n_splits)
        for m in ["dt", "rf"]:
            for fold, (tr_idx, te_idx) in enumerate(gkf.split(pooled, groups=groups)):
                tr = pooled.iloc[tr_idx].reset_index(drop=True)
                te = pooled.iloc[te_idx].reset_index(drop=True)
                held = str(te["group_id"].iloc[0])
                run_one(
                    "E_combined_groupcv",
                    f"fold-{fold}",
                    tr,
                    {f"holdout-{held}": te},
                    FEATURE_SETS["core"],
                    m,
                    SHARED,
                    f"E_{m}_core_fold{fold}",
                )
    else:
        print("Tahap E dilewati: group kurang dari 2.")

# %% [markdown]
# ## 10. Ringkasan hasil
#
# Tabel di bawah adalah rata-rata per stage/model/features. Untuk tahap A dan D,
# rata-rata mencakup beberapa sesi; lihat `metrics.csv` untuk angka per test set.
# Jangan hanya membaca rata-rata: variansi antar-sesi bisa besar.

# %%
if not ROWS:
    raise RuntimeError("Tidak ada eksperimen yang berjalan.")

metrics = pd.DataFrame(ROWS)
per_class = pd.concat(PER_CLASS_ROWS, ignore_index=True)
per_class_ap = pd.DataFrame(AP_ROWS)

METRICS = [
    "macro_f1", "weighted_f1", "balanced_acc", "macro_pr_auc",
    "bin_pr_auc", "recall_at_fpr1",
]
metrics.to_csv(OUT / "metrics.csv", index=False)
per_class.to_csv(OUT / "per_class.csv", index=False)
per_class_ap.to_csv(OUT / "per_class_ap.csv", index=False)

summary = (
    metrics.groupby(["stage", "model", "features"])[METRICS]
    .agg(["mean", "std", "count"])
    .round(4)
)
summary.to_csv(OUT / "summary_by_stage.csv")
print("=== ringkasan mean/std/count ===")
print(summary.to_string())

key = (
    metrics.groupby(["stage", "model", "features"])[METRICS]
    .mean().round(4).reset_index()
)
n_runs = (
    metrics.groupby(["stage", "model", "features"])
    .size().rename("n_runs").reset_index()
)
key = key.merge(n_runs, on=["stage", "model", "features"], how="left")
key.to_csv(OUT / "key_results.csv", index=False)

pivot = metrics.pivot_table(
    index=["stage", "model", "features"],
    columns="test",
    values="macro_f1",
    aggfunc="mean",
).round(4)
pivot.to_csv(OUT / "macro_f1_by_test.csv")
print("\n=== macro F1 per test ===")
print(pivot.to_string())

print("\n=== key results ===")
print(key.to_string(index=False))

# %% [markdown]
# ## 11. Gambar confusion matrix dan laporan ringkas

# %%
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def safe_name(s):
    return slug(s)[:120]


for tag, (cm, labels, stage, model) in CONFUSIONS.items():
    cm = np.asarray(cm, dtype=float)
    norm = cm / np.clip(cm.sum(axis=1, keepdims=True), 1, None)
    fig, ax = plt.subplots(figsize=(7.4, 6.2))
    im = ax.imshow(norm, cmap="Blues", vmin=0, vmax=1)
    ax.set_xticks(range(len(labels)), labels, rotation=45, ha="right")
    ax.set_yticks(range(len(labels)), labels)
    ax.set_xlabel("predicted")
    ax.set_ylabel("actual")
    ax.set_title(f"{stage} | {model}")
    for i in range(len(labels)):
        for j in range(len(labels)):
            ax.text(
                j, i, f"{norm[i, j]:.2f}",
                ha="center", va="center", fontsize=7,
                color="white" if norm[i, j] > 0.55 else "black",
            )
    fig.colorbar(im, ax=ax, fraction=0.046)
    fig.tight_layout()
    fig.savefig(OUT / "confusion" / f"{safe_name(tag)}.png", dpi=150)
    plt.close(fig)


def to_md(df):
    cols = list(df.columns)
    out = [
        "| " + " | ".join(map(str, cols)) + " |",
        "|" + "|".join(["---"] * len(cols)) + "|",
    ]
    for _, row in df.iterrows():
        vals = []
        for v in row:
            if isinstance(v, (float, np.floating)):
                vals.append(f"{v:.4f}")
            else:
                vals.append(str(v))
        out.append("| " + " | ".join(vals) + " |")
    return "\n".join(out)


def stage_mean(stage, col="macro_f1"):
    s = metrics.loc[metrics["stage"] == stage, col]
    return float(s.mean()) if len(s) else float("nan")


a = stage_mean("A_synthetic_internal")
c = stage_mean("C_cross_syn_to_unsw")
ratio = c / a if np.isfinite(a) and a > 0 else np.nan

md = [
    "# Hasil validasi dataset NIDS sintetis vs UNSW-NB15",
    "",
    f"- Mode quick: **{QUICK}**",
    f"- Synthetic: `{SYNTH_PATH}` — {len(syn):,} baris, sesi {syn_sessions}",
    f"- UNSW train/test: `{UNSW_TRAIN_PATH}` / `{UNSW_TEST_PATH}`",
    f"- Kelas synthetic: {', '.join(SYN_CLASSES)}",
    f"- Kelas UNSW: {', '.join(UNSW_CLASSES)}",
    f"- Irisan cross-domain: {', '.join(SHARED)}",
    "",
    "## Ringkasan",
    "",
    to_md(key),
    "",
    "## Rasio transfer",
    "",
    f"- Macro F1 internal synthetic (A): **{a:.4f}**",
    f"- Macro F1 synthetic → UNSW (C): **{c:.4f}**",
    f"- Rasio C/A: **{ratio:.2f}**" if np.isfinite(ratio) else "- Rasio C/A: n/a",
    "",
    "## Cara membaca",
    "",
    "1. **A** hanya membuktikan dataset *learnable*; skor tinggi di sini bukan bukti realisme.",
    "2. **B** adalah pembanding pipeline pada data nyata; pakai split resmi, bukan random split.",
    "3. **C** adalah bukti utama. Bandingkan dengan baseline acak 1/n_kelas "
    f"(≈ {1/len(SHARED):.3f} untuk {len(SHARED)} kelas).",
    "4. **D** menjawab apakah menambah data UNSW membantu sesi sintetis yang ditahan; "
    "lihat juga apakah skor UNSW turun karena domain shift.",
    "5. **E** hanya supplementary karena group-nya sedikit.",
    "6. Baca `core` lebih dulu. Kalau `full` jauh lebih tinggi, model kemungkinan memakai "
    "port/`ct_*`/IP-derived artifacts, bukan perilaku serangan.",
    "",
    "## Batasan",
    "",
    "- Hanya {} sesi sintetis; variansi antar-sesi besar dan std tidak stabil.".format(
        len(syn_sessions)
    ),
    "- UNSW official split berasal dari capture yang sama dan mengandung flow mirip/duplikat.",
    "- Label sintetis berbasis window + partisipasi IP, bukan ground truth generator.",
    "- Cross-domain hanya irisan kelas; kelas eksklusif tidak diuji.",
    "- Model baseline, tanpa tuning agresif; bukan klaim SOTA.",
]
(OUT / "RESULTS.md").write_text("\n".join(md), encoding="utf-8")

manifest = {
    "seed": SEED,
    "quick": QUICK,
    "grouped_cv": RUN_GROUPED_CV,
    "synthetic_path": str(SYNTH_PATH),
    "unsw_train_path": str(UNSW_TRAIN_PATH),
    "unsw_test_path": str(UNSW_TEST_PATH),
    "n_synthetic": int(len(syn)),
    "n_unsw_train": int(len(unsw_train)),
    "n_unsw_test": int(len(unsw_test)),
    "synthetic_classes": SYN_CLASSES,
    "unsw_classes": UNSW_CLASSES,
    "shared_classes": SHARED,
    "feature_sets": {k: len(v) for k, v in FEATURE_SETS.items()},
    "models": ["dt", "rf"],
    "versions": {
        "pandas": pd.__version__,
        "numpy": np.__version__,
        "sklearn": sklearn.__version__,
    },
}
(OUT / "run_manifest.json").write_text(
    json.dumps(manifest, indent=2), encoding="utf-8"
)

print("\nselesai ->", OUT)
print("file: metrics.csv, key_results.csv, summary_by_stage.csv, per_class.csv, RESULTS.md")
print("gambar:", len(list((OUT / 'confusion').glob('*.png'))), "confusion matrix")

# %% [markdown]
# ## 12. Interpretasi yang aman untuk paper
#
# Gunakan kalimat bersyarat, bukan klaim universal:
#
# > “Pada protokol session-disjoint, dataset sintetis mencapai macro F1 **A**.
# > Ketika diuji pada UNSW-NB15 dengan irisan kelas yang sama, performa turun
# > menjadi **C** (rasio transfer **C/A**). Ini menunjukkan bahwa dataset dapat
# > dipakai untuk klasifikasi dalam-domain, tetapi generalisasi lintas-domain
# > masih terbatas pada [kelas yang tetap tinggi].”
#
# Yang harus dilaporkan:
#
# * Tabel A/B/C/D per model dan per set fitur, bukan hanya rata-rata.
# * Per-class F1 untuk kelas minoritas (Analysis, DoS).
# * `core` sebagai klaim utama; `full` sebagai ablation.
# * Confusion matrix cross-domain; kelas mana yang paling sering tertukar.
# * Batasan: 2 sesi, UNSW split resmi, label berbasis window, dan domain gap.
#
# Yang **tidak** boleh dilakukan:
#
# * Melaporkan akurasi saja.
# * Menggabungkan train/test secara acak.
# * Memasukkan `domain` sebagai fitur lalu mengklaim transfer.
# * Membandingkan skor dengan paper yang memakai split acak.
# * Menyimpulkan “dataset valid” hanya dari skor internal yang tinggi.
