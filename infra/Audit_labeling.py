#!/usr/bin/env python3
"""
Audit relabel output: quantify contamination in original and check
new false positives introduced by chain-IP rule.

Usage:
    python audit_labeling.py --original lab_flows.csv \
                             --revised lab_flows_v2.csv \
                             --audit audit_relabel.csv \
                             --report audit_report.txt
"""
import argparse
import csv
from collections import defaultdict


def count_by(path, key_fn):
    cnt = defaultdict(int)
    with open(path) as f:
        for r in csv.DictReader(f):
            cnt[key_fn(r)] += 1
    return cnt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True)
    ap.add_argument("--revised", required=True)
    ap.add_argument("--audit", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()

    # Counts by (label, attack_cat) in original vs revised
    def key(r):
        return (int(r["label"]), r["attack_cat"])

    orig = count_by(args.original, key)
    rev = count_by(args.revised, key)

    lines = ["=== LABEL DISTRIBUTION ==="]
    lines.append(f"{'label/class':<30}{'original':>12}{'revised':>12}{'delta':>10}")
    for k in sorted(set(orig) | set(rev)):
        o, r = orig.get(k, 0), rev.get(k, 0)
        lines.append(f"{str(k):<30}{o:>12,}{r:>12,}{r-o:>+10,}")

    # Contamination analysis from audit CSV
    lines.append("\n=== CONTAMINATION ANALYSIS (from audit) ===")
    n2a_by_scn = defaultdict(int)
    a2n_by_scn = defaultdict(int)
    with open(args.audit) as f:
        for r in csv.DictReader(f):
            if r["change"] == "N->A":
                n2a_by_scn[r["scenario"]] += 1
            elif r["change"] == "A->N":
                a2n_by_scn[r["scenario"]] += 1

    total_n_orig = orig.get((0, "Normal"), 0)
    total_a_orig = sum(v for k, v in orig.items() if k[0] == 1)

    lines.append(f"\nOriginal Normal count:  {total_n_orig:,}")
    lines.append(f"Original Attack count:  {total_a_orig:,}")
    lines.append("")
    lines.append(f"{'scenario':<20}{'N->A (fixed)':>15}{'A->N':>10}"
                 f"{'% of orig Normal':>20}")
    for scn in sorted(set(n2a_by_scn) | set(a2n_by_scn)):
        n, a = n2a_by_scn.get(scn, 0), a2n_by_scn.get(scn, 0)
        pct = 100.0 * n / total_n_orig if total_n_orig else 0
        lines.append(f"{scn:<20}{n:>15,}{a:>10,}{pct:>19.4f}%")

    total_n2a = sum(n2a_by_scn.values())
    pct_n2a = 100.0 * total_n2a / total_n_orig if total_n_orig else 0
    lines.append(f"\nTotal N->A (fixed):     {total_n2a:,}")
    lines.append(f"Contamination rate:     {pct_n2a:.4f}% of original Normal class")
    lines.append(f"Reclassified as attack: {100*pct_n2a/100*len([1]):.4f}% of total flows")

    with open(args.report, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nReport written: {args.report}")


if __name__ == "__main__":
    main()