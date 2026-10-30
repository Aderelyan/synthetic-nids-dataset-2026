# pipeline/ — Argus+Zeek → CSV final 49 kolom UNSW-NB15

Mengubah hasil ekstraksi sensor (`.argus` biner + Zeek `.log`) menjadi 1 CSV
berskema UNSW-NB15 (49 kolom, termasuk `attack_cat` + `label`).

## Dua tahap (beda tempat jalan)

| Tahap | Skrip | Butuh | Jalan di |
|---|---|---|---|
| A — re-export argus 49-field | `ra_export.sh` | `ra` **v5** (argus-client v5) | **sensor** (argus 5.0.2) atau mesin ber-`ra` v5. **BUKAN** host Windows, **BUKAN** `ra` v3 (v3 tak bisa baca file argus v5). |
| B — merge Zeek + ct_* + label | `build_dataset.py` | Python 3 **stdlib saja** (tanpa pandas) | di mana saja — host Windows OK |

Alur: `argus -r pcap -w seg.argus` (sudah di sensor, Phase 5) → **A** `ra_export.sh`
→ `*_argus49.csv` → **B** `build_dataset.py` (+ Zeek logs + markers) → `unsw_<scn>.csv`.

## Tahap A

```bash
# di sensor (punya ra v5) atau mesin build:
bash ra_export.sh <extraction_dir> <out_dir> [ra_binary]
#   extraction_dir : folder berisi argus-<iface>/<iface>.argus
#   out_dir        : tujuan CSV
# contoh:
bash ra_export.sh extraction /tmp/argus_csv ra
```
Output: `<iface>_argus49.csv` (32 field argus: epoch stime/ltime, nomar) + kolom `segment`.

`ra` v5 belum ada? build sekali dari source (butuh internet/GitHub):
```bash
apt-get install -y build-essential flex bison libpcap-dev zlib1g-dev git
git clone --depth 1 https://github.com/openargus/clients.git
cd clients && ./configure && make -j$(nproc)   # biner: bin/ra
```

## Tahap B

```bash
python3 build_dataset.py \
  --argus-dir <dir CSV Tahap A> \
  --zeek-root <dir berisi zeek-<iface>/> \
  --markers <markers.csv> \
  --out unsw_<scn>.csv \
  [--attacker-ip 10.10.30.10] [--window 100]
```

`markers.csv` = format sama `~/attack-markers.csv` (dari `scenarios/_lib/common.sh`):
```
scenario,attack_cat,phase,target,start_utc,end_utc
S01,Reconnaissance,linux,multi,2026-10-08T17:07:54Z,2026-10-08T17:08:53Z
```

### Dua varian dataset (keputusan 2026-10-12)
Flow lintas-segmen tercatat di >1 vantage (tanpa SNAT, 5-tuple sama). Opsi `--dedup`:
- **`--dedup dest` (default) = SINGLE-VIEW, dataset UTAMA** — 1 flow/koneksi, ambil baris dari
  sensor di segmen IP tujuan (paling lengkap). Komparabel ke UNSW-NB15. Output 49 kolom.
- **`--dedup off --add-vantage` = MULTI-VIEW, varian/kontribusi** — simpan semua vantage +
  kolom `vantage` (50 kolom). Untuk studi sensor-placement.

Uji S01: single-view 10.366 flow (49 kol) vs multi-view 20.576 flow (50 kol).

### Label
- `label=1` + `attack_cat=<cat>` jika `stime` flow ada di dalam window marker **dan**
  (`--attacker-ip` kosong → window-only; atau IP attacker jadi `saddr`/`daddr`).
  Default `--attacker-ip 10.10.30.10` → lebih bersih (trafik background NTP/ARP di
  dalam window yang tak melibatkan attacker tetap `Normal`). Tidak ada SNAT inter-segmen
  di lab ini (terverifikasi) → IP attacker andal di semua segmen.
- selain itu `label=0`, `attack_cat=Normal`.

### Definisi fitur (ringkas)
- **Argus native**: dur, s/dbytes, s/dttl, s/dloss, S/Dpkts, s/dwin, s/dtcpb, s/dmeansz,
  S/Dload, S/Djit, S/Dintpkt, tcprtt, synack, ackdat, state, Stime, Ltime.
- **Zeek**: `service` (conn.log, locked decision #2), `trans_depth`/`res_bdy_len`/
  `ct_flw_http_mthd` (http.log), `is_ftp_login`/`ct_ftp_cmd` (ftp.log).
- **sliding-window `--window` (default 100 koneksi, urut `stime`)**: ct_srv_src,
  ct_srv_dst, ct_dst_ltm, ct_src_ltm, ct_src_dport_ltm, ct_dst_sport_ltm,
  ct_dst_src_ltm.
- **ct_state_ttl**: grup global (state, sttl, dttl).
- **is_sm_ips_ports**: 1 jika saddr==daddr & sport==dport.

Skema mengikuti **semantik** UNSW-NB15 (nama+arti kolom). Generator fitur C asli
UNSW tak pernah dirilis publik → ini reproduksi level-skema, bukan bit-identik
(lihat `docs/phase5-sensor.md` §7.3 honesty note).

## CAVEAT
- **`Sjit`/`Djit`/`Sintpkt`/`Dintpkt` kosong (→0)** pada data S01: argus di sensor
  dijalankan dengan config default yang tak menghitung jitter/inter-packet time.
  Untuk capture beneran, generate argus dengan opsi timing (mis. pastikan argus
  menyimpan metrik ini) bila 4 fitur ini penting; else diterima sebagai 0.
- `ct_flw_http_mthd` dihitung sbg flag per-flow (ada method GET/POST) — bukan
  sliding-window; cukup untuk sinyal, bisa dijadikan window bila perlu.
- Jalankan Tahap A **per sesi/scenario** (satu set .argus per window capture), lalu
  Tahap B dgn markers sesi itu.

## Hasil uji S01 (2026-10-12)
20.576 flow → 49 kolom. Label: Reconnaissance 20.204, Normal 372. `service` benar
(scan flow = `-`; dns/ntp/http/ssh terisi), state RST/REQ/INT (khas SYN-scan),
ct_* ter-cap di 100. Lihat `unsw_s01.csv` (dikirim ke host) sebagai referensi.
