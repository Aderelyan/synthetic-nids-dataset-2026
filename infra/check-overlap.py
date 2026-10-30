#!/usr/bin/env python3
# check-overlap.py — verifikasi hasil capture:
#  (1) window ATTACK saling time-disjoint (overlap BEDA-LABEL = masalah),
#  (2) tak ada flow jatuh di >1 window beda-label (ambigu),
#  (3) coverage: flow ter-cover ≥1 window (deteksi CSV stale / mismatch marker).
# Overlap sesama-label (mis. N01 client-1 & client-2 paralel) DIABAIKAN — aman.
# Usage: python infra/check-overlap.py [extract-out]
import csv, sys, os
from datetime import datetime, timezone

OUT = sys.argv[1] if len(sys.argv) > 1 else "extract-out"
def ep(s): return datetime.strptime(s.strip(), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
def hms(t): return datetime.fromtimestamp(t, timezone.utc).strftime("%H:%M:%S")

W = []
with open(os.path.join(OUT, "markers.csv")) as f:
    for r in csv.DictReader(f):
        try: s, e = ep(r["start_utc"]), ep(r["end_utc"])
        except Exception: continue
        W.append((r["scenario"], r["attack_cat"], s, e))
W.sort(key=lambda x: x[2])

print("=== WINDOW (urut waktu) ===")
for scn, cat, s, e in W:
    print(f"{scn:30s} {cat:16s} {hms(s)}..{hms(e)} ({e-s:5.0f}s)")

# overlap antar-window BEDA LABEL (yang bikin ambigu). Sesama-label diabaikan.
bad = 0
for i in range(len(W)):
    for j in range(i + 1, len(W)):
        si, ei, ci = W[i][2], W[i][3], W[i][1]
        sj, ej, cj = W[j][2], W[j][3], W[j][1]
        if sj < ei and si < ej and ci != cj:        # overlap waktu + label beda
            print(f"  ! OVERLAP beda-label: {W[i][0]}({ci}) x {W[j][0]}({cj})"); bad += 1
print(f"\nOVERLAP window beda-label   : {bad}  ->", "OK (disjoint)" if bad == 0 else "MASALAH")

# flow: coverage (deteksi stale) + ambiguitas (di >1 window beda-label)
amb = cov = tot = 0
with open(os.path.join(OUT, "unsw.csv")) as f:
    for r in csv.DictReader(f):
        try: st = float(r["Stime"])
        except Exception: continue
        tot += 1
        cats = {c for (_, c, s, e) in W if s <= st <= e}
        if cats: cov += 1
        if len(cats) > 1: amb += 1
stale = tot and cov < tot * 0.3
print(f"FLOW ter-cover ≥1 window    : {cov}/{tot}" +
      ("  !! COVERAGE RENDAH -> unsw.csv mungkin STALE / marker mismatch" if stale else ""))
print(f"FLOW di >1 window beda-label: {amb}/{tot}  ->", "OK" if amb == 0 else "AMBIGU")
print("\nVERDICT:", "LULUS" if (bad == 0 and amb == 0 and not stale) else "CEK ULANG (lihat tanda !! / !)")

# --- flow per-skenario + rate (utk kalibrasi DURMAP) ---
# overlap beda-label = 0 -> tiap flow attack jatuh di tepat 1 window attack. Hitung per window.
print("\n=== FLOW PER-SKENARIO (utk DURMAP) ===")
cnt = {}
with open(os.path.join(OUT, "unsw.csv")) as f:
    for r in csv.DictReader(f):
        try: st = float(r["Stime"])
        except Exception: continue
        for scn, cat, s, e in W:
            if s <= st <= e:
                cnt[scn] = cnt.get(scn, 0) + 1
                break
for scn, cat, s, e in W:
    d = e - s; n = cnt.get(scn, 0)
    print(f"{scn:30s} {cat:16s} {n:7d} flow / {d:4.0f}s = {n/d if d else 0:6.2f} fl/s")
