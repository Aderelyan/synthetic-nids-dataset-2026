"""Gabungkan hasil ekstraksi (extract-out/*/unsw.csv) menjadi satu dataset siap-Kaggle.

Kenapa perlu skrip ini (bukan `cat *.csv`):
1. Setiap CSV hanya punya 49 kolom UNSW; tidak ada penanda *sesi*. Tanpa penanda ini,
   evaluasi Group K-Fold mustahil dan flow dari run yang sama bisa bocor ke train & test.
2. Label window (`attack_cat`) sudah ada, tetapi kode skenario (S01..S12) tidak, padahal
   dibutuhkan untuk audit "kelas mana berasal dari skenario mana".
3. Arsip `normal-*` adalah capture Normal tambahan; harus ikut tergabung tetapi tetap
   ditandai supaya proporsi Normal terkontrol.

Pengelompokan run (urut LastWriteTime naik di raw-archive/research; 3 pertama = run 1):
  run-1 : linux-20261022-094511, linux-20261023-082131, windows-20261023-120511
  run-2 : windows-20261024-051115, normal-windows-20261024-072559,
          normal-linux-20261026-062948, linux-20261026-103227, linux-20261027-082533

Keluaran:
  dataset/ml/lab_flows.csv     -- 49 kolom UNSW + session_id, archive, scenario
  dataset/ml/data_card.md      -- ringkasan distribusi (untuk Bab 4)

Jalankan (python yang punya pandas):
  python ml/prepare_kaggle_dataset.py
"""
from __future__ import annotations

from pathlib import Path
import sys

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "extract-out"
ARCHIVE_ROOT = ROOT / "raw-archive" / "research"
OUT_DIR = ROOT / "dataset" / "ml"

# archive -> (session_id, phase, jenis)
ARCHIVE_MAP: dict[str, tuple[str, str, str]] = {
    # ---- RUN 1 (sesi-1) ----
    "linux-20261022-094511": ("run-1", "linux", "attack+normal"),
    "linux-20261023-082131": ("run-1", "linux", "attack+normal"),
    "windows-20261023-120511": ("run-1", "windows", "attack+normal"),
    # ---- RUN 2 (sesi-2) ----
    "windows-20261024-051115": ("run-2", "windows", "attack+normal"),
    "normal-windows-20261024-072559": ("run-2", "windows", "normal-only"),
    "normal-linux-20261026-062948": ("run-2", "linux", "normal-only"),
    "linux-20261026-103227": ("run-2", "linux", "attack+normal"),
    "linux-20261027-082533": ("run-2", "linux", "attack+normal"),
}

META_COLS = ["session_id", "archive", "scenario"]


def md_table(df: pd.DataFrame) -> str:
    """Markdown table tanpa ketergantungan `tabulate` (tidak terpasang di runtime ini)."""
    head = "| " + " | ".join([str(df.index.name or "")] + [str(c) for c in df.columns]) + " |"
    sep = "|" + "|".join(["---"] * (len(df.columns) + 1)) + "|"
    rows = [f"| {idx} | " + " | ".join(str(v) for v in row) + " |"
            for idx, row in zip(df.index, df.to_numpy())]
    return "\n".join([head, sep, *rows])


def _epoch_s(series: pd.Series) -> pd.Series:
    """UTC string -> epoch detik.

    JANGAN pakai `.astype('int64') // 10**9`: pandas 3.x menyimpan datetime pada
    resolusi mikrodetik, sehingga int64 = 1e15 (bukan 1e18) dan pembagian 1e9
    menghasilkan angka 1.000x terlalu kecil -> semua window gagal cocok.
    """
    dt = pd.to_datetime(series, utc=True)
    return (dt - pd.Timestamp("1970-01-01", tz="UTC")) // pd.Timedelta(seconds=1)


def read_markers(archive: str) -> pd.DataFrame:
    path = ARCHIVE_ROOT / archive / "markers.csv"
    if not path.exists():
        return pd.DataFrame(columns=["scenario", "start", "end"])
    mk = pd.read_csv(path)
    mk = mk[["scenario", "start_utc", "end_utc"]].copy()
    mk["start"] = _epoch_s(mk["start_utc"])
    mk["end"] = _epoch_s(mk["end_utc"])
    return mk[["scenario", "start", "end"]]


def assign_scenario(df: pd.DataFrame, mk: pd.DataFrame) -> pd.Series:
    """Kode skenario per baris = window marker yang memuat Stime.

    Untuk flow Normal di luar window Normal (idle/benar-benar benign), dipakai label
    "N01-outside" agar tetap jelas asalnya. Flow attack yang tidak jatuh di window mana pun
    ditandai "UNKNOWN" -> harus 0; kalau tidak, labeling bermasalah.
    """
    scen = pd.Series("UNKNOWN", index=df.index, dtype="object")
    t = df["Stime"]
    for _, w in mk.iterrows():
        mask = (t >= w["start"]) & (t <= w["end"])
        scen.loc[mask & (scen == "UNKNOWN")] = w["scenario"]
    scen.loc[(scen == "UNKNOWN") & (df["label"] == 0)] = "N01-outside"
    return scen


def main() -> int:
    missing = [a for a in ARCHIVE_MAP if not (EXTRACT / a / "unsw.csv").exists()]
    if missing:
        print(f"STOP: belum diekstrak: {missing}", file=sys.stderr)
        return 1

    frames: list[pd.DataFrame] = []
    for archive, (session, phase, kind) in ARCHIVE_MAP.items():
        df = pd.read_csv(EXTRACT / archive / "unsw.csv", low_memory=False)
        df["session_id"] = session
        df["archive"] = archive
        df["scenario"] = assign_scenario(df, read_markers(archive))
        frames.append(df)
        print(f"  {archive:<32} {len(df):>7} baris  session={session} phase={phase} ({kind})")

    full = pd.concat(frames, ignore_index=True)
    # Urutan kolom: 49 kolom UNSW dulu (kompatibilitas), lalu metadata di belakang.
    base = [c for c in frames[0].columns if c not in META_COLS]
    full = full[base + META_COLS]

    unknown_attack = int(((full["scenario"] == "UNKNOWN") & (full["label"] == 1)).sum())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_csv = OUT_DIR / "lab_flows.csv"
    full.to_csv(out_csv, index=False)

    # ---------- data card ----------
    lines = ["# Data card â€” lab_flows.csv", ""]
    lines.append(f"Total flow: **{len(full):,}**  |  sesi: {full['session_id'].nunique()}  |  "
                 f"arsip: {full['archive'].nunique()}")
    lines.append("")
    lines.append("## Distribusi kelas per sesi (baris)")
    lines.append("")
    ct = pd.crosstab(full["attack_cat"], full["session_id"], margins=True, margins_name="TOTAL")
    lines.append(md_table(ct))
    lines.append("")
    lines.append("## Distribusi skenario per sesi")
    lines.append("")
    sc = pd.crosstab(full["scenario"], full["session_id"], margins=True, margins_name="TOTAL")
    lines.append(md_table(sc))
    lines.append("")
    lines.append("## Kualitas data")
    lines.append("")
    lines.append(f"- Flow attack tanpa window marker (harus 0): **{unknown_attack}**")
    lines.append(f"- Duplikat (srcip,sport,dstip,dsport,proto,Stime): "
                 f"**{int(full.duplicated(subset=['srcip','sport','dstip','dsport','proto','Stime']).sum())}**")
    lines.append(f"- Baris dengan `Djit` null: **{int(full['Djit'].isna().sum())}**")
    lines.append(f"- Rentang waktu: {pd.to_datetime(full['Stime'].min(), unit='s', utc=True)} s/d "
                 f"{pd.to_datetime(full['Stime'].max(), unit='s', utc=True)}")
    (OUT_DIR / "data_card.md").write_text("\n".join(lines), encoding="utf-8")

    print(f"\nOK -> {out_csv}  ({out_csv.stat().st_size/1e6:.1f} MB)")
    print(f"OK -> {OUT_DIR/'data_card.md'}")
    print("\nDistribusi kelas:")
    print(full["attack_cat"].value_counts().to_string())
    print(f"\nAttack tanpa window: {unknown_attack}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

