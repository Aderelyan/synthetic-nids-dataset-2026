# Network Topology

Topologi final 8-VM, terkunci per `blueprint-v3-updated.md` §2–3. Lab sepenuhnya
terisolasi dari jaringan fisik/internet publik — satu-satunya jalur keluar
adalah `NatNetwork-temp`, yang bersifat sementara (hanya untuk instalasi OS/update)
dan wajib dilepas sebelum Phase 6 (validasi isolasi).

```text
                         HOST (VirtualBox, i7 Gen12, 40 GB RAM)
                                        |
                  "VirtualBox Host-Only Ethernet Adapter" (192.168.56.0/24)
                                        | (MGMT only, dari host)
                              +---------+---------+
                              |  router-opnsense    |
                              |  (OPNsense/FreeBSD) |
                              |  em0: hostonly      |
                              |  em1: intnet-server |
                              |  em2: intnet-client |
                              |  em3: intnet-attacker|
                              +--+--------+------+--+
                                 |        |      |
       intnet-server (10.10.10.0/24)      |      intnet-attacker (10.10.30.0/24)
                                 |        |      |
              +------------------+        |      +------------------+
              |                           |                         |
    +-----------------+     intnet-client |             +------------------+
    |   srv-web        |     (10.10.20.0/24)            |  attacker (Kali) |
    |   10.10.10.10    |                  |             |  10.10.30.10     |
    +-----------------+        +---------+--------+    +------------------+
                               |                  |
    +-----------------+        | client-1 .20      |
    |   srv-file       |        | client-2 .21      |  (Linux Phase saja)
    |   10.10.10.11    |        | win-client .50 +   |  (Windows Phase saja,
    +-----------------+        |   hostonly NIC2    |   NIC hostonly ke-2
                               |   (RDP mgmt)       |   untuk akses mgmt)
                               +------------------+

    +-----------------------------------------------------+
    |         sensor (Debian headless — capture node)      |
    |  NIC1 hostonly 192.168.56.20   (mgmt, SSH langsung)  |
    |  NIC2 intnet-server 10.10.10.20   (promiscuous)      |
    |  NIC3 intnet-client 10.10.20.30   (promiscuous)      |
    |  NIC4 intnet-attacker 10.10.30.20 (promiscuous)      |
    |  Capture: tcpdump (live, full, no port filter)       |
    |  Extraction offline: Zeek + Argus (-r <pcap>)        |
    |  IDS live: Suricata (af-packet)                      |
    |  [pcap-first, locked 2026-10-02 — phase5-sensor §7]  |
    +-----------------------------------------------------+
```

## Tabel Alamat & Peran

| VM | Segmen | IP | Peran |
|---|---|---|---|
| router-opnsense | hostonly / server / client / attacker | .56.10 / .10.1 / .20.1 / .30.1 | Gateway + firewall tiap segmen |
| srv-web | intnet-server | 10.10.10.10 | nginx, DVWA/Juice Shop (target S-04) |
| srv-file | intnet-server | 10.10.10.11 | SSH, SMB/Samba, syslog |
| client-1 | intnet-client | 10.10.20.20 | Linux Phase |
| client-2 | intnet-client | 10.10.20.21 | Linux Phase |
| win-client | intnet-client + hostonly | 10.10.20.50 / 192.168.56.x | Windows Phase; NIC kedua untuk RDP mgmt langsung |
| attacker | intnet-attacker | 10.10.30.10 | Kali — sumber semua skenario serangan |
| sensor | hostonly + 3×intnet | .56.20 / .10.20 / .20.30 / .30.20 | Capture pasif promiscuous di 3 segmen |

## Prinsip Isolasi

- Tidak ada NIC dengan attachment `nat`/`bridged` pada VM manapun kecuali `NatNetwork-temp` — dan itu pun sementara, dilepas sebelum Phase 6.
- Setiap segmen `intnet` hanya bisa saling berkomunikasi lewat OPNsense (tidak ada direct routing antar-intnet di level VirtualBox).
- DNS: semua resolusi lewat Unbound di OPNsense (`192.168.56.10`), host override untuk domain `*.lab.local` — tidak ada upstream DNS publik.
- `win-client` dan `client-1`/`client-2` berbagi segmen `intnet-client`, tapi **tidak pernah berjalan bersamaan** (phase-switching, lihat `infra/vagrant/switch-phase/`).

Lihat juga `infra/opnsense/` (host overrides Unbound) dan `docs/blueprint-v3-updated.md`
§2–4 untuk status implementasi tiap VM.

**Catatan arsitektur capture (update 2026-10-02):** sensor memakai tcpdump sebagai
satu-satunya capture layer *live*, full-capture tanpa filter port per-phase —
`capture/tcpdump-filters.md` (pendekatan filter port lama) **sudah tidak berlaku**
setelah keputusan pcap-first dikunci. Zeek dan Argus memproses pcap yang sama
secara offline; lihat `docs/phase5-sensor.md` §7 untuk detail lengkap.
