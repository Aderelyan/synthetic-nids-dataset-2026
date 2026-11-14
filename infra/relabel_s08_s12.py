#!/usr/bin/env python3
"""
Post-hoc relabeling of S08 and S12 flows using attack-chain specifications.
Reads existing lab_flows.csv + markers.csv, writes lab_flows_v2.csv.
Other scenarios are untouched.

Usage:
    python relabel_s08_s12.py \
        --input lab_flows.csv \
        --markers markers.csv \
        --output lab_flows_v2.csv \
        --audit audit_relabel.csv
"""
import argparse
import csv
from datetime import datetime, timezone

from chain_spec import get_chain, ATTACKER_IP


def parse_iso(ts):
    s = ts.strip().rstrip("Z")
    if "+" not in s and "-" not in s[-6:]:
        s = s + "+00:00"
    return datetime.fromisoformat(s).replace(tzinfo=timezone.utc).timestamp()


def load_markers(path):
    markers = []
    with open(path) as f:
        for r in csv.DictReader(f):
            try:
                start = parse_iso(r["start_utc"])
                end = parse_iso(r["end_utc"])
            except (KeyError, ValueError):
                continue
            markers.append((r["scenario"].strip(),
                            r["attack_cat"].strip(),
                            start, end))
    return markers


def label_flow(row, markers, attacker_ip, use_chain_spec=True):
    try:
        st = float(row["Stime"])
    except (KeyError, ValueError):
        return int(row["label"]), row["attack_cat"], False

    src_ip = (row.get("srcip") or "").strip()
    dst_ip = (row.get("dstip") or "").strip()
    try:
        src_port = int(float(row.get("sport") or 0))
        dst_port = int(float(row.get("dsport") or 0))
    except (ValueError, TypeError):
        src_port = dst_port = 0

    orig_label = int(row["label"])
    orig_cat = row["attack_cat"]

    def changed_for(new_label, new_cat):
        return (orig_label != new_label) or (orig_cat != new_cat)

    for scenario, category, start, end in markers:
        if not (start <= st <= end):
            continue
        if category.lower() == "normal":
            continue

        # RULE 1 (old, ALWAYS preserved): attacker IP present -> attack
        if src_ip == attacker_ip or dst_ip == attacker_ip:
            return 1, category, changed_for(1, category)

        # RULE 2 (new, ADDITIVE): chain-IP + port filter for multi-hop scenarios
        if use_chain_spec and scenario in ("S08", "S12"):
            chain_ips, chain_ports = get_chain(scenario)
            if ((src_ip in chain_ips or dst_ip in chain_ips)
                and (chain_ports is None
                     or src_port in chain_ports
                     or dst_port in chain_ports)):
                return 1, category, changed_for(1, category)

    return 0, "Normal", changed_for(0, "Normal")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--markers", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--audit", required=True)
    ap.add_argument("--attacker-ip", default=ATTACKER_IP)
    ap.add_argument("--disable-chain-spec", action="store_true")
    args = ap.parse_args()

    use_chain = not args.disable_chain_spec
    markers = load_markers(args.markers)
    print(f"Loaded {len(markers)} markers")
    print(f"Chain-spec: {'ENABLED' if use_chain else 'DISABLED'}")

    audit, per_scn = [], {}
    stats = {"total": 0, "n2a": 0, "a2n": 0, "cc": 0, "same": 0}

    with open(args.input) as fin, open(args.output, "w", newline="") as fout:
        reader = csv.DictReader(fin)
        writer = csv.DictWriter(fout, fieldnames=reader.fieldnames)
        writer.writeheader()
        for row in reader:
            stats["total"] += 1
            ol, oc = int(row["label"]), row["attack_cat"]
            nl, nc, changed = label_flow(row, markers, args.attacker_ip, use_chain)
            row["label"], row["attack_cat"] = nl, nc
            writer.writerow(row)

            scn = row.get("scenario", "")
            s = per_scn.setdefault(scn, {"total": 0, "n2a": 0, "a2n": 0, "same": 0})
            s["total"] += 1

            if changed:
                ct = "A->N" if (ol == 1 and nl == 0) else \
                     "N->A" if (ol == 0 and nl == 1) else "cat"
                if ct == "N->A":
                    stats["n2a"] += 1; s["n2a"] += 1
                elif ct == "A->N":
                    stats["a2n"] += 1; s["a2n"] += 1
                else:
                    stats["cc"] += 1
                audit.append({
                    "scenario": scn, "src_ip": row.get("srcip"),
                    "src_port": row.get("sport"), "dst_ip": row.get("dstip"),
                    "dst_port": row.get("dsport"), "proto": row.get("proto"),
                    "Stime": row.get("Stime"), "orig_label": ol, "orig_cat": oc,
                    "new_label": nl, "new_cat": nc, "change": ct,
                })
            else:
                stats["same"] += 1; s["same"] += 1

    if audit:
        with open(args.audit, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=audit[0].keys())
            w.writeheader(); w.writerows(audit)
        print(f"Audit: {args.audit} ({len(audit)} rows)")

    print(f"\n=== SUMMARY ===")
    print(f"Total:           {stats['total']:>10,}")
    print(f"N -> A (fixed):  {stats['n2a']:>10,}")
    print(f"A -> N:          {stats['a2n']:>10,}")
    print(f"Category change: {stats['cc']:>10,}")
    print(f"Unchanged:       {stats['same']:>10,}")

    print(f"\n=== PER SCENARIO ===")
    print(f"{'scenario':<20}{'total':>10}{'N->A':>8}{'A->N':>8}{'same':>10}")
    for scn in sorted(per_scn):
        s = per_scn[scn]
        print(f"{scn:<20}{s['total']:>10,}{s['n2a']:>8,}{s['a2n']:>8,}{s['same']:>10,}")


if __name__ == "__main__":
    main()