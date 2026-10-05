# Debloat for Windows 11 IoT Enterprise LTSC 2024 (win-client).
# Run as Administrator. Source: docs/phase4-windows-client.md section 3.
# Assembled from the commands run by hand on 2026-10-05; not yet re-run end to end as a script.
# Internet-Explorer-Optional-amd64 is not present in this build, so it is not disabled here.
Set-StrictMode -Version Latest

DISM /Online /Disable-Feature /FeatureName:WindowsMediaPlayer /NoRestart

$svc_off = @('DiagTrack','dmwappushservice','SysMain','WSearch','XblAuthManager')
$svc_off | ForEach-Object {
    Stop-Service $_ -Force -ErrorAction SilentlyContinue
    Set-Service $_ -StartupType Disabled -ErrorAction SilentlyContinue
}

Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2
