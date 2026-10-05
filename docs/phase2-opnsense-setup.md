# Phase 2 — OPNsense Router Installation & Configuration

Documentation of the OPNsense router build: OS install, interface assignment, WebGUI wizard, internal-routing firewall rules, SSH, and Unbound DNS host overrides. Host: Windows, VirtualBox 7.2.12, OPNsense 26.7.

## 1. VM Resource & Storage Provisioning

```cmd
VBoxManage modifyvm "router-opnsense" --memory 3072 --cpus 2 --firmware bios
VBoxManage createmedium disk --filename "C:\Users\<user>\VirtualBox VMs\router-opnsense\router-opnsense.vdi" --size 20480 --variant Standard
VBoxManage storagectl "router-opnsense" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "router-opnsense" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\<user>\VirtualBox VMs\router-opnsense\router-opnsense.vdi"
VBoxManage storagectl "router-opnsense" --name "IDE" --add ide
VBoxManage storageattach "router-opnsense" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\OPNsense-XX.X-dvd-amd64.iso"
VBoxManage modifyvm "router-opnsense" --boot1 dvd --boot2 disk --boot3 none --boot4 none
```

**Important — RAM requirement:** OPNsense's official minimum RAM for virtual installs is **3 GB**, regardless of filesystem (UFS or ZFS). The initial blueprint value of 2048 MB triggers an installer warning and should be raised to 3072 MB before installing. This adds +1 GB to both phase totals (Phase Linux → 20 GB, Phase Windows → 19 GB) — still well under the 38 GB host limit.

## 2. Installation

Boot the VM in GUI mode (installer is interactive console, not compatible with headless without VRDE):

```cmd
VBoxManage startvm "router-opnsense" --type gui
```

| Step | Action |
|---|---|
| Live login | Username: `installer`, Password: `opnsense` (official default — not blank) |
| Install type | **Install (UFS)** — not ZFS, to keep overhead low |
| Disk selection | Select `ada0` (20 GB, the `.vdi`) — **not** `cd0` (1 GB, the ISO itself, auto-detected as a block device) |
| Partitioning | Entire Disk → Auto (UFS) |
| Root password | Set and remember — used for console, WebGUI, and SSH |
| Finish | Reboot |

The installer auto-ejects the ISO and powers off on its own after installation — a manual `storageattach ... --medium none` or `acpipowerbutton` at that point may return "already detached" / "not running" errors; this is expected, not a failure.

## 3. Interface Assignment (Console Menu → Option 1)

NIC-to-interface mapping (Intel PRO/1000 `82540EM` → FreeBSD `em` driver):

| VBox NIC | Attachment | Interface Name |
|---|---|---|
| NIC1 | hostonly | em0 |
| NIC2 | intnet-server | em1 |
| NIC3 | intnet-client | em2 |
| NIC4 | intnet-attacker | em3 |

**Role assignment (final):**

| Role | Interface | Segment | Rationale |
|---|---|---|---|
| LAN | em0 | hostonly (192.168.56.0/24) | Gets the automatic anti-lockout rule — used for management access from the host |
| WAN | em1 | intnet-server (10.10.10.0/24) | Not a real internet uplink — satisfies OPNsense's mandatory-WAN requirement; gateways the server segment |
| OPT1 | em2 | intnet-client (10.10.20.0/24) | Gateways the client segment |
| OPT2 | em3 | intnet-attacker (10.10.30.0/24) | Gateways the attacker segment |

Wizard prompts and answers:
```
Configure LAGGs now? [y/N]: n
Configure VLANs now? [y/N]: n
WAN interface name: em1
LAN interface name: em0
Optional interface 1 name: em2
Optional interface 2 name: em3
Optional interface 3 name: [blank — done]
Proceed? [y/N]: y
```

## 4. Static IP Assignment (Console Menu → Option 2)

| Interface | IPv4 | Subnet | Gateway | DHCP Server |
|---|---|---|---|---|
| LAN (em0) | 192.168.56.10 | /24 | none | Disabled |
| WAN (em1) | 10.10.10.1 | /24 | none | N/A |
| OPT1 (em2) | 10.10.20.1 | /24 | none | Disabled |
| OPT2 (em3) | 10.10.30.1 | /24 | none | Disabled |

Per-interface wizard answers: DHCP → `n`, IPv4 address → per table, subnet bits → `24`, upstream gateway → blank/Enter, IPv6 (DHCP6 and static) → `n`/blank, DHCP server → `n`. For LAN specifically: webConfigurator protocol change to HTTP → `n`, generate new self-signed cert → `n`, **Restore web GUI access defaults? → `y`** (re-applies the anti-lockout rule for the new LAN subnet after reassigning interfaces/IP).

## 5. Known Issues & Fixes

| Issue | Cause | Fix |
|---|---|---|
| Installer warns RAM below requirement | VM configured with 2 GB, official minimum is 3 GB | `modifyvm --memory 3072` before installing (see §1) |
| Live installer "login incorrect" with blank password | Default password is `opnsense`, not blank | Username `installer`, password `opnsense` |
| Console prompt says "Enter the new **LAN** IPv4 upstream gateway address" while configuring WAN/OPT1/OPT2 | Cosmetic bug in OPNsense's console script — the word "LAN" is hardcoded in the gateway prompt regardless of which interface is being configured | Ignore the wording; answer based on which interface you are actually configuring (all interfaces here get blank/none) |
| WebGUI setup wizard won't let you click Next on the WAN step — Gateway field outlined red | Wizard form validation requires a non-empty Gateway for a Static WAN, unlike the console | Enter a placeholder IP inside the WAN subnet that no host uses (e.g. `10.10.10.254`). **Must then disable Gateway Monitoring** (System → Gateways → Configuration → edit → check "Disable Gateway Monitoring") — otherwise dpinger sends a constant 1-second ICMP probe to a nonexistent host, polluting the traffic capture used for the dataset |
| SSH: "REMOTE HOST IDENTIFICATION HAS CHANGED" / "Host key verification failed" | `known_hosts` on the Windows host has a stale fingerprint for `192.168.56.10` from a previous VM (e.g. old `kali`/`victim` project) | `ssh-keygen -R 192.168.56.10`, then reconnect and accept the new fingerprint |
| Typing a command (e.g. `drill`) at the `Enter an option:` console menu does nothing but redraw the menu | The numbered console menu is not a shell — unrecognized input is silently ignored | Select **option 8) Shell** first to get a real FreeBSD shell prompt (`root@OPNsense:~ #`), run commands there, `exit` to return to the console menu |
| `list intnets` (VirtualBox side) shows a generic `intnet` network with no suffix | Leftover VMs from another project (`kali`, `victim`) still use the default `intnet` NIC name | Not part of this topology — ignore |

## 6. Firewall Rules — Internal Routing

By default, only LAN gets an automatic "allow any" rule from the wizard. WAN/OPT1/OPT2 default-deny everything, including inter-segment routing traffic that this lab actually needs (attacker → server/client, client → server, etc.). One "pass any" rule was added per non-LAN interface:

| Interface | Action | Protocol | Source | Destination | Enabled | Log |
|---|---|---|---|---|---|---|
| WAN | Pass | any | WAN network | any | ✅ | ❌ |
| OPT1 | Pass | any | any | any | ✅ | ❌ |
| OPT2 | Pass | any | any | any | ✅ | ❌ |

**Notes:**
- `Enabled` is **not checked by default** in this OPNsense version's rule-edit form — easy to miss; a rule can look fully configured yet remain inactive if this checkbox is skipped.
- Logging is intentionally left off — traffic capture for the dataset comes from the sensor (promiscuous tcpdump/Zeek on the internal networks), not from firewall logs. Enabling logging on a "pass any" rule during a DoS/flood scenario (S-11) would generate excessive log volume for no benefit to the pipeline.
- OPT1/OPT2 use `Source: any` rather than `<interface> network` — functionally equivalent here since filtering is already scoped by interface + direction (`In`), and `any` avoids dropping spoofed-source packets that some attack scenarios (e.g. DoS) may intentionally generate.

## 7. SSH Access

```
System → Settings → Administration → Secure Shell
  Enable Secure Shell: checked
  Permit root user login: checked
  Permit password login: checked
  Listen Port: 22 (default)
```

Test from host:
```cmd
ssh root@192.168.56.10
```

SSH is reachable from LAN (192.168.56.0/24) via the anti-lockout rule; it remains blocked on WAN/OPT1/OPT2 by design (management access should not be exposed to client/attacker segments).

## 8. Unbound DNS — Host Overrides

`Services → Unbound DNS → Overrides → Host Overrides`, one entry per lab host:

| Host | Domain | IP Address | Description |
|---|---|---|---|
| web01 | lab.local | 10.10.10.10 | srv-web (nginx, DVWA/Juice Shop) |
| files01 | lab.local | 10.10.10.11 | srv-file (SSH, SMB, Samba, Syslog) |
| client1 | lab.local | 10.10.20.20 | Linux client 1 |
| client2 | lab.local | 10.10.20.21 | Linux client 2 |
| win-client | lab.local | 10.10.20.50 | Windows client (Phase Windows) |
| attacker | lab.local | 10.10.30.10 | Kali attacker VM |
| router | lab.local | 192.168.56.10 | OPNsense mgmt |

All entries created with default TTL, PTR record enabled (useful for reverse lookups during pcap/Zeek log analysis later), no aliases.

Entries can be registered before their VMs exist — Unbound simply stores the static mapping regardless of host liveness.

## 9. Validation

Run from a real shell (console option 8, or via SSH), not the numbered menu:

```bash
drill @127.0.0.1 web01.lab.local
drill @127.0.0.1 files01.lab.local
drill @127.0.0.1 google.com
```

**Actual results (confirmed):**

| Query | rcode | Answer |
|---|---|---|
| web01.lab.local | NOERROR | 10.10.10.10 |
| files01.lab.local | NOERROR | 10.10.10.11 |
| google.com | SERVFAIL | — (expected: no upstream DNS, confirms isolation) |

Additional checks:

```cmd
ping 192.168.56.10
```
Expected: reply from OPNsense LAN interface.

```
https://192.168.56.10
```
Expected: WebGUI login page (self-signed cert warning is normal — accept the exception).

```
System → Gateways → Configuration
```
Expected: `WAN_GW`, Disable Gateway Monitoring = checked, status not actively probing.

## 11. NTP Server Setup (added 2026-10-03)

Locked decision `blueprint-v3-updated.md` §5 point 9 required a local NTP source for the lab, since there is no internet access to reach `pool.ntp.org`. `Services → NTP → General Settings`:

| Setting | Value |
|---|---|
| Interfaces | LAN + WAN + OPT1 + OPT2 (all four — "WAN" here is just a label for the intnet-server segment, not a real internet uplink; every internal segment needs to be able to query NTP) |
| Advanced / raw config | `server 127.127.1.0` + `fudge 127.127.1.0 stratum 10` — forces OPNsense to serve its own system clock as a stratum-10 fallback source, since the upstream `pool.ntp.org` entries can never be reached |

**Validation** (`ntpq -p` from console shell, option 8, or SSH):
```
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
 0.opnsense.pool .POOL.          16 p    -   64    0    0.000   +0.000   0.001
 ...(3 more pool entries, all unreachable — expected, no internet)...
*LOCAL(0)        .LOCL.          10 l  125  128  377    0.000   +0.000   0.001
```
`*LOCAL(0)` with `reach=377` (octal, full) confirms OPNsense selected its own clock as the active sync source.

**Client-side (each VM, systemd-timesyncd):**
```bash
sudo tee /etc/systemd/timesyncd.conf > /dev/null <<'EOF'
[Time]
NTP=<gateway-ip>
FallbackNTP=
EOF
sudo systemctl restart systemd-timesyncd
timedatectl
```

| VM | Gateway used |
|---|---|
| srv-web | 10.10.10.1 |
| srv-file | 10.10.10.1 |
| client-1 | 10.10.20.1 |
| client-2 | 10.10.20.1 |
| attacker | 10.10.30.1 |
| sensor | 192.168.56.10 |

All 6 confirmed `System clock synchronized: yes` / `NTP service: active` as of 2026-10-03. `win-client` not yet applicable (Phase 4 not built yet).

**Known quirk:** on attacker (Kali), `sudo` printed `unable to resolve host attacker: Temporary failure in name resolution` before each command — harmless (command still executes, just sudo trying to resolve the hostname first). Caused by `/etc/hosts` missing a `127.0.1.1 attacker` entry (unlike srv-web/srv-file, which had this added during provisioning — see `phase3-linux-servers-attacker.md`). Fixed with `echo "127.0.1.1 attacker" | sudo tee -a /etc/hosts`.

## 12. Notes for the Next Phase

- Full inter-segment routing (ping between srv-web ↔ client-1 ↔ attacker, etc.) cannot be validated yet — those VMs have no OS/IP configured. This is deferred to **Phase 6** (network isolation & baseline traffic validation) once all VMs are live.
- `NatNetwork-temp` (from Phase 1) has not been attached to `router-opnsense` — the router never needs internet access, so no detach step is required for this VM specifically.
- The WAN placeholder gateway (`10.10.10.254`) exists only to satisfy the WebGUI wizard's form validation; it does not correspond to a real device and gateway monitoring is disabled to prevent probe traffic.
- NTP server (§11) is now live — golden snapshots (blueprint-v3 §5 point 3) can proceed now that VM clocks are consistent.
