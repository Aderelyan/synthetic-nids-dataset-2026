# Phase 3 (Part 4) — Linux Client Provisioning: client-2

Documentation of the client-2 VM build: Debian 13.7.0 (Trixie) netinst installation, static IP configuration, and a partial-mitigation case (SSH server task applied correctly, network mirror did not). Host: Windows, VirtualBox 7.2.12.

## 1. VM Resource & Storage Provisioning

Per `blueprint-v3-updated.md` §2: 2 vCPU, 2 GB RAM, 15 GB disk. VM shell + NIC1 (`intnet-client`) already registered in Phase 1.

```cmd
VBoxManage modifyvm "client-2" --memory 2048 --cpus 2 --firmware bios
VBoxManage createmedium disk --filename "C:\Users\Aderelyan\VirtualBox VMs\client-2\client-2.vdi" --size 15360 --variant Standard
VBoxManage storagectl "client-2" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "client-2" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\Aderelyan\VirtualBox VMs\client-2\client-2.vdi"
VBoxManage storagectl "client-2" --name "IDE" --add ide
VBoxManage storageattach "client-2" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\debian-13.7.0-amd64-netinst.iso"
VBoxManage modifyvm "client-2" --boot1 dvd --boot2 disk --boot3 none --boot4 none
VBoxManage modifyvm "client-2" --nic2 natnetwork --nat-network2 "NatNetwork-temp"
```

## 2. Installation — Mitigation Outcome Was Partial

Same install flow as client-1 (`phase3-linux-servers-client-1.md` §2), with the SSH-server-task + accept-mirror mitigation intended. Actual outcome:

| Mitigation | Intended | Actual |
|---|---|---|
| SSH server task checked | ✅ | **Applied correctly** — `sshd` was `active (running)` immediately after first login, no manual install needed |
| Network mirror accepted | ✅ | **Did not apply** — `/etc/apt/sources.list` still had `cdrom:` as the only source post-install (same symptom as srv-file's original issue) |

**Takeaway:** the two mitigations are independent installer steps and can partially fail independently — checking the SSH task does not guarantee the mirror step was also registered. Both should be verified post-install, not assumed together.

## 3. Known Issue Recurrence: apt Sources Stuck on cdrom:

### Symptom
```
Err:2 cdrom://[Debian GNU/Linux 13.7.0 _Trixie_ - Official amd64 NETINST...] trixie Release
E: The repository '...' does not have a Release file.
N: Updating from such a repository can't be done securely, and is therefore disabled by default.
```

### Fix (identical to `phase3-linux-servers-client-1.md`/`srv-file.md`)
```bash
sed -i 's/^deb cdrom/#deb cdrom/' /etc/apt/sources.list
echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
echo "deb http://security.debian.org/debian-security trixie-security main" >> /etc/apt/sources.list
apt update
```

## 4. Static IP, Hostname, Timezone, Hosts

`enp0s3` (intnet-client) — static, no default route:

```
auto enp0s3
iface enp0s3 inet static
    address 10.10.20.21
    netmask 255.255.255.0
    dns-nameservers 10.10.20.1
```

```bash
ifup enp0s3
hostnamectl set-hostname client2
timedatectl set-timezone Etc/UTC
```

`/etc/hosts`:
```
127.0.1.1    client2
10.10.20.1   opnsense.lab.local opnsense
```

## 5. SSH Access — Jump-Host Pattern (Confirmed Again)

```cmd
ssh -J root@192.168.56.10 labadmin@10.10.20.21
```

No NAT port-forward rule created for client-2 — the jump-host pattern is now the confirmed default access method across client-1 and client-2 (second consecutive successful validation).

## 6. Final Validation Results

| Check | Command | Result |
|---|---|---|
| Single default route | `ip route` | Only 1 default route, via `enp0s8` (NAT) |
| Reachability to router | `ping -c 3 10.10.20.1` | 0% loss |
| Hostname | `hostnamectl` | `client2` |
| Timezone | `timedatectl \| grep "Time zone"` | `Etc/UTC (UTC, +0000)` |
| `/etc/hosts` | `cat /etc/hosts` | Contains `10.10.20.1 opnsense.lab.local opnsense` |
| sshd | `systemctl status ssh` | active (running), enabled |
| SSH via jump host | `ssh -J root@192.168.56.10 labadmin@10.10.20.21` | Connected successfully |

## 7. Known Issues Summary (New/Recurring)

| Issue | Cause | Fix | Status |
|---|---|---|---|
| apt sources stuck on `cdrom:` | Network mirror step not registered despite intending to accept it during install | Comment out `cdrom:` line, append `deb.debian.org` + `security.debian.org`, `apt update` | Recurred — same fix as srv-file; **verify apt sources post-install on every remaining VM regardless of what was clicked during install** |
| — | — | — | `enp0s8` NAT auto-up issue (client-1 §3) **did not recur** this time — inconsistent across installs, still worth checking `ip a` post-boot rather than assuming |

## 8. Notes for Remaining VMs (attacker, sensor, win-client)

- **Do not assume installer checkbox/mirror choices persisted** — always verify `/etc/apt/sources.list` and `systemctl status ssh` immediately after first login, independently of what was selected during install.
- Jump-host SSH access (§5) is now validated twice in a row — continue using it as the default; skip NAT port-forward setup unless jump-host access fails.
- With client-1 and client-2 done, Phase 3 Linux servers+clients is complete except for `attacker` (Kali). Sensor and win-client remain in later phases (5 and 4).
