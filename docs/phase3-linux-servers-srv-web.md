# Phase 3 (Part 1) — Linux Server Provisioning: srv-web

Documentation of the srv-web VM build: Ubuntu Server 24.04 installation, a critical VT-x host issue and its fix, static IP configuration, dual-gateway routing conflict, and DVWA deployment as the target web app for SQLi scenarios (S-04). Host: Windows, VirtualBox 7.2.12.

## 1. VM Resource & Storage Provisioning

Per blueprint spec: 2 vCPU, 2 GB RAM, 20 GB disk.

```cmd
VBoxManage modifyvm "srv-web" --memory 2048 --cpus 2 --firmware bios
VBoxManage createmedium disk --filename "C:\Users\<user>\VirtualBox VMs\srv-web\srv-web.vdi" --size 20480 --variant Standard
VBoxManage storagectl "srv-web" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "srv-web" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "C:\Users\<user>\VirtualBox VMs\srv-web\srv-web.vdi"
VBoxManage storagectl "srv-web" --name "IDE" --add ide
VBoxManage storageattach "srv-web" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "C:\ISO\ubuntu-24.04.x-live-server-amd64.iso"
VBoxManage modifyvm "srv-web" --boot1 dvd --boot2 disk --boot3 none --boot4 none
```

**Temporary NAT NIC for installation** (live-server installer needs internet to fetch/update packages; the VM's only planned NIC is `intnet-server`, which has no DHCP/internet):

```cmd
VBoxManage modifyvm "srv-web" --nic2 natnetwork --nat-network2 "NatNetwork-temp"
```

Must be detached before Phase 6 (air-gap validation) — see topology docs in Phase 1.

## 2. Critical Issue: VT-x Not Available → VM Hangs/Soft-Locks

### Symptom

During installation, the console repeatedly froze with:
```
watchdog: BUG: soft lockup - CPU#1 stuck for 56s! [unattended-upgr:12803]
```
Power-cycling the VM did not help — subsequent boots also hung indefinitely (multiple hours) at early boot stages (e.g. right after `Loading essential drivers...`), with no further progress.

### Root Cause

`VBox.log` for the VM showed:
```
HMR3Init: Attempting fall back to NEM: VT-x is not available
```

VirtualBox could not access hardware virtualization (VT-x) and fell back to NEM (software emulation), which is slow and unstable enough to fully hang under real workloads like package installation.

### Diagnosis Path

1. Suspected Windows 11 **Core Isolation / Memory Integrity** first (a known conflict with VT-x) — disabled it, but the hang persisted.
2. Checked `VBox.log` directly:
   ```cmd
   type "C:\Users\<user>\VirtualBox VMs\srv-web\Logs\VBox.log" | findstr /I "error warning HAXM AMD-V VT-x"
   ```
   This surfaced the real cause: VT-x unavailable, not a Core Isolation issue per se (though Core Isolation being enabled was a contributing factor before it was turned off).

### Fix — Disable Hyper-V Platform Entirely

Core Isolation being off was not sufficient; the Windows Hyper-V platform itself was still claiming the hypervisor, which is what VT-x fallback was detecting via "A hypervisor has been detected" behavior.

```cmd
dism.exe /Online /Disable-Feature:Microsoft-Hyper-V-All /NoRestart
dism.exe /Online /Disable-Feature:HypervisorPlatform /NoRestart
dism.exe /Online /Disable-Feature:VirtualMachinePlatform /NoRestart
dism.exe /Online /Disable-Feature:Containers-DisposableClientVM /NoRestart
shutdown /r /t 0
```

**Validation after reboot:**
```cmd
systeminfo | findstr /I "Hyper-V Virtualization"
```
Expected: the line "A hypervisor has been detected. Features required for Hyper-V will not be displayed." should no longer appear.

After this fix, the VM could be reset to its normal spec (`--cpus 2 --memory 2048`) and the installation completed without further lockups.

**Note for future VMs:** this is a one-time host-level fix — it does not need to be repeated for srv-file, client-1/2, win-client, attacker, or sensor.

## 3. Ubuntu Server 24.04 Installation

```cmd
VBoxManage startvm "srv-web" --type gui
```

| Step | Choice |
|---|---|
| Installation type | Ubuntu Server (not "minimized") |
| Network connections | Leave both NICs on default DHCP during install |
| Storage | Use an entire disk → the 20 GB disk → Done → Continue |
| Profile | Server name: `web01`, username: `labadmin`, set a password |
| Ubuntu Pro | Skip for now |
| SSH Setup | **Install OpenSSH server — checked** (needed for remote access; no separate install step required later) |
| Featured Server Snaps | None selected — avoid bloat, nginx/DVWA installed manually |

Installer auto-ejects the ISO and powers off on its own at the end, same behavior as OPNsense's installer.

## 4. Dual-Gateway Routing Conflict

### Symptom

After setting a static IP with a default route on `enp0s3` (intnet-server), `apt install` failed:
```
E: Failed to fetch ... Could not connect to id.archive.ubuntu.com:80 ... connection timed out
```
despite `enp0s3` pinging `10.10.10.1` (OPNsense) successfully.

### Cause

Two NICs, two default routes: `enp0s3` (via OPNsense, `10.10.10.1` — no internet) and `enp0s8` (via NAT DHCP — has internet). The routing table picked the non-internet route for outbound traffic.

### Fix

Static netplan config for `enp0s3` **without a default route** — only an address and a nameserver pointing at OPNsense. `enp0s8` keeps DHCP (its own default route, unopposed):

```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    enp0s3:
      addresses:
        - 10.10.10.10/24
      nameservers:
        addresses:
          - 10.10.10.1
    enp0s8:
      dhcp4: true
```

```bash
sudo netplan apply
```

**Validation:**
```bash
ip route          # exactly one "default via ..." line, through enp0s8
ping -c 3 10.10.10.1   # still succeeds (same-subnet, no default route needed)
```

This dual-NIC/dual-route conflict is expected to recur for every server/client VM provisioned with a temporary NAT NIC — apply the same "no default route on the intnet NIC" pattern each time.

## 5. Base Packages & Hostname

```bash
sudo apt update
sudo apt install -y nginx curl vim net-tools
sudo hostnamectl set-hostname web01
```

`/etc/hosts` — added a convenience entry for OPNsense:
```
127.0.1.1    web01
10.10.10.1   opnsense.lab.local opnsense
```

## 6. SSH Access From Host — NAT Network Limitation

### Issue

VirtualBox's NAT Network (`NatNetwork-temp`) blocks **all inbound host→guest traffic** by design — a guest can reach the internet and the host can be reached by the guest, but the host cannot reach the guest, unless an explicit port-forwarding rule exists. This applies to SSH and to any other service (see §7).

### Fix — Port Forwarding on the NAT Network

```cmd
VBoxManage natnetwork modify --netname NatNetwork-temp --port-forward-4 "ssh-web:tcp:[]:2222:[10.0.99.7]:22"
```

Rule format: `name:protocol:[host-ip, blank = all]:host-port:[guest-ip]:guest-port`

```cmd
ssh -p 2222 labadmin@127.0.0.1
```

Guest IP on the NAT interface must be checked per-VM (`ip a show enp0s8` inside the guest) — DHCP lease order is not guaranteed to match across VMs.

**Permanent access pattern** (once the NAT NIC is detached before Phase 6): SSH to any server/client VM goes through OPNsense as a jump host, since the host only has direct access to the `192.168.56.0/24` (hostonly/LAN) segment:
```cmd
ssh -J root@192.168.56.10 labadmin@10.10.10.10
```

## 7. DVWA Deployment (Target for S-04 — SQL Injection)

nginx was installed only as an early connectivity check; DVWA replaces it as the actual attack target.

```bash
sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
sudo systemctl stop nginx && sudo systemctl disable nginx    # free port 80 for DVWA
sudo docker run -d -p 80:80 --name dvwa vulnerables/web-dvwa
```

### Same NAT Inbound Limitation as SSH

Accessing `http://10.0.99.7/setup.php` directly from the host browser timed out — same root cause as §6 (NAT Network blocks unsolicited host→guest traffic).

**Fix:**
```cmd
VBoxManage natnetwork modify --netname NatNetwork-temp --port-forward-4 "dvwa-http:tcp:[]:8080:[10.0.99.7]:80"
```

Access from host:
```
http://127.0.0.1:8080/setup.php
```

### Database Initialization

On `/setup.php`: click **Create / Reset Database**, then log in.

```
Username: admin
Password: password
```

Security level (`DVWA Security` menu) defaults to **Low** — required for the SQLi scenario in Phase 7 to work without WAF-style interference.

**Validation:**
```bash
sudo docker ps                                                    # dvwa container: Up
sudo docker exec dvwa mysql -u root -ppassword -e "SHOW DATABASES;"   # dvwa database present
curl -I http://localhost                                          # 302 Found → login.php (Apache)
```

## 8. Known Issues Summary

| Issue | Cause | Fix |
|---|---|---|
| VM soft-locks / hangs indefinitely during install or boot | Host has no working VT-x; VirtualBox silently falls back to slow/unstable NEM emulation | Disable Windows Hyper-V platform entirely (`Microsoft-Hyper-V-All`, `HypervisorPlatform`, `VirtualMachinePlatform`, `Containers-DisposableClientVM`) + disable Core Isolation/Memory Integrity, then reboot host. One-time host fix. |
| `apt install` times out reaching `archive.ubuntu.com` despite the guest pinging its intnet gateway fine | Two NICs each installed a default route; the non-internet route (via OPNsense) won | Remove the default route from the intnet-facing NIC's netplan config; leave only the NAT NIC's DHCP-provided default route |
| Host cannot SSH or browse to a guest's NAT-network IP, even though the guest itself can reach the internet and ping the host | VirtualBox NAT Network blocks unsolicited inbound host→guest traffic by design | Add a `--port-forward-4` rule on `NatNetwork-temp` per service/VM, then connect via `127.0.0.1:<host-port>` instead of the guest's NAT IP directly |

## 9. Notes for Remaining Phase 3 VMs

- The VT-x/Hyper-V fix (§2) is host-wide and does not need repeating.
- The dual-gateway routing pattern (§4) and the NAT port-forwarding requirement (§6–7) will very likely recur for srv-file, client-1, client-2, and attacker — apply the same fixes proactively (no default route on the intnet NIC; add port-forward rules for SSH before installing, rather than discovering the issue again).
- `NatNetwork-temp` NICs and all associated port-forward rules must be removed from every VM before Phase 6 (air-gap validation).
