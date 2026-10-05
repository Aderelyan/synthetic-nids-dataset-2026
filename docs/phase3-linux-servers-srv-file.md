# Phase 3 (Part 2) — Linux Server Provisioning: srv-file

Dokumentasi pembangunan VM `srv-file`: instalasi Debian 13.7.0 (Trixie) netinst, gap jaringan di minimal-install, konflik NAT Network port-forward, dan rantai root-cause SSH-inaccessibility. Host: Windows, VirtualBox 7.2.12.

## 1. VM Provisioning

VM dan registrasi NIC mengikuti pola yang sama seperti `srv-web` (lihat `phase3-linux-servers-srv-web.md` §1) — 2 vCPU, 2 GB RAM, 20 GB disk, NIC NAT sementara (`nic2` di `NatNetwork-temp`) untuk instalasi, NIC utama di `intnet-server`. OS: **Debian 13.7.0 (Trixie) netinst**, bukan Ubuntu — dipilih untuk srv-file guna mendiversifikasi OS fingerprint dataset lintas server lab.

Command lengkap (eksplisit, bukan cuma rujuk ke srv-web — spesifikasi disk/CPU/RAM disalin dari §1 srv-web agar file ini bisa berdiri sendiri):

```cmd
VBoxManage createvm --name "srv-file" --ostype "Debian_64" --register
VBoxManage modifyvm "srv-file" --memory 2048 --cpus 2 --firmware bios
VBoxManage modifyvm "srv-file" --nic1 intnet --intnet1 "intnet-server"
VBoxManage modifyvm "srv-file" --nic2 natnetwork --nat-network2 "NatNetwork-temp"
VBoxManage createmedium disk --filename "C:\Users\<user>\VirtualBox VMs\srv-file\srv-file.vdi" --size 20480 --variant Standard
VBoxManage storagectl "srv-file" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "srv-file" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\<user>\VirtualBox VMs\srv-file\srv-file.vdi"
VBoxManage storagectl "srv-file" --name "IDE" --add ide
VBoxManage storageattach "srv-file" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\debian-13.7.0-amd64-netinst.iso"
VBoxManage modifyvm "srv-file" --boot1 dvd --boot2 disk --boot3 none --boot4 none
VBoxManage startvm "srv-file" --type gui
```

NIC NAT sementara (`nic2`) wajib dilepas sebelum Phase 6 (air-gap validation), sama seperti pola srv-web.

## 2. Debian 13.7.0 Installation

| Step | Choice |
|---|---|
| Install type | Graphical install / Install (text) |
| Locale, keyboard | Defaults |
| Primary network interface | `enp0s3` auto-selected first |
| Network configuration | **DHCP failed** on `enp0s3` (expected — `intnet-server` has no DHCP server) → selected **"Do not configure the network at this time"** to skip networking entirely during install |
| Hostname/domain step | Skipped (no network config chosen) |
| Root password, user account | Set (`root`, `labadmin`) |
| Time zone | Selected by city; corrected to UTC post-install (§4) |
| Partitioning | Guided — entire disk, all files in one partition |
| Scan extra installation media | No |
| Network mirror | **Declined** ("Continue without a network mirror") — this has a downstream consequence, see §6 |
| Popularity contest | No |
| Software selection | Minimal / standard system utilities only, no desktop, no SSH server task |
| GRUB | Install to the VDI disk (`/dev/sda`) |

Installer auto-ejects the ISO and reboots on its own, same behavior as the Ubuntu/OPNsense installers.

## 3. Known Issue: `dhclient: command not found`

### Symptom
After first boot, `ip a` showed `enp0s8` (the temporary NAT NIC) down/unconfigured, and running `dhclient` for a manual DHCP attempt failed:
```
-bash: dhclient: command not found
```

### Cause
Debian 13's true minimal install (no software-selection tasks checked) does not include `isc-dhcp-client`, unlike Ubuntu Server's live-server installer, which DHCPs all NICs by default regardless of profile.

### Fix
```bash
ip link set enp0s8 up
```
Then edit `/etc/network/interfaces` (Debian uses ifupdown, not netplan) to add:
```
auto enp0s8
iface enp0s8 inet dhcp
```
```bash
ifup enp0s8
```

## 4. Static IP, Hostname, Timezone, Hosts

`enp0s3` (intnet-server) set static, **no default route** (same dual-gateway-conflict pattern as srv-web — see `phase3-linux-servers-srv-web.md` §4) — `enp0s8`'s DHCP-provided route remains the sole default:

```bash
# /etc/network/interfaces — enp0s3 stanza
auto enp0s3
iface enp0s3 inet static
    address 10.10.10.11
    netmask 255.255.255.0
    dns-nameservers 10.10.10.1
```

```bash
hostnamectl set-hostname files01
timedatectl set-timezone Etc/UTC
```

`/etc/hosts`:
```
127.0.1.1    files01
10.10.10.1   opnsense.lab.local opnsense
```

## 5. Known Issue: NAT Port-Forward Rule Conflict

### Symptom
```
VBoxManage.exe: error: A NAT rule of this name already exists
VBoxManage.exe: error: Details: code E_INVALIDARG (0x80070057), component NATNetworkWrap, interface INATNetwork, callee IUnknown
```
Raised when adding `ssh-file` to `NatNetwork-temp` — a rule with that name already existed from an earlier attempt made with an unconfirmed guest IP.

### Fix — Delete Before Re-adding
```cmd
VBoxManage natnetwork modify --netname NatNetwork-temp --port-forward-4 delete ssh-file
VBoxManage natnetwork modify --netname NatNetwork-temp --port-forward-4 "ssh-file:tcp:[]:2223:[10.0.99.8]:22"
VBoxManage natnetwork stop --netname NatNetwork-temp
VBoxManage natnetwork start --netname NatNetwork-temp
```
`VBoxManage natnetwork modify --port-forward-4` has no in-place overwrite — an existing rule name must be deleted first. Stop/start of the NAT network was applied to force the rule to take effect immediately, though this may not be strictly required.

## 6. Known Issue: SSH Inaccessible After Port-Forward Fix

### Symptom
Even with the correct port-forward rule and guest IP confirmed (`10.0.99.8`), SSH failed differently across attempts:
```
kex_exchange_identification: read: Connection reset
banner exchange: Connection to 127.0.0.1 port 2223: Connection aborted
```
This is distinct from a refused/timed-out connection — the TCP handshake succeeded, but the far end reset the connection during the SSH banner exchange, meaning nothing was listening or answering as SSH on port 22 in the guest.

### Root Cause Chain

| # | Finding | Detail |
|---|---|---|
| 1 | `openssh-server` not installed | Minimal software selection during install (§2) did not include the SSH server task |
| 2 | `apt install openssh-server` failed | `apt` package sources still pointed at the install-time CD-ROM (`deb cdrom:...` in `/etc/apt/sources.list`) — a direct consequence of declining a network mirror during install (§2). Prompted repeatedly for the installer disc. |
| 3 | `sudo: command not found` | True minimal install also excludes `sudo`; `labadmin` is not a sudoer by default — all fixes had to be run logged in directly as `root` (`su -`) |

### Fix
```bash
# as root
sed -i 's/^deb cdrom/#deb cdrom/' /etc/apt/sources.list
echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list
echo "deb http://security.debian.org/debian-security trixie-security main" >> /etc/apt/sources.list
apt update
apt install -y openssh-server
systemctl enable --now ssh
```

Optional convenience for the rest of the lab (grant `labadmin` sudo so root login isn't needed for every future command):
```bash
apt install -y sudo
usermod -aG sudo labadmin
```

### Validation
```bash
ss -tlnp | grep :22
systemctl status ssh
```
```cmd
ssh -p 2223 labadmin@127.0.0.1
```
Confirmed: `sshd` log showed `Accepted password for ... at 09:23:00 UTC`.

## 7. Final Validation Results

| Check | Command | Result |
|---|---|---|
| Static IP | `ip a show enp0s3` | `10.10.10.11/24` |
| Single default route | `ip route` | `default via 10.0.99.1 dev enp0s8` only — no competing route via `enp0s3` |
| Reachability to router | `ping -c 3 10.10.10.1` | 0% loss |
| Hostname | `hostnamectl` | `files01` |
| Timezone | `timedatectl \| grep "Time zone"` | `Etc/UTC (UTC, +0000)` |
| sshd | `systemctl status ssh` | active (running), enabled |
| NAT IP | `ip a show enp0s8` | `10.0.99.8/24` (dynamic, matches port-forward rule) |

## 8. Known Issues Summary

| Issue | Cause | Fix |
|---|---|---|
| `dhclient: command not found` | Debian minimal install excludes `isc-dhcp-client` | `ip link set <nic> up` + static/manual `ifupdown` stanza in `/etc/network/interfaces`, or install `isc-dhcp-client` once any NIC has connectivity |
| `VBoxManage natnetwork modify --port-forward-4` — "rule already exists" | No in-place overwrite; a stale rule (wrong/unconfirmed guest IP) was added earlier | `--port-forward-4 delete <rule-name>` before re-adding |
| SSH "Connection reset"/"Connection aborted" during banner exchange | `openssh-server` not installed — not a network/port-forward problem despite matching symptoms | Fix `apt` sources (see below), install `openssh-server`, enable service |
| `apt install` prompts for installer disc / can't reach packages | Declining the network mirror during install leaves only a `cdrom:` source in `/etc/apt/sources.list` | Comment out the `cdrom:` line, append `deb.debian.org` + `security.debian.org` mirror lines, `apt update` |
| `sudo: command not found` | Minimal install excludes `sudo`; default user not a sudoer | Run fixes as `root` (`su -`), or `apt install sudo && usermod -aG sudo <user>` |

## 9. Notes for Remaining Phase 3 VMs

- If client-1/client-2 also use Debian minimal netinst, expect the same three-part chain (§6) by default: no `openssh-server`, `cdrom:`-only apt sources (if network mirror is declined), no `sudo`. Installing the SSH server task and accepting the network mirror during install would avoid all three proactively.
- The NAT port-forward "rule already exists" error (§5) will recur for any VM where a port-forward rule is added, corrected, and re-added under the same name — always `delete` before re-adding rather than attempting to modify in place.
- `NatNetwork-temp` NICs and all associated port-forward rules must still be removed from every VM before Phase 6 (air-gap validation), per the note carried over from `phase3-linux-servers-srv-web.md` §9.
