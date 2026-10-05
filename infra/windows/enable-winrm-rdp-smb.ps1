# SMB share, WinRM and RDP for the attack scenarios (win-client).
# Run as Administrator. Source: docs/phase4-windows-client.md section 6.
# Assembled from the commands run by hand on 2026-10-05; not yet re-run end to end as a script.
Set-StrictMode -Version Latest

# Both NICs must be Private: WinRM refuses to open its firewall exception on Public.
Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private
Set-NetConnectionProfile -InterfaceAlias "Ethernet 2" -NetworkCategory Private

New-Item -Path "C:\LabData" -ItemType Directory -Force
if (-not (Get-SmbShare -Name "LabShare" -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name "LabShare" -Path "C:\LabData" -FullAccess "labuser","admin_lab"
}

Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
