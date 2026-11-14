#!/usr/bin/env python3
"""QC ringan untuk CSV hasil build_dataset.py.
Usage: python3 pipeline/qa_dataset.py <unsw.csv>
Exit code 0 jika semua cek lulus, 1 jika ada FAIL, 2 jika ada WARN saja.
"""
import sys, csv
from statistics import median

def safe_float(x, d=0.0):
    try:
        v = float(x)
        return d if v != v else v
    except (TypeError, ValueError):
        return d

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: qa_dataset.py <csv>")
    path = sys.argv[1]
    rows = []
    with open(path, newline="") as f:
        rdr = csv.DictReader(f)
        hdr = rdr.fieldnames or []
        for r in rdr:
            rows.append(r)
    if not rows:
        sys.exit(f"FAIL: {path} kosong")

    fails, warns = [], []
    print(f"== QA {path} ({len(rows)} rows, {len(hdr)} cols) ==")

    # --- Kolom wajib
    need = ["Stime", "Ltime", "ct_src_ltm", "ct_flw_http_mthd", "label"]
    missing = [c for c in need if c not in hdr]
    if missing:
        fails.append(f"kolom wajib hilang: {missing}")

    # --- Numeric sanity
    for col, msg in [
        ("dur", "dur negatif"),
        ("sbytes", "sbytes negatif"),
        ("dbytes", "dbytes negatif"),
    ]:
        if col not in hdr:
            continue
        nneg = sum(1 for r in rows if safe_float(r[col], 0) < 0)
        if nneg:
            fails.append(f"{msg}: {nneg} baris")

    # --- stime monotonic (bukan strict; hanya warn untuk lompatan besar)
    if "Stime" in hdr:
        st = [safe_float(r["Stime"], 0) for r in rows]
        if all(x == 0 for x in st):
            fails.append("Stime semua 0 (ra -u gagal?)")
        else:
            neg = 0
            big_neg = 0
            prev = None
            for x in st:
                if prev is not None:
                    d = x - prev
                    if d < 0:
                        neg += 1
                        if d < -60:
                            big_neg += 1
                prev = x
            if neg:
                warns.append(f"Stime delta negatif: {neg} baris "
                             f"({big_neg} > 60s mundur)")
            print(f"   Stime: neg_delta={neg}, big_neg={big_neg}")

    # --- Fitur mati / constant
    numeric = [c for c in hdr if c not in
               {"srcip","sport","dstip","dsport","proto","state","service",
                "attack_cat","label","vantage","session_id","archive","scenario"}]
    for col in numeric:
        vals = [safe_float(r.get(col)) for r in rows]
        nz = sum(1 for v in vals if v != 0)
        uniq = len(set(vals))
        if nz == 0:
            warns.append(f"{col}: all-zero")
        elif uniq == 1:
            warns.append(f"{col}: constant ({vals[0]})")

    # --- Label / attack_cat
    if "label" in hdr:
        n0 = sum(1 for r in rows if r["label"] in ("0","0.0"))
        n1 = sum(1 for r in rows if r["label"] in ("1","1.0"))
        print(f"   label: 0={n0}, 1={n1}")
        if n1 == 0:
            fails.append("label=1 tidak ada (semua Normal) — cek markers/attacker-ip")
        if n0 == 0:
            warns.append("label=0 tidak ada (semua Attack)")

    # --- Cross-check: label=1 & attack_cat=Normal (harus 0 setelah fix)
    if "attack_cat" in hdr and "label" in hdr:
        bad = sum(1 for r in rows
                  if r.get("attack_cat","").strip().lower() == "normal"
                  and r.get("label") in ("1","1.0"))
        if bad:
            fails.append(f"label=1 & attack_cat=Normal: {bad} baris (harus 0)")

    # --- ct_flw_http_mthd harus bisa > 1 jika ada HTTP
    if "ct_flw_http_mthd" in hdr:
        mx = max((safe_float(r["ct_flw_http_mthd"], 0) for r in rows), default=0)
        print(f"   ct_flw_http_mthd max: {mx:.0f}")
        if mx <= 1:
            warns.append("ct_flw_http_mthd max <= 1 (tidak ada multi-request HTTP?)")

    # --- ct_* cap 100 (window=100 -> max harus <= 100)
    for col in ("ct_src_ltm","ct_dst_ltm","ct_srv_src","ct_srv_dst",
                "ct_state_ttl","ct_dst_src_ltm"):
        if col not in hdr:
            continue
        mx = max((safe_float(r[col], 0) for r in rows), default=0)
        if mx > 100:
            warns.append(f"{col} max={mx} > 100 (window=100 harus cap di 100)")

    # --- Report
    print()
    if fails:
        print("FAIL:")
        for f in fails: print(f"  - {f}")
    if warns:
        print("WARN:")
        for w in warns: print(f"  - {w}")
    if not fails and not warns:
        print("OK: semua cek lulus.")
        return 0
    if fails:
        return 1
    return 2

if __name__ == "__main__":
    sys.exit(main())