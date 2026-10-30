# Data card â€” lab_flows.csv

Total flow: **167,568**  |  sesi: 2  |  arsip: 8

## Distribusi kelas per sesi (baris)

| attack_cat | run-1 | run-2 | TOTAL |
|---|---|---|---|
| Analysis | 1936 | 1929 | 3865 |
| Backdoor | 8664 | 7682 | 16346 |
| Brute Force | 4682 | 4343 | 9025 |
| DoS | 2571 | 2614 | 5185 |
| Exploits | 2554 | 2558 | 5112 |
| Normal | 9357 | 66025 | 75382 |
| Reconnaissance | 26204 | 26449 | 52653 |
| TOTAL | 55968 | 111600 | 167568 |

## Distribusi skenario per sesi

| scenario | run-1 | run-2 | TOTAL |
|---|---|---|---|
| N01 | 6799 | 63883 | 70682 |
| N01-outside | 352 | 289 | 641 |
| S01 | 26228 | 26475 | 52703 |
| S02 | 2825 | 3033 | 5858 |
| S03 | 1171 | 1177 | 2348 |
| S04 | 2662 | 2664 | 5326 |
| S05 | 1279 | 645 | 1924 |
| S06 | 1570 | 459 | 2029 |
| S07 | 1040 | 854 | 1894 |
| S08 | 2604 | 2597 | 5201 |
| S09 | 2282 | 2284 | 4566 |
| S10 | 2446 | 2455 | 4901 |
| S11 | 2712 | 2773 | 5485 |
| S12 | 1998 | 2012 | 4010 |
| TOTAL | 55968 | 111600 | 167568 |

## Kualitas data

- Flow attack tanpa window marker (harus 0): **0**
- Duplikat (srcip,sport,dstip,dsport,proto,Stime): **0**
- Baris dengan `Djit` null: **11010**
- Rentang waktu: 2026-10-22 05:11:44.358130932+00:00 s/d 2026-10-27 08:23:54.609544039+00:00