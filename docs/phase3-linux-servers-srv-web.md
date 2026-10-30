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

### Fix (SAAT NAT NIC masih terpasang)

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

> ⚠️ **PENTING:** konfig §4 ini HANYA valid selama NAT NIC (`enp0s8`) terpasang. Setelah NAT NIC dilepas (§10), enp0s3 jadi satu-satunya NIC dan WAJIB pegang default route via OPNsense — lihat **§11**. Tanpa itu srv-web tak bisa membalas host di luar subnet 10.10.10.0/24 (termasuk attacker 10.10.30.10) dan S04 gagal.

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

> ⚠️ **Restart policy:** `docker run` di atas TANPA `--restart` → container `dvwa` TIDAK auto-start setelah VM reboot/golden-restore (gejala: `http 000` dari attacker walau VM nyala). Set sekali:
> ```bash
> sudo docker update --restart unless-stopped dvwa
> ```
> **Lebih kuat (2026-10-15):** `--restart` TAK menjamin apache/mysql di dalam container melayani
> :80 pasca host-reboot. Pakai `dvwa-ensure.service` (§11, `infra/install/dvwa-ensure.{sh,service}`).

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
| Attacker (10.10.30.10) gets `http 000` ke DVWA walau VM srv-web nyala & DVWA `Up` (curl lokal `302`); scenario ke srv-file .11 tetap jalan | srv-web TANPA default route setelah NAT NIC dilepas (§4 menghapusnya) → SYN sampai, SYN-ACK tak bisa balik ke subnet lain | Tambah default route via OPNsense ke enp0s3 (netplan persisten) — lihat §11 |
| DVWA `http 000` dari attacker padahal routing benar | container `dvwa` mati / apache di dalam container tak melayani :80 (tak auto-serve setelah reboot) | `docker restart dvwa` + pasang `dvwa-ensure.service` (§11) |

## 9. Notes for Remaining Phase 3 VMs

- The VT-x/Hyper-V fix (§2) is host-wide and does not need repeating.
- The dual-gateway routing pattern (§4) and the NAT port-forwarding requirement (§6–7) will very likely recur for srv-file, client-1, client-2, and attacker — apply the same fixes proactively (no default route on the intnet NIC; add port-forward rules for SSH before installing, rather than discovering the issue again).
- `NatNetwork-temp` NICs and all associated port-forward rules must be removed from every VM before Phase 6 (air-gap validation).

## 10. Post-Provisioning Status (added 2026-10-05)

| Item | Status |
|---|---|
| Clock sync | systemd-timesyncd pointed at OPNsense (`10.10.10.1`), confirmed `System clock synchronized: yes` on 2026-10-03 — see `phase2-opnsense-setup.md` §11 |
| Golden snapshot | Re-taken 2026-10-06 (offline, after NAT NIC detached), UUID `ae630ccc-3c9d-4d59-bb13-7fe6f9c8f07b` — see `blueprint-v3-updated.md` §5 point 3 |
| Temporary NAT NIC (`NatNetwork-temp`) | **Dilepas 2026-10-06** (`VBoxManage modifyvm "<vm>" --nic2 none`). Dikonfirmasi lewat sapuan `showvminfo ... natnet` kosong untuk semua 8 VM. Golden snapshot di atas sudah diambil setelah pelepasan ini. |

## 11. Routing Fix — default route enp0s3 setelah NAT NIC dilepas (added 2026-10-14)

**Masalah ditemukan saat capture Linux hari-1 (2026-10-14):** S04 (SQLi) gagal — `run-1h` abort ~30s, 0 flow. Dari attacker `curl http://10.10.10.10/login.php` → `http 000`, padahal VM srv-web nyala, container `dvwa` `Up`, dan `curl` **lokal** di srv-web → `302`. Scenario lain ke srv-file (.11) normal.

**Root cause:** golden snapshot srv-web (§10, diambil 2026-10-06 *setelah* NAT NIC dilepas) membekukan netplan §4 yang **tanpa default route**. Dengan NAT NIC sudah tiada, enp0s3 jadi satu-satunya NIC tanpa rute keluar-subnet:
```
# ip route (srv-web — RUSAK)
10.10.10.0/24 dev enp0s3 proto kernel scope link src 10.10.10.10
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
# ping 10.10.30.10 -> "Network is unreachable"
```
srv-file (.11) sebaliknya punya `default via 10.10.10.1 dev enp0s3` → bisa membalas attacker. SYN attacker→srv-web:80 sampai (OPNsense me-route antar-segmen), tapi SYN-ACK srv-web→10.10.30.10 di-drop (beda subnet, tak ada default route) → koneksi tak pernah terbentuk → `http 000`.

Catatan: fix default-route 2026-10-07 (`phase6` Temuan#1) sebetulnya pakai `lab-defroute.service` (systemd oneshot `ip route replace default via 10.10.10.1`). Untuk srv-web service itu **tak efektif** di golden yang aktif hari ini (kemungkinan tak ter-enable di golden, atau gagal timing `network-online`) → rute hilang. Maka fix di-pindah ke netplan (level boot, independen service).

**Fix (netplan persisten):**
```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    enp0s3:
      addresses: [10.10.10.10/24]
      nameservers:
        addresses: [10.10.10.1]
      routes:
        - to: default
          via: 10.10.10.1
```
```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan apply
ip route   # harus muncul: default via 10.10.10.1 dev enp0s3 proto static
```
**Validasi dari attacker:** `curl -s -o /dev/null -w '%{http_code}' http://10.10.10.10/login.php` → `200` ✓.

**Catatan:**
- Default route via OPNsense = **inter-segmen saja** — tetap air-gap (OPNsense tanpa WAN). Aman.
- **Re-golden srv-web offline** → golden otoritatif terkini **`f389a32f-a94f-469f-b3f2-39af5365e4a2`** (2026-10-15; route + `dvwa-ensure.service`, terverifikasi lintas-reboot — tabel `phase6` §Golden). Lama: `07a55c0f` (tanpa route) RUSAK; `a6e88dfb` (route OK, DVWA bisa gagal serve pasca-reboot) usang — jangan di-restore.
- **DVWA auto-serve pasca-reboot** — container `vulnerables/web-dvwa` kadang `Up` tapi apache/mysql tak melayani :80 setelah host reboot (`connection refused`); `--restart unless-stopped` tak cukup. Fix: `dvwa-ensure.service` (`infra/install/dvwa-ensure.{sh,service}`) — boot-time, poll `:80` lalu `docker restart dvwa` bila perlu. Ter-bake di golden `f389a32f`.
- Ini juga sebab kalibrasi 2026-10-12 sempat dapat S04 ~2480 flow lalu hilang: rute pernah ada (manual/boot-order) lalu lenyap saat restore/reboot. Netplan persisten = permanen.
- Fix sejenis berlaku untuk VM lain yang NAT NIC-nya dilepas dan hanya bersisa NIC intnet — pastikan masing-masing punya `default via 10.10.10.1`.
