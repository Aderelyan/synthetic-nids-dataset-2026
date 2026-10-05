# Phase 3 (Part 3) — Linux Client Provisioning: client-1

Documentation of the client-1 VM build: Debian 13.7.0 (Trixie) netinst installation with proactive mitigation of known Debian minimal-install gaps, static IP configuration, and SSH access via OPNsense jump host (the permanent access pattern, validated for the first time end-to-end). Host: Windows, VirtualBox 7.2.12.

## 1. VM Resource & Storage Provisioning

Per `blueprint-v3-updated.md` §2 (locked spec): 2 vCPU, 3 GB RAM, 20 GB disk. VM shell + NIC1 (`intnet-client`) already registered in Phase 1.

```cmd
VBoxManage modifyvm "client-1" --memory 3072 --cpus 2 --firmware bios
VBoxManage createmedium disk --filename "C:\Users\Aderelyan\VirtualBox VMs\client-1\client-1.vdi" --size 20480 --variant Standard
VBoxManage storagectl "client-1" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "client-1" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\Aderelyan\VirtualBox VMs\client-1\client-1.vdi"
VBoxManage storagectl "client-1" --name "IDE" --add ide
VBoxManage storageattach "client-1" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\debian-13.7.0-amd64-netinst.iso"
VBoxManage modifyvm "client-1" --boot1 dvd --boot2 disk --boot3 none --boot4 none
VBoxManage modifyvm "client-1" --nic2 natnetwork --nat-network2 "NatNetwork-temp"
```

## 2. Debian 13.7.0 Installation — Proactive Mitigation Applied

Following the known-issue chain documented in `phase3-linux-servers-srv-file.md` §6, two mitigations were applied proactively this time:

| Step | Choice | Rationale |
|---|---|---|
| Locale | `en_US.UTF-8` | Consistency with log/tooling pipeline (Zeek, Suricata, syslog) |
| Timezone | Any (corrected post-install) | Console timezone picker not authoritative — always corrected via `timedatectl set-timezone Etc/UTC` post-install |
| Partitioning | Guided — all files in one partition | Same as srv-web/srv-file |
| Network mirror | **Accepted** (not skipped) | Avoids the `cdrom:`-only `/etc/apt/sources.list` issue hit on srv-file |
| Software selection (tasksel) | **SSH server task checked** + standard system utilities, no desktop | Avoids the manual `openssh-server` install needed on srv-file |
| GRUB | Install to `/dev/sda` | Standard |

## 3. Known Issue Recurrence: enp0s8 (NAT) Not Auto-Up

### Symptom
Post-reboot, `enp0s8` (temporary NAT NIC) had no IP — same underlying gap as srv-file (`phase3-linux-servers-srv-file.md` §3): Debian's true minimal install lacks `isc-dhcp-client`, and/or the NIC was not brought up automatically.

### Fix
```bash
ip link set enp0s8 up
# /etc/network/interfaces — added if missing:
#   auto enp0s8
#   iface enp0s8 inet dhcp
ifup enp0s8
```

Result: `enp0s8` obtained `10.0.99.9/24` from `NatNetwork-temp`.

## 4. Static IP, Hostname, Timezone, Hosts

`enp0s3` (intnet-client) — static, **no default route** (same dual-gateway pattern as all prior VMs):

```
# /etc/network/interfaces
auto enp0s3
iface enp0s3 inet static
    address 10.10.20.20
    netmask 255.255.255.0
    dns-nameservers 10.10.20.1
```

```bash
ifup enp0s3
hostnamectl set-hostname client1
timedatectl set-timezone Etc/UTC
```

`/etc/hosts`:
```
127.0.1.1    client1
10.10.20.1   opnsense.lab.local opnsense
```

## 5. SSH Access — Permanent Jump-Host Pattern (First End-to-End Validation)

Unlike srv-web/srv-file (which used a temporary `--port-forward-4` NAT rule for early access), client-1 was accessed directly via the **permanent jump-host pattern** already documented in `phase3-linux-servers-srv-web.md` §6 — this is the first time it was validated end-to-end:

```cmd
ssh -J root@192.168.56.10 labadmin@10.10.20.20
```

No additional firewall rule needed — OPT1 (intnet-client) already has the "pass any" rule from Phase 2 (`phase2-opnsense-setup.md` §6). Two password prompts are expected (OPNsense jump host, then the target VM).

**Implication for remaining VMs:** once a VM has a static IP reachable through OPNsense and sshd running, the NAT port-forward rule (`--port-forward-4`) is no longer needed for SSH access — it was only a bootstrapping workaround for srv-web/srv-file before the jump-host pattern was confirmed working.

## 6. Final Validation Results

| Check | Command | Result |
|---|---|---|
| Hostname | `hostnamectl` | `client1` |
| Timezone | `timedatectl \| grep "Time zone"` | `Etc/UTC (UTC, +0000)` |
| `/etc/hosts` | `cat /etc/hosts` | Contains `10.10.20.1 opnsense.lab.local opnsense` |
| Single default route | `ip route` | Only 1 default route, via `enp0s8` (NAT) — `enp0s3` carries no default route |
| Reachability to router | `ping -c 3 10.10.20.1` | 0% loss |
| SSH via jump host | `ssh -J root@192.168.56.10 labadmin@10.10.20.20` | Connected successfully |

## 7. Known Issues Summary (New/Recurring)

| Issue | Cause | Fix | Status |
|---|---|---|---|
| `enp0s8` (NAT) no IP post-install | Debian minimal install — same gap as srv-file | `ip link set enp0s8 up` + static/dhcp stanza in `/etc/network/interfaces` | Recurred as predicted in `blueprint-v3-updated.md` §1 item 8 |
| SSH via NAT port-forward | N/A this time | **Avoided entirely** — used jump-host pattern instead | Confirms the jump-host pattern is viable as the primary access method going forward, not just a documented fallback |

## 8. Notes for client-2

- Apply the same proactive mitigations (§2): accept network mirror, check SSH server task during install.
- Expect `enp0s8` to still require manual `ip link set up` even with the SSH-server task checked — the two issues are independent (`isc-dhcp-client` absence vs. `openssh-server` absence).
- Use the jump-host pattern (§5) as the default SSH access method; skip setting up a NAT port-forward rule unless jump-host access fails.
- Target: Debian 13.7.0, 2 vCPU, 2 GB RAM, 15 GB disk, IP `10.10.20.21`, hostname `client2`.
