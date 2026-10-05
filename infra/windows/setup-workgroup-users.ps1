# Network, workgroup, hostname and synthetic lab accounts for win-client.
# Run as Administrator. Source: docs/phase4-windows-client.md section 4.
# Assembled from the commands run by hand on 2026-10-05; not yet re-run end to end as a script.
# The adapter aliases are specific to this VM: confirm them by MAC address
# first (section 1 of that document) before running on a rebuilt VM.
Set-StrictMode -Version Latest

New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.10.20.50 -PrefixLength 24 -DefaultGateway 10.10.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses 10.10.20.1
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.56.50 -PrefixLength 24

# Synthetic lab-only credentials (targets for the brute-force scenarios).
New-LocalUser -Name "labuser" -Password (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force) -FullName "Lab User"
New-LocalUser -Name "admin_lab" -Password (ConvertTo-SecureString "Admin@2024" -AsPlainText -Force) -FullName "Lab Admin"
Add-LocalGroupMember -Group "Administrators" -Member "admin_lab"

Add-Computer -WorkgroupName "LABWORKGROUP"
Rename-Computer -NewName "win-client" -Restart
