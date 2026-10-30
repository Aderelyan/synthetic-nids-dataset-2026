#!/usr/bin/env python3
# Tahap B — gabungkan CSV argus (Tahap A) + Zeek (service/http/ftp) -> hitung ct_* &
# flag sliding-window -> label per marker window -> CSV final 49 kolom UNSW-NB15.
#
# Usage:
#   build_dataset.py --argus-dir <dir CSV Tahap A> --zeek-root <dir berisi zeek-<iface>/>
#                    --markers <markers.csv> --out <final.csv>
#                    [--attacker-ip 10.10.30.10] [--window 100]
#
# markers.csv: header scenario,attack_cat,phase,target,start_utc,end_utc
#   (format sama dgn ~/attack-markers.csv dari scenarios/_lib/common.sh)
#
# CATATAN definisi ct_* mengikuti SEMANTIK UNSW-NB15 (nama+arti kolom). Implementasi
# C asli feature-generator UNSW tak pernah dirilis publik (lihat phase5-sensor.md §7.3
# honesty note) -> ini reproduksi level-skema, bukan bit-identik.
import argparse, csv, glob, os, sys
from collections import deque, Counter
from datetime import datetime, timezone

UNSW_COLS = [
 "srcip","sport","dstip","dsport","proto","state","dur","sbytes","dbytes","sttl",
 "dttl","sloss","dloss","service","Sload","Dload","Spkts","Dpkts","swin","dwin",
 "stcpb","dtcpb","smeansz","dmeansz","trans_depth","res_bdy_len","Sjit","Djit",
 "Stime","Ltime","Sintpkt","Dintpkt","tcprtt","synack","ackdat","is_sm_ips_ports",
 "ct_state_ttl","ct_flw_http_mthd","is_ftp_login","ct_ftp_cmd","ct_srv_src",
 "ct_srv_dst","ct_dst_ltm","ct_src_ltm","ct_src_dport_ltm","ct_dst_sport_ltm",
 "ct_dst_src_ltm","attack_cat","label",
]

def parse_iso(s):  # 2026-10-08T17:07:54Z -> epoch (UTC)
    return datetime.strptime(s.strip(), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()

def read_zeek(path):
    """Parse satu Zeek .log (TSV header #fields). return (fields, list[dict])."""
    if not os.path.exists(path): return [], []
    fields, rows = [], []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#fields"):
                fields = line.rstrip("\n").split("\t")[1:]
            elif line.startswith("#") or not line.strip():
                continue
            else:
                vals = line.rstrip("\n").split("\t")
                if len(vals) == len(fields):
                    rows.append(dict(zip(fields, vals)))
    return fields, rows

def z(v):  # zeek '-'/'(empty)' -> None
    return None if v in ("-", "(empty)", "") else v

def key5(proto, sa, sp, da, dp):
    return (str(proto).lower(), sa, str(sp), da, str(dp))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--argus-dir", required=True)
    ap.add_argument("--zeek-root", required=True, help="dir berisi zeek-<iface>/ (mis. extraction)")
    ap.add_argument("--markers", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--attacker-ip", default="10.10.30.10",
                    help="label=1 butuh IP ini sbg saddr/daddr dlm window; kosong='' = window-only")
    ap.add_argument("--window", type=int, default=100)
    ap.add_argument("--dedup", choices=["dest", "off"], default="dest",
                    help="dest (default)=single-view, 1 flow/koneksi (ambil vantage sisi tujuan) "
                         "-> dataset UTAMA komparabel UNSW. off=multi-view (simpan semua vantage) -> varian.")
    ap.add_argument("--add-vantage", action="store_true",
                    help="tambah kolom 'vantage' (segmen sensor) di output -> untuk varian multi-view.")
    a = ap.parse_args()

    # ---- 1) baca semua CSV argus (Tahap A) ----
    argus_rows = []
    for csvf in sorted(glob.glob(os.path.join(a.argus_dir, "*_argus49.csv"))):
        with open(csvf) as f:
            for r in csv.DictReader(f):
                argus_rows.append(r)
    if not argus_rows:
        sys.exit(f"ERROR: tak ada *_argus49.csv di {a.argus_dir}")
    argus_rows.sort(key=lambda r: float(r["stime"]))  # kronologis utk sliding window
    print(f"[B] argus flows (mentah, semua vantage): {len(argus_rows)}")

    # ---- 1b) DEDUP multi-vantage (keputusan 2a: single-view = dataset utama) ----
    # Flow lintas-segmen tercatat >1x (tanpa SNAT, 5-tuple sama di tiap vantage).
    # 'dest': simpan 1 baris/koneksi, utamakan sensor di segmen IP TUJUAN (paling lengkap).
    def seg_for_ip(ip):
        if ip.startswith("10.10.10."): return "enp0s8"
        if ip.startswith("10.10.20."): return "enp0s9"
        if ip.startswith("10.10.30."): return "enp0s10"
        return None
    def npkts(r):
        try: return int(r["spkts"] or 0) + int(r["dpkts"] or 0)
        except ValueError: return 0
    if a.dedup == "dest":
        seen = {}; kept = []
        for r in argus_rows:
            k = (r["proto"], r["saddr"], r["sport"], r["daddr"], r["dport"],
                 round(float(r["stime"]) / 2))           # toleransi split timing ~2s
            pref = seg_for_ip(r["daddr"])
            if k not in seen:
                seen[k] = len(kept); kept.append(r)
            else:
                cur = kept[seen[k]]
                better = (r["segment"] == pref and cur["segment"] != pref) or \
                         (cur["segment"] != pref and npkts(r) > npkts(cur))
                if better: kept[seen[k]] = r
        print(f"[B] dedup=dest: {len(argus_rows)} -> {len(kept)} flow (single-view)")
        argus_rows = kept
    else:
        print("[B] dedup=off: multi-view (semua vantage dipertahankan)")

    # ---- 2) Zeek conn.log -> service by 5-tuple + uid->5tuple map ----
    svc_map, uid5 = {}, {}
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, conn = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "conn.log"))
        for r in conn:
            k = key5(r.get("proto"), r.get("id.orig_h"), r.get("id.orig_p"),
                     r.get("id.resp_h"), r.get("id.resp_p"))
            sv = z(r.get("service"))
            if sv and k not in svc_map:
                svc_map[k] = sv
            if r.get("uid"):
                uid5[r["uid"]] = k
    print(f"[B] zeek conn service keys: {len(svc_map)}")

    # ---- 3) http.log -> per 5tuple: trans_depth,res_bdy_len,has_method ----
    http5 = {}
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, hrows = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "http.log"))
        for r in hrows:
            k = uid5.get(r.get("uid"))
            if not k: continue
            td = z(r.get("trans_depth")); rb = z(r.get("response_body_len"))
            meth = z(r.get("method"))
            d = http5.setdefault(k, {"trans_depth": 0, "res_bdy_len": 0, "mthd": 0})
            if td: d["trans_depth"] = max(d["trans_depth"], int(float(td)))
            if rb: d["res_bdy_len"] += int(float(rb))
            if meth in ("GET", "POST"): d["mthd"] = 1

    # ---- 4) ftp.log -> per 5tuple: is_ftp_login, ct_ftp_cmd ----
    ftp5 = {}
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, frows = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "ftp.log"))
        for r in frows:
            k = uid5.get(r.get("uid"))
            if not k: continue
            d = ftp5.setdefault(k, {"login": 0, "cmd": 0})
            if z(r.get("command")): d["cmd"] += 1
            rc = z(r.get("reply_code"))
            user = z(r.get("user"))
            if (rc and str(rc).startswith("230")) or (user and user not in ("anonymous",)):
                d["login"] = 1

    # ---- 5) marker windows ----
    wins = []
    with open(a.markers) as f:
        for r in csv.DictReader(f):
            wins.append((parse_iso(r["start_utc"]), parse_iso(r["end_utc"]),
                         r["attack_cat"].strip()))
    atk = a.attacker_ip.strip()
    def label_of(sa, da, st):
        for s, e, cat in wins:
            if s <= st <= e and (not atk or sa == atk or da == atk):
                return cat, 1
        return "Normal", 0

    # ---- 6) sliding-window counters (last N, kronologis) ----
    N = a.window
    win = deque()
    c_src, c_dst, c_srv_src, c_srv_dst = Counter(), Counter(), Counter(), Counter()
    c_src_dport, c_dst_sport, c_dst_src = Counter(), Counter(), Counter()
    def dec(cnt, k):
        if cnt[k] <= 1: del cnt[k]
        else: cnt[k] -= 1

    # ct_state_ttl global (grup state+sttl+dttl) — pra-hitung
    g_state_ttl = Counter()
    for r in argus_rows:
        g_state_ttl[(r["state"], r["sttl"], r["dttl"])] += 1

    out_rows = []
    nlab = Counter()
    for r in argus_rows:
        sa, da = r["saddr"], r["daddr"]
        sp, dp = r["sport"], r["dport"]
        proto = r["proto"].lower()
        k5 = key5(proto, sa, sp, da, dp)
        svc = svc_map.get(k5) or svc_map.get(key5(proto, sa, sp, da, dp)) or "-"
        st = float(r["stime"])

        # sliding window: tambah current dulu, lalu evict > N
        win.append((sa, da, sp, dp, svc))
        c_src[sa] += 1; c_dst[da] += 1
        c_srv_src[(svc, sa)] += 1; c_srv_dst[(svc, da)] += 1
        c_src_dport[(sa, dp)] += 1; c_dst_sport[(da, sp)] += 1; c_dst_src[(sa, da)] += 1
        if len(win) > N:
            osa, oda, osp, odp, osv = win.popleft()
            dec(c_src, osa); dec(c_dst, oda)
            dec(c_srv_src, (osv, osa)); dec(c_srv_dst, (osv, oda))
            dec(c_src_dport, (osa, odp)); dec(c_dst_sport, (oda, osp)); dec(c_dst_src, (osa, oda))

        h = http5.get(k5, {}); ftp = ftp5.get(k5, {})
        cat, lab = label_of(sa, da, st); nlab[cat] += 1

        def num(x, d="0"): return x if x not in (None, "") else d
        row = {
            "srcip": sa, "sport": num(sp), "dstip": da, "dsport": num(dp),
            "proto": proto, "state": r["state"], "dur": r["dur"],
            "sbytes": r["sbytes"], "dbytes": r["dbytes"], "sttl": num(r["sttl"]),
            "dttl": num(r["dttl"]), "sloss": num(r["sloss"]), "dloss": num(r["dloss"]),
            "service": svc, "Sload": num(r["sload"]), "Dload": num(r["dload"]),
            "Spkts": num(r["spkts"]), "Dpkts": num(r["dpkts"]), "swin": num(r["swin"]),
            "dwin": num(r["dwin"]), "stcpb": num(r["stcpb"]), "dtcpb": num(r["dtcpb"]),
            "smeansz": num(r["smeansz"]), "dmeansz": num(r["dmeansz"]),
            "trans_depth": h.get("trans_depth", 0), "res_bdy_len": h.get("res_bdy_len", 0),
            "Sjit": num(r["sjit"]), "Djit": num(r["djit"]),
            "Stime": r["stime"], "Ltime": r["ltime"],
            "Sintpkt": num(r["sintpkt"]), "Dintpkt": num(r["dintpkt"]),
            "tcprtt": num(r["tcprtt"]), "synack": num(r["synack"]), "ackdat": num(r["ackdat"]),
            "is_sm_ips_ports": 1 if (sa == da and sp == dp and sp) else 0,
            "ct_state_ttl": g_state_ttl[(r["state"], r["sttl"], r["dttl"])],
            "ct_flw_http_mthd": h.get("mthd", 0),
            "is_ftp_login": ftp.get("login", 0),
            "ct_ftp_cmd": ftp.get("cmd", 0),
            "ct_srv_src": c_srv_src[(svc, sa)], "ct_srv_dst": c_srv_dst[(svc, da)],
            "ct_dst_ltm": c_dst[da], "ct_src_ltm": c_src[sa],
            "ct_src_dport_ltm": c_src_dport[(sa, dp)],
            "ct_dst_sport_ltm": c_dst_sport[(da, sp)],
            "ct_dst_src_ltm": c_dst_src[(sa, da)],
            "attack_cat": cat, "label": lab,
        }
        if a.add_vantage:
            row["vantage"] = r["segment"]
        out_rows.append(row)

    cols = UNSW_COLS + (["vantage"] if a.add_vantage else [])
    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader(); w.writerows(out_rows)
    print(f"[B] tulis {len(out_rows)} baris, {len(cols)} kolom -> {a.out}")
    print(f"[B] label: {dict(nlab)}")

if __name__ == "__main__":
    main()
