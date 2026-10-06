# Phase 5 — Sensor Provisioning (pcap-first capture: tcpdump capture + Zeek/Argus offline extraction + Suricata live IDS; Tranalyzer2 replaced by Argus)

Documentation of the sensor VM build: Debian 13.7.0 netinst installation as a headless, 4-NIC passive capture node, the ICH9 chipset requirement for a 5th temporary install NIC, static IP configuration across all 4 final segments, and capture-tooling installation (tcpdump/Zeek/Suricata/Argus; Tranalyzer2 replaced by Argus, see §7.3). Host: Windows, VirtualBox 7.2.12.

## 1. VM Resource & Storage Provisioning

Per `blueprint-v3-updated.md` §2 (locked spec): 2 vCPU, 4 GB RAM, 60 GB disk, 4 final NICs (hostonly mgmt + 3×intnet promiscuous). Unlike client/attacker VMs (1 intnet + 1 temp NAT), sensor needs all 4 NIC slots for its final role — a 5th NIC for install-time internet access requires switching the chipset from the default PIIX3 (4-NIC max via VBoxManage) to ICH9.

```cmd
VBoxManage modifyvm "sensor" --memory 4096 --cpus 2 --firmware bios --chipset ich9
VBoxManage createmedium disk --filename "C:\Users\Aderelyan\VirtualBox VMs\sensor\sensor.vdi" --size 61440 --variant Standard
VBoxManage storagectl "sensor" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "sensor" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\Aderelyan\VirtualBox VMs\sensor\sensor.vdi"
VBoxManage storagectl "sensor" --name "IDE" --add ide
VBoxManage storageattach "sensor" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\debian-13.7.0-amd64-netinst.iso"
VBoxManage modifyvm "sensor" --boot1 dvd --boot2 disk --boot3 none --boot4 none
VBoxManage modifyvm "sensor" --nic2 intnet --intnet2 "intnet-server" --nicpromisc2 allow-all
VBoxManage modifyvm "sensor" --nic3 intnet --intnet3 "intnet-client" --nicpromisc3 allow-all
VBoxManage modifyvm "sensor" --nic4 intnet --intnet4 "intnet-attacker" --nicpromisc4 allow-all
VBoxManage modifyvm "sensor" --nic5 natnetwork --nat-network5 "NatNetwork-temp"
```

NIC1 (hostonly, mgmt) already registered in Phase 1.

## 2. Known Issue: ICH9 NIC Slot Numbering Jump (installer primary-interface selection)

### Symptom
Debian installer's "Configure the network" step listed 5 interfaces with non-sequential naming — `enp0s3`, `enp0s8`, `enp0s9`, `enp0s10`, `enp0s16` — and pre-selected `enp0s10` (no internet) as the default/highlighted choice.

### Cause
Under the ICH9 chipset, VirtualBox assigns PCI slots 3/8/9/10 to NICs 1–4 sequentially (same as PIIX3), but NIC 5+ sits on a separate PCI bridge and jumps to slot 16+. The installer's "first connected interface" heuristic only checks link state (all `intnet` NICs show as "connected" even with no real traffic), not actual internet reachability.

### Fix
Manually select the highest-numbered interface as primary during install. Confirmed mapping for this VM:

| Installer interface | VBox NIC | Attachment |
|---|---|---|
| `enp0s3` | NIC1 | hostonly (mgmt) |
| `enp0s8` | NIC2 | intnet-server |
| `enp0s9` | NIC3 | intnet-client |
| `enp0s10` | NIC4 | intnet-attacker |
| `enp0s16` | **NIC5** | **NatNetwork-temp (install only) — the only one with internet** |

## 3. Known Issue: First Install Attempt Failed — Desktop Environment Mis-Selected at tasksel

### Symptom
First installation attempt selected tasksel options `1 7 11 12` (Debian desktop environment + Xfce + SSH server + standard system utilities) instead of the intended `11 12` only. The install ran far longer than any prior VM and failed at 95% ("Select and install software" → `!! ERROR: Installation step failed`), most likely a network-mirror timeout from the much larger desktop package set pulled over the comparatively fragile `NatNetwork-temp` link.

### Fix
Full reinstall from scratch (VM reset, reboot into the netinst ISO). At the tasksel step, selected **`11 12` only** — matching the locked spec ("Debian 13.7.0 headless", no desktop environment). Sensor is a passive capture node; a desktop environment only adds unnecessary RAM/disk/attack-surface.

## 4. Static IP — 4 Final Segments, No Default Route (except temp NAT)

All 4 final NICs configured without a gateway/default route — sensor only needs passive per-segment reachability for capture, not routing. Only the temp NAT NIC (`enp0s16`, DHCP) carries a default route, and will be detached before Phase 6.

`/etc/network/interfaces`:
```
auto enp0s3
iface enp0s3 inet static
    address 192.168.56.20
    netmask 255.255.255.0

auto enp0s8
iface enp0s8 inet static
    address 10.10.10.20
    netmask 255.255.255.0

auto enp0s9
iface enp0s9 inet static
    address 10.10.20.30
    netmask 255.255.255.0

auto enp0s10
iface enp0s10 inet static
    address 10.10.30.20
    netmask 255.255.255.0
```

```bash
ifup enp0s3 enp0s8 enp0s9 enp0s10
hostnamectl set-hostname sensor
timedatectl set-timezone Etc/UTC
```

`/etc/hosts`:
```
127.0.1.1    sensor
192.168.56.10   opnsense.lab.local opnsense
```

Resulting routing table — exactly one default route, via the temp NAT NIC:
```
default via 10.0.99.1 dev enp0s16 proto dhcp src 10.0.99.12 metric 1006
10.0.99.0/24 dev enp0s16 proto dhcp scope link src 10.0.99.12 metric 1006
10.10.10.0/24 dev enp0s8 proto kernel scope link src 10.10.10.20
10.10.20.0/24 dev enp0s9 proto kernel scope link src 10.10.20.30
10.10.30.0/24 dev enp0s10 proto kernel scope link src 10.10.30.20
192.168.56.0/24 dev enp0s3 proto kernel scope link src 192.168.56.20
```

## 5. SSH Access — Direct via Hostonly (No Jump Host Needed)

Unlike client-1/client-2/attacker (which sit on `intnet` segments reachable only through OPNsense), sensor's NIC1 is on the **hostonly** segment (`192.168.56.0/24`) — the same segment the Windows host itself sits on. SSH is reachable **directly**, the jump-host pattern is not needed for this VM:

```cmd
ssh sensor@192.168.56.20
```

Username is `sensor` (not `labadmin`, unlike the other Linux VMs).

### Recurring Known Issue: Stale Host Key
Same as Phase 2 §5 (`192.168.56.10` stale fingerprint) — reinstalling the VM regenerates its SSH host key, so a prior `known_hosts` entry at the same IP trips `REMOTE HOST IDENTIFICATION HAS CHANGED`.

```cmd
ssh-keygen -R 192.168.56.20
ssh sensor@192.168.56.20
```

## 6. Final Validation Results — Network Layer

| Check | Command | Result |
|---|---|---|
| All 4 final NICs up with correct static IP | `ip -br a` | `enp0s3 192.168.56.20/24`, `enp0s8 10.10.10.20/24`, `enp0s9 10.10.20.30/24`, `enp0s10 10.10.30.20/24` |
| Single default route (via temp NAT only) | `ip route` | Only 1 `default via ...` line, through `enp0s16` |
| Reachability — hostonly (OPNsense LAN) | `ping -c 3 192.168.56.10` | 0% loss |
| Reachability — intnet-server gateway | `ping -c 3 10.10.10.1` | 0% loss |
| Reachability — intnet-client gateway | `ping -c 3 10.10.20.1` | 0% loss |
| Reachability — intnet-attacker gateway | `ping -c 3 10.10.30.1` | 0% loss |
| Hostname | `hostnamectl` | `sensor` |
| Timezone | `timedatectl \| grep "Time zone"` | `Etc/UTC (UTC, +0000)` |
| apt sources | `cat /etc/apt/sources.list` | `deb.debian.org` + `security.debian.org` + `trixie-updates` — correct on first boot (no `cdrom:`-only issue this time) |
| SSH direct access | `ssh sensor@192.168.56.20` | Connected successfully (after `ssh-keygen -R`, see §5) |

## 7. Capture Tooling — pcap-first Architecture (LOCKED 2026-10-02)

**Architecture decision (2026-10-02): capture and extraction are now separate layers**, rather than Zeek/Argus/Suricata each capturing live off the wire independently:

- **Capture layer** (live, continuous, one tool): **tcpdump** → raw `.pcap`, one systemd instance per interface (§7.1).
- **Extraction layer** (offline, run against the saved `.pcap`): **Zeek** (`-r <pcap>`, §7.2) and **Argus** (`-r <pcap>`, §7.3) both process the *same* pcap file — deterministic, re-runnable, no live-capture socket contention between tools.
- **Suricata** stays on **live af-packet** (§7.4) — its role is real-time IDS alerting/detection, a different concern from flow-feature extraction, so it is not part of the pcap-first re-architecture.

Rationale: the original 3-tools-all-live-capturing-simultaneously design (first validated 2026-10-02 earlier in the day) risked CPU/socket contention on a 2 vCPU/4 GB VM during high-traffic attack scenarios, gave no raw ground-truth to re-run extraction against if labeling logic changes later, and didn't match the likely original UNSW-NB15 methodology (capture first, then run Argus/Bro against the capture). Confirmed end-to-end 2026-10-02: tcpdump captures real ICMP traffic → both `zeek -r` and `argus -r` against the identical pcap produce matching real flow records (not synthetic/placeholder data).

Base packages (via temp NAT NIC, `enp0s16`):
```bash
apt install -y curl gnupg tcpdump net-tools
```

### 7.1 tcpdump — Capture Layer, 3 Independent Processes

```bash
mkdir -p /var/log/pcap/{enp0s8,enp0s9,enp0s10}
```
```ini
# /etc/systemd/system/pcap-capture@.service
[Unit]
Description=pcap capture on %i
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/tcpdump -i %i -w /var/log/pcap/%i/%i-%%Y%%m%%d%%H%%M%%S.pcap -U -G 3600 -Z root
Restart=on-failure
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
```
Write via heredoc, verify `grep -c "ExecStart=" <file>` = 1 (see §7.3's systemd-corruption known issue — same risk with any `nano` in-place edit).

```bash
systemctl daemon-reload
systemctl enable --now pcap-capture@enp0s8 pcap-capture@enp0s9 pcap-capture@enp0s10
```

**Known Issue — pcap file stays 0 bytes despite real traffic passing.** `tcpdump -w` without `-U` buffers writes internally (libpcap default buffer, ~4KB) and only flushes on buffer-full or file close/rotation — on a low-traffic segment, a `.pcap` file can sit at 0 bytes for many minutes even though packets are actively being captured (confirmed via a parallel manual `tcpdump -c N` on the same interface, which *did* show packets immediately — the capture itself was never broken, only the on-disk visibility). **Fix: `-U` flag** (packet-buffered mode, flush after every packet) — included in the `ExecStart` above. Validated: file size increments immediately after `-U` added + instances restarted.

**`%%` escaping is mandatory** in the systemd unit — `%i` is systemd's own specifier, so tcpdump's strftime pattern (`%Y%m%d%H%M%S`) must be written `%%Y%%m%%d...` or systemd attempts to interpret `%Y` itself.

**Validated 2026-10-02:** all 3 instances `active (running)`, pcap files growing on real traffic (confirmed via manual `ping` test, ICMP visible in the capture).

### 7.2 Zeek — Offline Extraction Only (`zeek -r <pcap>`)

Install (openSUSE Build Service `security:zeek` repo — not in default Debian sources):
```bash
echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_13/ /' | tee /etc/apt/sources.list.d/security:zeek.list
curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_13/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null
apt update
apt install -y zeek
```

**Binary not in `$PATH`** — OBS package installs to `/opt/zeek/bin/`, not `/usr/bin`:
```bash
echo 'export PATH=$PATH:/opt/zeek/bin' >> /etc/profile.d/zeek.sh
source /etc/profile.d/zeek.sh
```

**Superseded history (kept for context):** originally ran as 3 live-capturing systemd instances (`zeek-capture@%i`, one process per interface — `zeekctl` was abandoned first because its standalone `node.cfg` `interface=` field doesn't support comma-separated multi-interface, and raw `zeek` also rejects repeated `-i` flags, v9.0.0 hard limit: one process = one interface). This live setup was validated working (`active (running)`, 3 segments) but **disabled 2026-10-02** in favor of pcap-first (§7 architecture decision):
```bash
systemctl disable --now zeek-capture@enp0s8 zeek-capture@enp0s9 zeek-capture@enp0s10
```

**Current usage — offline, run per pcap file (manually for now, scripted in Phase 7/8):**
```bash
mkdir -p /opt/zeek/extract/<scenario-or-window-name>
cd /opt/zeek/extract/<scenario-or-window-name>
/opt/zeek/bin/zeek -r /var/log/pcap/enp0s8/<file>.pcap local
```
Output `conn.log`/`http.log`/etc. land in the current working directory — tag with `segment`/`sensor_nic`/`pcap_source` columns downstream since one `zeek -r` run only covers one interface's pcap at a time (3 interfaces × N rotated pcap files = 3×N separate extraction runs per capture window).

**Validated 2026-10-02 (pcap-first):** `zeek -r` against a real pcap (containing manual ICMP test traffic) produced a populated `conn.log` — confirmed real flow data, not empty.

Zeek's `service` field remains the **locked source** for the `service` column in the final dataset (locked decision #2, §7.3) — more reliable than Argus's port-based service guess for traffic that deliberately uses non-standard ports (S-06, S-07, S-09).

### 7.3 Argus — Offline Extraction Only (`argus -r <pcap>`), Replaces Tranalyzer2 (LOCKED 2026-10-02)

**Decision context:** user's goal is a dataset whose columns match the original UNSW-NB15 schema as closely as possible. Research finding: the original UNSW-NB15 paper (Moustafa & Slay, 2015) generated flow records using **Argus + Bro-IDS**, not Tranalyzer2 — Tranalyzer2 was this blueprint's own earlier tooling choice (v2), not what the reference dataset actually used. Argus confirmed **actively maintained** (`github.com/openargus/clients`, Debian package `argus-client` at a March-2025 git snapshot) and packaged directly in Debian 13 trixie (`argus-server`/`argus-client`, `2:5.0.2-3`) — no build-from-source needed, unlike Tranalyzer2's dead-end.

**Honesty note (ties to blueprint §6/§7 rationale #1 and the Arp et al./Semmelrock et al. citations already there):** the original UNSW-NB15 feature-generation C code (the program that converts raw Argus records into the final 49 columns, including the `ct_*` contextual features) was **never publicly released** by the UNSW team — confirmed via literature search, no GitHub/paper artifact exists. "Identical columns" is achievable at the schema/definition level (same column names, same semantics), not as a verified identical implementation — this is a known, citable reproducibility gap in the field, not a shortcut taken by this lab.

**Column-to-source mapping (49 UNSW-NB15 features):**

| Feature group | Columns | Source |
|---|---|---|
| Basic flow | `dur`, `proto`, `sbytes`, `dbytes`, `sttl`, `dttl`, `sloss`, `dloss`, `spkts`, `dpkts` | Argus native (`ra -s ...`) |
| Content | `swin`, `dwin`, `stcpb`, `dtcpb`, `smeansz`, `dmeansz` | Argus native |
| Content (app-layer) | `trans_depth`, `res_bdy_len` | Zeek `http.log` |
| Time | `sjit`, `djit`, `sintpkt`, `dintpkt`, `tcprtt`, `synack`, `ackdat`, `stime`, `ltime` | Argus native |
| State | `state` | Argus native |
| Service | `service` | **Zeek `conn.log`** (locked decision #2 below) |
| Contextual (9 cols) | `ct_srv_src`, `ct_srv_dst`, `ct_dst_ltm`, `ct_src_ltm`, `ct_src_dport_ltm`, `ct_dst_sport_ltm`, `ct_dst_src_ltm`, `ct_state_ttl`, `ct_flw_http_mthd` | **Not available from any tool natively** — custom Python post-processing, 100-record sliding window sorted by `stime` — **deferred to Phase 7/8 (locked decision #3)** |
| Flags/label | `is_sm_ips_ports`, `is_ftp_login`, `ct_ftp_cmd` | Same as above — deferred to Phase 7/8 |
| Ground truth | `attack_cat`, `label` | This lab's own `label_by_scenario_window.py` (per blueprint §5 point 9) |

**LOCKED DECISIONS (2026-10-02):**
1. **Replace Tranalyzer2 with Argus** as the flow-feature generator — more faithful to the original dataset's methodology and trivially installable (apt package vs. Tranalyzer2's dead source).
2. **`service` column sourced from Zeek, not Argus's port-based guess.** Reason: 3 of 12 attack scenarios (S-06 WinRM, S-07 PtH/SMB, S-09 DNS tunneling/DoH) deliberately use non-standard ports or covert channels — exactly where port-based service detection fails. Zeek's DPI/signature-based detection stays correct regardless of port; Argus's guess would systematically mislabel `service` precisely on the traffic most relevant to the research, introducing a non-random bias into the most informative feature for the classifier.
3. **`ct_*` contextual features (9 cols) + `is_sm_ips_ports`/`is_ftp_login`/`ct_ftp_cmd` deferred to Phase 7/8** — not computed during capture; built later as a Python post-processing stage on merged Argus+Zeek output.

**Install:**
```bash
apt install -y argus-server argus-client
```

**Known Issue — `ArgusError: Srcid format error: hostuuid` (daemon fails to start at all, before any packet I/O).** Root cause: `/etc/argus.conf` ships with `ARGUS_MONITOR_ID=\`hostuuid\`` — backtick **shell command substitution** calling an external `hostuuid` command not packaged on Debian; substitution fails, the literal unresolved string `"hostuuid"` gets validated as srcid and rejected. Ruled out first: `/etc/machine-id` (valid) and the `-e <value>` CLI flag (no effect — proves `-e` doesn't override this codepath). **Fix:**
```bash
sed -i 's/^ARGUS_MONITOR_ID=`hostuuid`/ARGUS_MONITOR_ID=192.168.56.20/' /etc/argus.conf
```
This global config fix applies to every Argus invocation (live or offline) and only needs doing once.

**Known Issue — MAR (status/heartbeat) records masquerade as real flow data.** By default, `ra` output includes Argus's own periodic self-status records (`proto` column shows `man`, `saddr`/`daddr` are meaningless placeholder numbers, not real IPs) alongside actual traffic flow records (`FAR`). On a quiet capture these MAR records are the *only* rows present, which produced a false-positive "it's capturing real flows" read during initial live-mode validation. **Always filter them out when verifying or exporting:**
```bash
ra -M nomar -r <file>.argus -c ',' -s stime,dur,proto,saddr,sport,daddr,dport,state
```
A genuine flow record shows a real `proto` (`icmp`, `tcp`, `udp`, `arp`, ...) and real IP addresses in `saddr`/`daddr`.

**Superseded history (kept for context):** originally ran as 3 live-capturing systemd instances (`argus-capture@%i`). Also hit: `ArgusEstablishListen: bind() error` (default port-561 remote-client listen socket; not needed here — fixed with `-P 0`); a `nano` in-place unit-file edit that concatenated 3 `ExecStart=` lines onto one with no newline, causing instant `status=1/FAILURE` on all 3 instances (fixed by rewriting via heredoc, verifying `grep -c "ExecStart=" <file>` = 1); stray manual-test `argus` processes left in state `T` (stopped via `Ctrl+Z` instead of `Ctrl+C`), which `pkill -f` couldn't signal — required `kill -9 <pid>` by explicit PID. This live setup was fully validated working, then **disabled 2026-10-02** in favor of pcap-first:
```bash
systemctl disable --now argus-capture@enp0s8 argus-capture@enp0s9 argus-capture@enp0s10
```
Note: stopping a live `argus-capture@*` instance can take several minutes (observed 7+ min) before systemd gives up and SIGKILLs it — not a bug to chase, just budget time when disabling.

**Current usage — offline, run per pcap file:**
```bash
argus -r /var/log/pcap/enp0s8/<file>.pcap -w /opt/argus/extract/<scenario-or-window-name>/enp0s8.argus -P 0
ra -M nomar -r /opt/argus/extract/<scenario-or-window-name>/enp0s8.argus -c ',' -s stime,dur,proto,saddr,sport,daddr,dport,sttl,dttl,sbytes,dbytes,spkts,dpkts,state > enp0s8_flows.csv
```

**Validated 2026-10-02 (pcap-first):** `argus -r` against a real pcap (manual ICMP test traffic) + `ra -M nomar` produced genuine flow records — real `proto=icmp`/`arp`, real `saddr`/`daddr` IPs, correct `state` (`ECO` for ICMP echo, `CON` for ARP). Full pcap → Zeek + Argus pipeline confirmed working end-to-end on identical input.

### 7.4 Suricata — Live af-packet (unchanged, stray default `eth0` stanza removed)

Install (standard Debian repo):
```bash
apt install -y suricata
```

**Edited `/etc/suricata/suricata.yaml`** `af-packet:` section — added 3 entries for `enp0s8`/`enp0s9`/`enp0s10` (cluster-id 98/99/100, cluster-type `cluster_flow`, defrag yes) placed **after** the stock template's existing `- interface: eth0` placeholder entry, rather than replacing it.

**Symptom:** `systemctl status suricata` → `failed (Result: exit-code)`, exits in ~90ms. `suricata -T -c ... -v` (test mode) reported **success** — config syntax is valid YAML, test mode does not attempt to bind any AF_PACKET socket, so it cannot catch this class of error.

**Cause:** live run (`-D --af-packet`) binds a socket for every interface listed in `af-packet:`, in order — the stock `eth0` entry is still first in the list, and `eth0` does not exist on this VM (interfaces are `enp0s3/8/9/10`) → immediate fatal exit before reaching the valid `enp0s8/9/10` entries.

**Fix** — delete the entire stray `eth0` stanza (full indented block, not just the `interface:` line):
```bash
cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.bak
sed -i '622,699d' /etc/suricata/suricata.yaml    # exact line range for this install — verify with grep before deleting on any other VM
grep -n "interface:" /etc/suricata/suricata.yaml | head -6   # enp0s8 must now be the first af-packet entry
suricata -T -c /etc/suricata/suricata.yaml -v
systemctl restart suricata
systemctl status suricata --no-pager
```

**Validated 2026-10-02:** `active (running)`, af-packet socket confirmed bound (stats.log `afpacket.polls` incrementing). Traffic-flow validation (`eve.json`/`fast.log` populated on real attack-scenario traffic) — still pending, see §9. Suricata was **not** moved to pcap-offline mode — its role (real-time IDS alerting) is a separate concern from dataset feature extraction; `suricata -r <pcap>` remains available later as a supplementary/validation step if needed, without removing live mode.

### Tranalyzer2 — DEFERRED (blocked 2026-10-01, re-confirmed 2026-10-02, replaced in active stack by Argus §7.3)

Attempted build-from-source (not packaged for Debian). Corrected GitHub org first (`Tranalyzer`, capitalized, no digit — not `tranalyzer2`):
```bash
apt install -y build-essential autoconf automake libtool libpcap-dev flex bison libjansson-dev zlib1g-dev git
git clone https://github.com/Tranalyzer/tranalyzer2.git /opt/tranalyzer2
cd /opt/tranalyzer2
./autogen.sh && ./configure && make -j$(nproc) && make install
```
`./autogen.sh: No such file or directory` — repo only contains `ChangeLog`/`documentation.pdf`/`README.md`, no buildable source tree. All source channels investigated and exhausted as of 2026-10-01:

| Sumber | Status (2026-10-01) |
|---|---|
| `tranalyzer.com` | DNS resolve gagal total (confirmed dari sensor VM DAN dari browser host — genuine external outage, bukan isolasi lab) |
| `tranalyzer.org` | DNS resolve OK, tapi port 443 **connection refused** |
| GitHub `Tranalyzer/tranalyzer2` | Arsip saja (README+ChangeLog+PDF), no releases, no source tree |
| Debian/Ubuntu apt repo | Tidak dipaketkan |
| Docker Hub | Tidak ada official image |

**Re-check 2026-10-02** (retry atas permintaan user): `tranalyzer.com` masih DNS dead — `nslookup` dari host Windows timeout khusus domain ini, sementara domain lain (`github.com`, `tranalyzer.org`) resolve normal dari resolver yang sama persis → dikonfirmasi bukan masalah resolver/koneksi user, genuinely domain itu yang mati secara DNS. `tranalyzer.org` DNS tetap resolve ke IP sama (`5.226.150.131`), tapi port 443 sekarang **full connection timeout** (sebelumnya "connection refused" — makin tidak responsif, bukan membaik), dikonfirmasi via `Test-NetConnection` + `curl.exe -v` dari host user **dan** independen dari luar jaringan lab.

**Keputusan final (2026-10-02): Tranalyzer2 digantikan Argus (§7.3) di capture stack aktif.** Tranalyzer2 tidak lagi jadi blocker atau dependency — kalau upstream site-nya pulih di masa depan, bisa dievaluasi lagi sbg tambahan opsional (bukan requirement), tapi Argus+Zeek+Suricata sudah cukup utk reproduksi skema UNSW-NB15.

## 8. Known Issues Summary (New/Recurring)

| Issue | Cause | Fix | Status |
|---|---|---|---|
| Installer defaults to wrong primary NIC under ICH9 | NIC5+ gets non-sequential PCI slot (`enp0s16`), installer picks lowest-numbered "connected" interface regardless of actual internet reachability | Manually select the highest-numbered interface as primary | New — specific to any VM needing a 5th+ NIC |
| Install failed at 95% (desktop env mis-selected) | tasksel defaults (`1 7 11 12`) include Debian desktop + Xfce, not just SSH server + standard utilities | Full reinstall, explicitly select `11 12` only | New — worth double-checking tasksel selection explicitly on every remaining install |
| Stale SSH host key on reinstall | VM reinstall regenerates host key | `ssh-keygen -R <ip>` | Recurring — same as Phase 2 §5 |
| `git clone https://github.com/tranalyzer2/tranalyzer2` prompts for Username/Password | Wrong org name — real org is `Tranalyzer` (capitalized, no trailing digit) | Use `git clone https://github.com/Tranalyzer/tranalyzer2.git` | Corrected 2026-10-01 |
| Tranalyzer2 source unreachable from every channel | `tranalyzer.com` DNS dead, `tranalyzer.org` port 443 unreachable, GitHub archive-only, no apt package, no Docker image | **Replaced by Argus** (§7.3) | Blocked 2026-10-01, superseded 2026-10-02 |
| `zeek` binary: `command not found` | OBS `security:zeek` package installs to `/opt/zeek/bin/`, not on default `$PATH` | `export PATH=$PATH:/opt/zeek/bin` via `/etc/profile.d/zeek.sh` | Fixed 2026-10-02 |
| `zeekctl deploy` → `fatal error: problem with interface enp0s8,enp0s9,enp0s10 (pcap_activate: No such device exists)` | `node.cfg` standalone `interface=` field does not support comma-separated multi-interface | Abandoned zeekctl — see §7.2 history | Fixed/superseded 2026-10-02 |
| Raw `zeek -i enp0s8 -i enp0s9 -i enp0s10` → `ERROR: Only a single interface option (-i) is allowed` | Zeek 9.0.0 binary hard limit: one process binds exactly one capture interface | Superseded by pcap-first; each `zeek -r` run processes one pcap file | Fixed/superseded 2026-10-02 |
| `suricata.service` → `failed (Result: exit-code)`, exits in ~90ms; `suricata -T` reports config valid | Stock `af-packet:` list still had its default `- interface: eth0` placeholder as the *first* entry | Deleted the stray `eth0` stanza (`sed -i '622,699d'`, install-specific range) | Fixed 2026-10-02 |
| Argus `ArgusError: Srcid format error: hostuuid` — daemon won't start | Default `/etc/argus.conf` has `ARGUS_MONITOR_ID=\`hostuuid\`` — backtick shell command substitution calling an external `hostuuid` command not packaged on Debian | Replace with literal value: `ARGUS_MONITOR_ID=192.168.56.20` | Fixed 2026-10-02 |
| Argus `ArgusEstablishListen: bind() error` (live mode, after srcid fix) | Default TCP listen socket (port 561) for remote `ra` clients, unneeded in this lab | Added `-P 0` (moot now — live argus-capture@ disabled, see §7.3) | Fixed 2026-10-02, superseded by pcap-first |
| `argus-capture@*` systemd units all `status=1/FAILURE` instantly, `ExecStart=` lines concatenated in status output | In-place `nano` edit left 3 `ExecStart=` directives on one line, no newline between them | Rewrote unit file via heredoc; verified `grep -c "ExecStart=" file` = 1 | Fixed 2026-10-02 (unit itself later disabled/superseded) |
| Stray manual-test `argus`/`tcpdump` processes left in state `T` (stopped) blocking systemd instances | Manual foreground tests stopped with `Ctrl+Z` instead of `Ctrl+C`; `pkill -f` doesn't signal stopped processes | `kill -9 <pid>` by explicit PID | Recurring gotcha 2026-10-02 — **always use Ctrl+C for manual foreground tcpdump/argus/zeek tests in this project** |
| Argus `ra` output shows `proto=man`, placeholder `saddr`/`daddr` — looked like real flow data but wasn't | Default `ra` output includes Argus's own periodic MAR (status/heartbeat) records alongside real flow (FAR) records; on a quiet capture, MAR records are the only rows present → false-positive "capture is working" read | Always filter with `ra -M nomar ...` when verifying/exporting flow data | Found 2026-10-02 — affects all Argus validation going forward, not just this VM |
| `pcap-capture@*` systemd units: `.pcap` file stays 0 bytes despite confirmed real traffic on the interface | `tcpdump -w` without `-U` buffers writes (libpcap default buffer), only flushes on buffer-full/rotation/exit — low-traffic segment means long waits before any on-disk data appears | Added `-U` (packet-buffered mode, flush per packet) to `ExecStart` | Fixed 2026-10-02 |

## 9. Notes for Remaining Work

- Sensor is the only VM with direct hostonly SSH access (no jump host) — keep this in mind when scripting cross-VM automation later (different access pattern than client-1/2/attacker/srv-web/srv-file).
- `NatNetwork-temp` (NIC5) **detached 2026-10-06** (`VBoxManage modifyvm "sensor" --nic5 none`); the `natnet` sweep across all 8 VMs is now empty, and sensor's golden snapshot was re-taken offline the same day (UUID `2aade3df-a88e-46d6-96a6-c68b1de619d8`). Sensor keeps its 4 permanent NICs (chipset `ich9`).
- **Architecture as of 2026-10-02: pcap-first.** `pcap-capture@{enp0s8,enp0s9,enp0s10}` (tcpdump, live, §7.1) is the only live capture layer for dataset purposes; `zeek-capture@*` and `argus-capture@*` (live) are **disabled**, superseded by offline `zeek -r`/`argus -r` runs against saved pcap files (§7.2/§7.3). Suricata (`suricata.service`, live af-packet, §7.4) is unchanged — separate IDS-alerting concern.
- Full pipeline (tcpdump capture → `zeek -r` + `argus -r` offline extraction) validated end-to-end 2026-10-02 on manual ICMP test traffic. **Immediate next step (deferred by user to a later session):** generate deliberate scenario-like test traffic across all 3 intnet segments (server/client/attacker VMs), confirm pcap/conn.log/argus flow records all populate correctly per segment, and confirm Suricata `eve.json`/`fast.log` populate too.
- Blueprint propagation: the pcap-first decision and the Argus-replaces-Tranalyzer2 decision are recorded in `blueprint-v3-updated.md`/`-en.md` (deviation log #16, §5 point 10). The other two locked decisions from §7.3 (`service` sourced from Zeek; `ct_*` deferred to Phase 7/8) are recorded only in this document.
- Once confirmed working with real scenario traffic, update the `sensor` row in `blueprint-v3-updated.md`/`-en.md` §2 from "parsial"/"partial" to "✅" — also update the stale footnote there (still lists "Tranalyzer2 in progress"; should read "tcpdump/Zeek/Suricata/Argus, Tranalyzer2 superseded").
- Downstream Phase 7/8 pipeline needs a script that: (1) iterates rotated pcap files per interface per scenario window, (2) runs `zeek -r` + `argus -r` (with `-M nomar` on any `ra` read) on each, (3) tags output rows with `segment`/`sensor_nic`/`pcap_source`, (4) merges Argus+Zeek on the common flow key, (5) computes the deferred `ct_*`/`is_sm_ips_ports`/`is_ftp_login`/`ct_ftp_cmd` columns via the 100-record sliding window, (6) applies `label_by_scenario_window.py` for `attack_cat`/`label`.
- **Done 2026-10-03/05 (blueprint §5 point 9):** local NTP server on OPNsense, all client VMs including sensor synced to it — see `phase2-opnsense-setup.md` §11. Golden snapshot of sensor taken 2026-10-05 (blueprint §5 point 3).
