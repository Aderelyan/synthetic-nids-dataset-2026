# Windows Firewall logging for the dataset (win-client).
# Run as Administrator. Source: docs/phase4-windows-client.md section 6.
# Assembled from the commands run by hand on 2026-10-05; not yet re-run end to end as a script.
Set-StrictMode -Version Latest

Set-NetFirewallProfile -Profile Domain,Public,Private -LogFileName "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -LogMaxSizeKilobytes 4096 -LogAllowed True -LogBlocked True
