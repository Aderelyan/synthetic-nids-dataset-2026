"""Gabung extract-out/<run>/*.csv jadi satu CSV per skema.

Dua grup, dua output -- skemanya beda 1 kolom, JANGAN dicampur:
  unsw.csv       (49 kolom) -> dataset/ml/lab_flows.csv
  unsw_multi.csv (50 kolom) -> dataset/ml/lab_flows_multi.csv

Metadata yang ditambahkan: session_id, archive, scenario
(session_id: folder normal-* -> run-1, folder lainnya -> run-2; lihat SESSION di bawah.
(scenario = kode window dari markers.csv, logika sama dengan ml/prepare_kaggle_dataset.py:
 window pertama yang memuat Stime menang; label=0 tanpa window -> N01-outside; selain itu UNKNOWN).

Hanya stdlib -> jalan di python 3.12 tanpa pandas.
Usage:
  python pipeline/merge_extract.py --file unsw.csv
  python pipeline/merge_extract.py --file unsw_multi.csv [--out PATH]
"""
from __future__ import annotations

import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "extract-out"
ML = ROOT / "dataset" / "ml"

# Pengelompokan sesi (revisi 2026-10-29): run-1 = 3 arsip awal (sesi-1) + 2 arsip
# normal-only; run-2 = 3 arsip sisanya. Kalau grouping diubah lagi, ubah HANYA di sini
# supaya kedua output konsisten (ARCHIVE_MAP di ml/prepare_kaggle_dataset.py kini usang).
SESSION = {
    # ---- RUN 1 (sesi-1: 3 arsip awal + capture normal) ----
    "linux-20261022-094511": "run-1",
    "linux-20261023-082131": "run-1",
    "windows-20261023-120511": "run-1",
    "normal-windows-20261024-072559": "run-1",
    "normal-linux-20261026-062948": "run-1",
    # ---- RUN 2 (sesi-2: 3 arsip sisanya) ----
    "windows-20261024-051115": "run-2",
    "linux-20261026-103227": "run-2",
    "linux-20261027-082533": "run-2",
}

META = ["session_id", "archive", "scenario"]


def epoch(ts: str) -> float:
    """2026-10-22T06:17:19Z -> epoch detik (UTC)."""
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()


def windows_for(run_dir: Path) -> list[tuple[str, float, float]]:
    path = run_dir / "markers.csv"
    if not path.exists():
        print(f"WARN: {run_dir.name} tanpa markers.csv -> semua UNKNOWN", file=sys.stderr)
        return []
    wins = []
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            wins.append((row["scenario"], epoch(row["start_utc"]), epoch(row["end_utc"])))
    return wins


def scenario_of(t: float, wins: list[tuple[str, float, float]], label: str) -> str:
    for code, start, end in wins:          # urutan baris markers = prioritas
        if start <= t <= end:
            return code
    return "N01-outside" if label.strip() in ("0", "0.0") else "UNKNOWN"


def merge(target: str, out_path: Path) -> int:
    dirs = sorted((d for d in EXTRACT.iterdir() if d.is_dir() and (d / target).exists()),
                  key=lambda d: d.name)
    if not dirs:
        sys.exit(f"STOP: tidak ada folder berisi {target} di {EXTRACT}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_name(out_path.name + ".part")
    if tmp.exists():
        tmp.unlink()

    header = None
    header_plus = None
    total = 0
    skipped = 0
    per_run: dict[str, int] = {}
    scen_counts: dict[str, int] = {}

    with tmp.open("w", newline="", encoding="utf-8") as fo:
        w = csv.writer(fo, lineterminator="\r\n")   # CRLF, sama seperti sumber
        for d in dirs:
            wins = windows_for(d)
            session = SESSION.get(d.name, "?")
            with (d / target).open("r", newline="", encoding="utf-8") as fi:
                r = csv.reader(fi)
                h = next(r)
                if header is None:
                    header = h
                    header_plus = h + META
                    i_stime = h.index("Stime")
                    i_label = h.index("label")
                    w.writerow(header_plus)
                elif h != header:
                    tmp.unlink(missing_ok=True)
                    sys.exit(f"STOP: skema beda di {d.name}/{target}")

                n = 0
                for row in r:
                    if len(row) != len(header):
                        skipped += 1
                        if skipped <= 5:
                            print(f"WARN {d.name} baris {n + 2}: {len(row)} kolom (dilewati)",
                                  file=sys.stderr)
                        continue
                    scen = scenario_of(float(row[i_stime]), wins, row[i_label])
                    w.writerow(row + [session, d.name, scen])
                    scen_counts[scen] = scen_counts.get(scen, 0) + 1
                    n += 1
            per_run[d.name] = n
            total += n
            print(f"  {d.name:<32} {n:>8} baris  ({session})")

    with tmp.open("r", newline="", encoding="utf-8") as f:
        again = next(csv.reader(f))
    if again != header_plus:
        tmp.unlink(missing_ok=True)
        sys.exit("STOP: header hasil tulis tidak sesuai")

    tmp.replace(out_path)
    print(f"\n  kolom     : {len(header)} UNSW + {len(META)} metadata = {len(header_plus)}")
    print(f"  baris data: {total:,}  (+1 header, dilewati {skipped})")
    print(f"  ukuran    : {out_path.stat().st_size / 1e6:.1f} MB")
    print(f"  output    : {out_path}")
    print("  skenario  : " + "  ".join(f"{k}={v:,}" for k, v in sorted(scen_counts.items())))
    if scen_counts.get("UNKNOWN"):
        print(f"  PERHATIAN : {scen_counts['UNKNOWN']:,} baris UNKNOWN (cek window marker)")
    return total


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file", default="unsw.csv", choices=["unsw.csv", "unsw_multi.csv"])
    ap.add_argument("--out", default=None, help="path output (default: dataset/ml/...)")
    a = ap.parse_args()

    default_out = ML / ("lab_flows.csv" if a.file == "unsw.csv" else "lab_flows_multi.csv")
    out_path = Path(a.out) if a.out else default_out
    print(f"=== merge {a.file} -> {out_path}")
    merge(a.file, out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
