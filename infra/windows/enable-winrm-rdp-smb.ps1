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

Enable-PSRemoting -SkipNetworkProfileCheck -Force
Set-Service -Name winrm -StartupType Automatic
Start-Service -Name winrm
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force
New-NetFirewallRule -Name "WinRM-Inbound-Any" -DisplayName "WinRM HTTP Any" -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -Direction Inbound -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
