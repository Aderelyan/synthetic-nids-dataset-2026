# Phase 1 — VirtualBox Network Setup

Documentation of the isolated lab network topology build for generating a UNSW-NB15-style NIDS dataset. Host: Windows, VirtualBox 7.2.12.

## 1. Environment

| Item | Value | 
|---|---|
| Host OS | Windows |
| VirtualBox | 7.2.12r174389 |
| Host hardware | Intel i7 Gen12, 40 GB RAM |
| Shell | `cmd.exe` (Command Prompt) |

## 2. Network Topology

| Network | Type | Subnet | Purpose |
|---|---|---|---|
| `VirtualBox Host-Only Ethernet Adapter` | Host-Only | 192.168.56.0/24 | Management only (OPNsense WAN-mgmt, sensor mgmt) |
| `intnet-server` | Internal Network | 10.10.10.0/24 | srv-web, srv-file |
| `intnet-client` | Internal Network | 10.10.20.0/24 | client-1, client-2, win-client |
| `intnet-attacker` | Internal Network | 10.10.30.0/24 | attacker (Kali) |
| `NatNetwork-temp` | NAT Network | 10.0.99.0/24 | Temporary — OS ISO/update downloads during provisioning; detached before Phase 6 |

Internal Networks (`intnet`) are **not created via a separate command** — they are auto-created the moment the first VM's NIC is attached with that name. There is no DHCP on an intnet by design (fully isolated); all IPs are assigned statically in Phase 3/4.

## 3. Caveat: Host-Only Adapter Naming on Windows

Unlike Linux (`vboxnet0`), Windows names the host-only adapter with a literal, space-containing string:

```
VirtualBox Host-Only Ethernet Adapter
```

It must be quoted in every command that references it. Check the exact name on your system:

```cmd
VBoxManage list hostonlyifs
```

## 4. Host-Only Network Setup

If the adapter doesn't exist yet:

```cmd
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```

Disable the built-in DHCP server (all VMs use static IPs):

```cmd
VBoxManage list dhcpservers
VBoxManage dhcpserver remove --network "HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter"
```

**Validation:**

```cmd
VBoxManage list hostonlyifs
```

Expected: `IPAddress: 192.168.56.1`, `NetworkMask: 255.255.255.0`, `Status: Up`, `DHCP: Disabled`.

## 5. Temporary NAT Network Setup

Used only for downloading OS ISOs/updates during installation (Phase 3/4). Any NIC using it must be detached before Phase 6 (air-gap validation).

```cmd
VBoxManage natnetwork add --netname NatNetwork-temp --network "10.0.99.0/24" --enable --dhcp on
VBoxManage natnetwork start --netname NatNetwork-temp
```

**Validation:**

```cmd
VBoxManage list natnetworks
```

## 6. Variable Helper (per CMD session)

CMD environment variables don't persist across windows — re-set at the start of every new session:

```cmd
set HOSTONLYIF=VirtualBox Host-Only Ethernet Adapter
```

## 7. VM Registration + NIC Definition

VMs are created as shells (no disk/OS yet) purely to define the network topology. OS installation happens in a separate phase.

### router-opnsense (4 NICs — gateway for all segments)

```cmd
VBoxManage createvm --name "router-opnsense" --ostype "FreeBSD_64" --register
VBoxManage modifyvm "router-opnsense" --nic1 hostonly --hostonlyadapter1 "%HOSTONLYIF%" --nic2 intnet --intnet2 "intnet-server" --nic3 intnet --intnet3 "intnet-client" --nic4 intnet --intnet4 "intnet-attacker"
```

### srv-web

```cmd
VBoxManage createvm --name "srv-web" --ostype "Ubuntu_64" --register
VBoxManage modifyvm "srv-web" --nic1 intnet --intnet1 "intnet-server"
```

### srv-file

```cmd
VBoxManage createvm --name "srv-file" --ostype "Debian_64" --register
VBoxManage modifyvm "srv-file" --nic1 intnet --intnet1 "intnet-server"
```

### client-1 (Linux Phase)

```cmd
VBoxManage createvm --name "client-1" --ostype "Debian_64" --register
VBoxManage modifyvm "client-1" --nic1 intnet --intnet1 "intnet-client"
```

### client-2 (Linux Phase)

```cmd
VBoxManage createvm --name "client-2" --ostype "Debian_64" --register
VBoxManage modifyvm "client-2" --nic1 intnet --intnet1 "intnet-client"
```

### win-client (Windows Phase)

```cmd
VBoxManage createvm --name "win-client" --ostype "Windows11_64" --register
VBoxManage modifyvm "win-client" --nic1 intnet --intnet1 "intnet-client"
```

### attacker (Kali)

```cmd
VBoxManage createvm --name "attacker" --ostype "Debian_64" --register
VBoxManage modifyvm "attacker" --nic1 intnet --intnet1 "intnet-attacker"
```

### sensor (4 NICs — all promiscuous except mgmt)

```cmd
VBoxManage createvm --name "sensor" --ostype "Debian_64" --register
VBoxManage modifyvm "sensor" --nic1 hostonly --hostonlyadapter1 "%HOSTONLYIF%" --nic2 intnet --intnet2 "intnet-server" --nic3 intnet --intnet3 "intnet-client" --nic4 intnet --intnet4 "intnet-attacker"
VBoxManage modifyvm "sensor" --nicpromisc2 allow-all --nicpromisc3 allow-all --nicpromisc4 allow-all
```

## 8. Known Issues & Fixes

| Issue | Cause | Fix |
|---|---|---|
| `'VBoxManage' is not recognized` | Binary not in PATH | Add `C:\Program Files\Oracle\VirtualBox` to PATH, or `cd` into that folder before running commands |
| `Machine settings file '...\<vm>.vbox' already exists` (VBOX_E_FILE_ERROR) | Orphaned `.vbox` folder/file from a previous failed/aborted `createvm` attempt, or a name collision with an old VM | `VBoxManage unregistervm "<vm-name>" --delete`, then re-run `createvm`. If `unregistervm` also fails (VM not registered), delete manually: `rmdir /s /q "C:\Users\<user>\VirtualBox VMs\<vm-name>"` |
| Multi-line command with `^` fails to parse | CMD is unreliable for line continuation | Write each command as a single long line, avoid `^` |
| `%HOSTONLYIF%` expands to empty | Variable was `set` in a different CMD session | Re-run `set HOSTONLYIF=...` in the active session |
| `list intnets` shows a generic `intnet` network (no suffix) | Leftover VMs from another project (e.g. `kali`, `victim`) still use the default `intnet` NIC name | Not part of this topology — ignore it, or `modifyvm` those VMs if you want to clean it up |
| `showvminfo --machinereadable \| findstr "nicpromisc"` returns empty even though the setting is correct | The `nicpromiscN` field is not exposed in `--machinereadable` output on VBox 7.2.12 | Validate with `showvminfo "<vm>"` (no `--machinereadable`) `\| findstr /I "promisc"` — look for `Promisc Policy: allow-all` per NIC in the human-readable output |

## 9. Phase 1 Final Validation

```cmd
VBoxManage list vms
VBoxManage list intnets
VBoxManage list natnetworks
VBoxManage list hostonlyifs
VBoxManage showvminfo "router-opnsense" --machinereadable | findstr "ostype= nic1 nic2 nic3 nic4"
VBoxManage showvminfo "sensor" | findstr /I "promisc"
```

**Expected state:**

| Check | Expected |
|---|---|
| `list vms` | 8 VMs registered: router-opnsense, srv-web, srv-file, client-1, client-2, win-client, attacker, sensor |
| `list intnets` | `intnet-server`, `intnet-client`, `intnet-attacker` (the generic `intnet` from other VMs can be ignored) |
| `list natnetworks` | `NatNetwork-temp`, Enabled: Yes |
| `list hostonlyifs` | IPAddress 192.168.56.1/24, Status Up, DHCP Disabled |
| router-opnsense NICs | nic1=hostonly, nic2/3/4=intnet |
| sensor promisc | NIC 1: `Promisc Policy: deny` (mgmt, default) — NIC 2/3/4: `Promisc Policy: allow-all` |

## 10. Notes for the Next Phase

- Disks (`.vdi`) and OS installation are **not done yet** in this phase — that's Phase 3 (Linux servers/clients) and Phase 4 (Windows client).
- `NatNetwork-temp` must be **detached** from any VM's NIC before Phase 6 (air-gap validation) to prevent traffic leakage during attack-scenario testing.
- `win-client` intentionally shares the `intnet-client` segment with `client-1`/`client-2`, but is **never run at the same time** — this is handled via phase-switching in Phase 7.
