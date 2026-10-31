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
#!/usr/bin/env python3
# Tahap B — gabungkan CSV argus (Tahap A) + Zeek (service/http/ftp) -> hitung ct_* &
# flag sliding-window -> label per marker window -> CSV final 49 kolom UNSW-NB15.
#
# Usage:
#   build_dataset.py --argus-dir <dir CSV Tahap A> --zeek-root <dir berisi zeek-<iface>/>
#                    --markers <markers.csv> --out <final.csv>
#                    [--attacker-ip 10.10.30.10] [--window 100]
#                    [--sload-unit auto|bits|bytes] [--no-time-scale]
#
# markers.csv: header scenario,attack_cat,phase,target,start_utc,end_utc
#   (format sama dgn ~/attack-markers.csv dari scenarios/_lib/common.sh)
#
# CATATAN definisi ct_* mengikuti SEMANTIK UNSW-NB15 (nama+arti kolom). Implementasi
# C asli feature-generator UNSW tak pernah dirilis publik -> ini reproduksi level-skema,
# bukan bit-identik. Lihat CHANGES di akhir file untuk detail perbaikan vs versi lama.
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

# ---------- helpers ----------

def parse_iso(s):
    """2026-10-08T17:07:54Z -> epoch (UTC)."""
    return datetime.strptime(s.strip(), "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc).timestamp()

def safe_float(x, default=0.0):
    """Konversi toleran: None/''/'-'/'NaN' -> default."""
    if x in (None, "", "-", "(empty)"):
        return default
    try:
        v = float(x)
        if v != v:  # NaN check
            return default
        return v
    except (TypeError, ValueError):
        return default

def safe_int(x, default=0):
    return int(safe_float(x, default))

def read_zeek(path):
    """Parse satu Zeek .log (TSV header #fields). return (fields, list[dict])."""
    if not os.path.exists(path):
        return [], []
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

def z(v):
    """Zeek placeholder '-'/'(empty)'/'' -> None."""
    return None if v in ("-", "(empty)", "") else v

def key5(proto, sa, sp, da, dp):
    return (str(proto).lower(), sa, str(sp), da, str(dp))

def ttl_bucket(v):
    """Bucket TTL ke 5 level, meniru kategori TTL di UNSW:
       0 = tidak ada / 0
       1 = 1..64      (Linux/macOS default)
       2 = 65..128    (Windows default)
       3 = 129..192   (jarang)
       4 = 193..255   (network appliance / initial TTL 255)
    """
    t = safe_int(v, 0)
    if t <= 0:   return 0
    if t <= 64:  return 1
    if t <= 128: return 2
    if t <= 192: return 3
    return 4

# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--argus-dir", required=True)
    ap.add_argument("--zeek-root", required=True,
                    help="dir berisi zeek-<iface>/ (mis. extraction)")
    ap.add_argument("--markers", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--attacker-ip", default="10.10.30.10",
                    help="label=1 butuh IP ini sbg saddr/daddr dlm window; '' = window-only")
    ap.add_argument("--window", type=int, default=100)
    ap.add_argument("--dedup", choices=["dest", "off"], default="dest",
                    help="dest (default)=single-view, 1 flow/koneksi (ambil vantage "
                         "sisi tujuan) -> dataset UTAMA komparabel UNSW. off=multi-view.")
    ap.add_argument("--add-vantage", action="store_true",
                    help="tambah kolom 'vantage' (segmen sensor) di output.")
    ap.add_argument("--sload-unit", choices=["auto", "bits", "bytes"], default="auto",
                    help="Argus sload/dload dalam bits/s atau bytes/s? "
                         "auto = deteksi dari sample sbytes vs sload*dur. "
                         "UNSW Sload = bits/s, jadi bytes akan dikali 8.")
    ap.add_argument("--no-time-scale", action="store_true",
                    help="jangan konversi sinpkt/dinpkt dari us -> ms "
                         "(default: konversi, karena UNSW Sintpkt dalam mSec).")
    ap.add_argument("--verbose", "-v", action="store_true")
    a = ap.parse_args()

    def vlog(*args):
        if a.verbose:
            print(*args)

    # ---- 1) baca semua CSV argus (Tahap A) ----
    argus_rows = []
    for csvf in sorted(glob.glob(os.path.join(a.argus_dir, "*_argus49.csv"))):
        n0 = len(argus_rows)
        with open(csvf) as f:
            for r in csv.DictReader(f):
                argus_rows.append(r)
        vlog(f"[B]   {os.path.basename(csvf)}: +{len(argus_rows)-n0} rows")
    if not argus_rows:
        sys.exit(f"ERROR: tak ada *_argus49.csv di {a.argus_dir}")
    argus_rows.sort(key=lambda r: safe_float(r.get("stime"), 0.0))
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
        return safe_int(r.get("spkts")) + safe_int(r.get("dpkts"))

    if a.dedup == "dest":
        # Key dedup: 5-tuple + bucket 2 detik (toleransi split timing antar sensor).
        # Bucket dibulatkan supaya kedua vantage yang beda timestamp <2s tetap match.
        seen = {}
        kept = []
        for r in argus_rows:
            k = (r.get("proto"), r.get("saddr"), r.get("sport"),
                 r.get("daddr"), r.get("dport"),
                 round(safe_float(r.get("stime"), 0.0) / 2))
            pref = seg_for_ip(r.get("daddr", ""))
            if k not in seen:
                seen[k] = len(kept)
                kept.append(r)
            else:
                cur = kept[seen[k]]
                cur_is_pref = (cur.get("segment") == pref)
                new_is_pref = (r.get("segment") == pref)
                better = (new_is_pref and not cur_is_pref) or \
                         (not new_is_pref and not cur_is_pref
                          and npkts(r) > npkts(cur))
                if better:
                    kept[seen[k]] = r
        print(f"[B] dedup=dest: {len(argus_rows)} -> {len(kept)} flow (single-view)")
        argus_rows = kept
    else:
        print("[B] dedup=off: multi-view (semua vantage dipertahankan)")

    # ---- 2) Zeek conn.log -> service by 5-tuple + uid->5tuple map ----
    svc_map = {}
    uid5 = {}
    zeek_conn_total = 0
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, conn = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "conn.log"))
        zeek_conn_total += len(conn)
        for r in conn:
            k = key5(r.get("proto"), r.get("id.orig_h"), r.get("id.orig_p"),
                     r.get("id.resp_h"), r.get("id.resp_p"))
            sv = z(r.get("service"))
            if sv and k not in svc_map:
                svc_map[k] = sv
            if r.get("uid"):
                uid5[r["uid"]] = k
    print(f"[B] zeek conn rows: {zeek_conn_total}, "
          f"service keys: {len(svc_map)}, uid map: {len(uid5)}")

    # Lookup service dengan fallback bidirectional (Zeek orig/resp bisa flip dari Argus).
    def lookup_service(proto, sa, sp, da, dp):
        k_fwd = key5(proto, sa, sp, da, dp)
        v = svc_map.get(k_fwd)
        if v:
            return v
        # reverse: kalau Zeek lihat arah sebaliknya
        return svc_map.get(key5(proto, da, dp, sa, sp))

    # ---- 3) http.log -> per 5tuple: trans_depth, res_bdy_len, has_method ----
    http5 = {}
    http_stats = {"rows": 0, "match_uid": 0, "match_5t": 0, "skip": 0}
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, hrows = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "http.log"))
        for r in hrows:
            http_stats["rows"] += 1
            # Coba uid dulu
            k = uid5.get(r.get("uid"))
            if k:
                http_stats["match_uid"] += 1
            else:
                # Fallback: 5-tuple langsung dari http.log (Zeek menulisnya di sini)
                if r.get("id.orig_h") and r.get("id.resp_h"):
                    k = key5(r.get("proto"), r.get("id.orig_h"), r.get("id.orig_p"),
                             r.get("id.resp_h"), r.get("id.resp_p"))
                    http_stats["match_5t"] += 1
            if not k:
                http_stats["skip"] += 1
                continue
            td = safe_int(z(r.get("trans_depth")), 0)
            rb = safe_int(z(r.get("response_body_len")), 0)
            meth = z(r.get("method"))
            d = http5.setdefault(k, {"trans_depth": 0, "res_bdy_len": 0, "mthd": 0})
            d["trans_depth"] = max(d["trans_depth"], td)
            d["res_bdy_len"] += rb
            if meth in ("GET", "POST"):
                d["mthd"] = 1
    print(f"[B] http.log rows: {http_stats['rows']}, "
          f"match via uid: {http_stats['match_uid']}, "
          f"via 5tuple: {http_stats['match_5t']}, "
          f"skip: {http_stats['skip']}, unique 5tuple: {len(http5)}")
    if http_stats["rows"] > 0 and len(http5) == 0:
        print("   WARN: http.log ada baris tapi tak ada match -> cek schema #fields")

    # ---- 4) ftp.log -> per 5tuple: is_ftp_login, ct_ftp_cmd ----
    ftp5 = {}
    ftp_stats = {"rows": 0, "match_uid": 0, "match_5t": 0, "skip": 0}
    for seg in ("enp0s8", "enp0s9", "enp0s10"):
        _, frows = read_zeek(os.path.join(a.zeek_root, f"zeek-{seg}", "ftp.log"))
        for r in frows:
            ftp_stats["rows"] += 1
            k = uid5.get(r.get("uid"))
            if k:
                ftp_stats["match_uid"] += 1
            else:
                if r.get("id.orig_h") and r.get("id.resp_h"):
                    k = key5(r.get("proto"), r.get("id.orig_h"), r.get("id.orig_p"),
                             r.get("id.resp_h"), r.get("id.resp_p"))
                    ftp_stats["match_5t"] += 1
            if not k:
                ftp_stats["skip"] += 1
                continue
            d = ftp5.setdefault(k, {"login": 0, "cmd": 0})
            if z(r.get("command")):
                d["cmd"] += 1
            rc = z(r.get("reply_code"))
            user = z(r.get("user"))
            if (rc and str(rc).startswith("230")) or \
               (user and user not in ("anonymous",)):
                d["login"] = 1
    print(f"[B] ftp.log rows: {ftp_stats['rows']}, "
          f"match via uid: {ftp_stats['match_uid']}, "
          f"via 5tuple: {ftp_stats['match_5t']}, "
          f"skip: {ftp_stats['skip']}, unique 5tuple: {len(ftp5)}")

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

    # ---- 5b) auto-detect Argus sload unit ----
    # UNSW Sload = bits/s. Argus ra_export bisa bytes/s atau bits/s tergantung versi.
    # Deteksi: sample N flow dgn dur>0 & sbytes>0, bandingkan sload*dur vs sbytes.
    #   sload*dur ~ sbytes  -> bytes/s (perlu *8)
    #   sload*dur ~ sbytes*8 -> bits/s (sudah benar)
    sload_factor = 1.0
    if a.sload_unit == "auto":
        samples = []
        for r in argus_rows:
            d = safe_float(r.get("dur"), 0)
            sb = safe_float(r.get("sbytes"), 0)
            sl = safe_float(r.get("sload"), 0)
            if d > 0.001 and sb > 100 and sl > 0 and len(samples) < 200:
                samples.append((sl * d) / sb)
        if samples:
            samples.sort()
            median_ratio = samples[len(samples) // 2]
            # ratio ~1 => bytes/s; ratio ~8 => bits/s
            if 0.3 < median_ratio < 3.0:
                sload_factor = 8.0
                detected = "bytes/s"
            elif 5.0 < median_ratio < 15.0:
                sload_factor = 1.0
                detected = "bits/s"
            else:
                sload_factor = 8.0
                detected = f"unknown (ratio {median_ratio:.2f}), assume bytes/s"
            print(f"[B] sload auto-detect: {detected} -> factor={sload_factor} "
                  f"(median sload*dur/sbytes={median_ratio:.3f})")
        else:
            sload_factor = 8.0
            print("[B] sload auto-detect: tak cukup sample -> default bytes/s (x8)")
    elif a.sload_unit == "bytes":
        sload_factor = 8.0
        print("[B] sload unit: bytes/s (x8)")
    else:
        sload_factor = 1.0
        print("[B] sload unit: bits/s (no change)")

    time_factor = 1.0 if a.no_time_scale else 0.001  # us -> ms
    print(f"[B] sinpkt/dinpkt scale: x{time_factor} "
          f"({'raw' if a.no_time_scale else 'us->ms'})")

    # ---- 6) sliding-window counters (last N, kronologis) ----
    N = a.window
    # Tuple window: (sa, da, sp, dp, svc, key_state_ttl)
    win = deque()
    c_src = Counter()
    c_dst = Counter()
    c_srv_src = Counter()
    c_srv_dst = Counter()
    c_src_dport = Counter()
    c_dst_sport = Counter()
    c_dst_src = Counter()
    c_state_ttl = Counter()  # PERBAIKAN: bukan global, tapi sliding-window

    def dec(cnt, k):
        if cnt[k] <= 1:
            del cnt[k]
        else:
            cnt[k] -= 1

    out_rows = []
    nlab = Counter()
    svc_miss = 0
    for r in argus_rows:
        sa = r.get("saddr", "")
        da = r.get("daddr", "")
        sp = r.get("sport", "")
        dp = r.get("dport", "")
        proto = (r.get("proto") or "").lower()
        st = safe_float(r.get("stime"), 0.0)

        # Service lookup: bidirectional
        svc = lookup_service(proto, sa, sp, da, dp)
        if svc is None:
            svc = "-"
            svc_miss += 1

        # ct_state_ttl key: PERBAIKAN — TTL di-bucket supaya kardinalitas kecil
        key_st = (r.get("state", ""), ttl_bucket(r.get("sttl")),
                  ttl_bucket(r.get("dttl")))

        # sliding window: tambah current dulu, lalu evict > N
        win.append((sa, da, sp, dp, svc, key_st))
        c_src[sa] += 1
        c_dst[da] += 1
        c_srv_src[(svc, sa)] += 1
        c_srv_dst[(svc, da)] += 1
        c_src_dport[(sa, dp)] += 1
        c_dst_sport[(da, sp)] += 1
        c_dst_src[(sa, da)] += 1
        c_state_ttl[key_st] += 1
        if len(win) > N:
            osa, oda, osp, odp, osv, okey_st = win.popleft()
            dec(c_src, osa)
            dec(c_dst, oda)
            dec(c_srv_src, (osv, osa))
            dec(c_srv_dst, (osv, oda))
            dec(c_src_dport, (osa, odp))
            dec(c_dst_sport, (oda, osp))
            dec(c_dst_src, (osa, oda))
            dec(c_state_ttl, okey_st)

        # HTTP / FTP lookup (bidirectional)
        k_fwd = key5(proto, sa, sp, da, dp)
        k_rev = key5(proto, da, dp, sa, sp)
        h = http5.get(k_fwd) or http5.get(k_rev) or {}
        ftp = ftp5.get(k_fwd) or ftp5.get(k_rev) or {}

        cat, lab = label_of(sa, da, st)
        nlab[cat] += 1

        # Numeric field dengan konversi unit
        sload_out = safe_float(r.get("sload")) * sload_factor
        dload_out = safe_float(r.get("dload")) * sload_factor
        sinpkt_out = safe_float(r.get("sintpkt")) * time_factor
        dinpkt_out = safe_float(r.get("dintpkt")) * time_factor

        row = {
            "srcip": sa, "sport": sp, "dstip": da, "dsport": dp,
            "proto": proto, "state": r.get("state", ""),
            "dur": safe_float(r.get("dur")),
            "sbytes": safe_int(r.get("sbytes")),
            "dbytes": safe_int(r.get("dbytes")),
            "sttl": safe_int(r.get("sttl")),
            "dttl": safe_int(r.get("dttl")),
            "sloss": safe_int(r.get("sloss")),
            "dloss": safe_int(r.get("dloss")),
            "service": svc,
            "Sload": sload_out,
            "Dload": dload_out,
            "Spkts": safe_int(r.get("spkts")),
            "Dpkts": safe_int(r.get("dpkts")),
            "swin": safe_int(r.get("swin")),
            "dwin": safe_int(r.get("dwin")),
            "stcpb": safe_int(r.get("stcpb")),
            "dtcpb": safe_int(r.get("dtcpb")),
            "smeansz": safe_float(r.get("smeansz")),
            "dmeansz": safe_float(r.get("dmeansz")),
            "trans_depth": h.get("trans_depth", 0),
            "res_bdy_len": h.get("res_bdy_len", 0),
            "Sjit": safe_float(r.get("sjit")),
            "Djit": safe_float(r.get("djit")),
            "Stime": safe_float(r.get("stime")),
            "Ltime": safe_float(r.get("ltime")),
            "Sintpkt": sinpkt_out,
            "Dintpkt": dinpkt_out,
            "tcprtt": safe_float(r.get("tcprtt")),
            "synack": safe_float(r.get("synack")),
            "ackdat": safe_float(r.get("ackdat")),
            "is_sm_ips_ports": 1 if (sa == da and sp == dp and sp) else 0,
            "ct_state_ttl": c_state_ttl[key_st],   # PERBAIKAN
            "ct_flw_http_mthd": h.get("mthd", 0),
            "is_ftp_login": ftp.get("login", 0),
            "ct_ftp_cmd": ftp.get("cmd", 0),
            "ct_srv_src": c_srv_src[(svc, sa)],
            "ct_srv_dst": c_srv_dst[(svc, da)],
            "ct_dst_ltm": c_dst[da],
            "ct_src_ltm": c_src[sa],
            "ct_src_dport_ltm": c_src_dport[(sa, dp)],
            "ct_dst_sport_ltm": c_dst_sport[(da, sp)],
            "ct_dst_src_ltm": c_dst_src[(sa, da)],
            "attack_cat": cat,
            "label": lab,
        }
        if a.add_vantage:
            row["vantage"] = r.get("segment", "")
        out_rows.append(row)

    # ---- 7) tulis CSV ----
    cols = UNSW_COLS + (["vantage"] if a.add_vantage else [])
    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(out_rows)
    print(f"[B] tulis {len(out_rows)} baris, {len(cols)} kolom -> {a.out}")
    print(f"[B] label: {dict(nlab)}")
    if svc_miss:
        print(f"[B] service miss: {svc_miss} flow -> '-' "
              f"({100*svc_miss/max(1,len(out_rows)):.1f}%)")

    # ---- 8) kolom summary (deteksi kolom mati / rusak) ----
    print(f"\n[B] === Column summary ===")
    print(f"    {'column':<22} {'nz%':>6} {'min':>10} {'median':>12} {'max':>12} {'uniq':>6}")
    warn_cols = []
    numeric_check_cols = [c for c in UNSW_COLS
                          if c not in ("srcip", "dstip", "sport", "dsport",
                                       "proto", "state", "service",
                                       "attack_cat", "label")]
    for col in numeric_check_cols:
        vals = [safe_float(r[col]) for r in out_rows]
        nz = sum(1 for v in vals if v != 0)
        nz_pct = 100.0 * nz / max(1, len(vals))
        s = sorted(vals)
        n = len(s)
        mn = s[0] if n else 0
        med = s[n // 2] if n else 0
        mx = s[-1] if n else 0
        uniq = len(set(vals))
        print(f"    {col:<22} {nz_pct:>5.1f}% {mn:>10.4g} {med:>12.4g} "
              f"{mx:>12.4g} {uniq:>6}")
        if nz_pct == 0:
            warn_cols.append(f"{col}: all zero")
        elif uniq == 1:
            warn_cols.append(f"{col}: constant ({vals[0]})")
        elif uniq > 0.9 * n:
            warn_cols.append(f"{col}: nearly unique ({uniq}/{n}) - mungkin ID/raw value")
    if warn_cols:
        print("\n[B] WARN kolom bermasalah:")
        for w_ in warn_cols:
            print(f"    - {w_}")


if __name__ == "__main__":
    main()

# ============================================================================
# CHANGES vs versi lama
# ----------------------------------------------------------------------------
# 1. ct_state_ttl: SEBELUMNYA dihitung sebagai count GLOBAL per (state, sttl,
#    dttl) triplet -> nilainya besar (9585, 9488, ...) dan menyesatkan model
#    (korelasi negatif di Lab, positif di UNSW). SEKARANG sliding-window count
#    dengan TTL di-bucket ke 5 level -> nilai kecil (~0-100) dan konsisten
#    arah antar dataset. Ini perbaikan paling berdampak.
#
# 2. Unit conversion: Sload/Dload dari Argus (bytes/s) dikali 8 -> bits/s
#    sesuai definisi UNSW. Sintpkt/Dintpkt dari Argus (us) dikali 0.001 ->
#    ms sesuai UNSW. Auto-detect untuk sload dengan --sload-unit=auto.
#
# 3. HTTP/FTP mapping: SEBELUMNYA hanya via uid -> gagal kalau uid tidak
#    resolve (yang terjadi di dataset Anda: trans_depth,res_bdy_len,
#    ct_flw_http_mthd semua 0). SEKARANG fallback ke 5-tuple langsung dari
#    http.log (Zeek menulis id.orig_h/id.resp_h di sana) + bidirectional.
#
# 4. Service lookup: SEBELUMNYA forward saja -> kalau Zeek lihat arah
#    terbalik dari Argus, miss. SEKARANG bidirectional fallback.
#
# 5. Robustness: safe_float/safe_int untuk handle None/''/'-'/'NaN', tanpa
#    crash. Dedup key tetap 2-detik bucket tapi lebih toleran.
#
# 6. Diagnostik: print per-file row count, match rate HTTP/FTP, service miss%,
#    column summary dengan warning untuk kolom mati/konstan/nearly-unique.
# ============================================================================