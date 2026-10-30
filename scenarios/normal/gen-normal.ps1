# N01-WIN — generator trafik NORMAL dari win-client (fase Windows), VERSI PARALEL.
# Jalankan: powershell -ExecutionPolicy Bypass -File gen-normal.ps1 -Duration 1800 -Workers 4
# Tak melibatkan IP attacker -> label=0 (Normal) di pipeline.
#
# Perubahan vs versi lama:
#   - PARALEL: `-Workers N` job background (Start-Job) berjalan bersamaan (default 4).
#   - Think-time 0.5–3 dtk (dulu 1–8 dtk) -> rate normal lebih padat.
#   - Aksi "web" = PAGE-VIEW (2–3 request cepat), meniru perilaku browser.
#   - Tambah aksi unduhan HTTP kecil.
#   - Kontrak marker TIDAK berubah: header ditimpa fresh + 1 baris N01 di finally.
param(
  [int]$Duration = 1800,
  [int]$Workers = 4,
  [string]$Web = "10.10.10.10",
  [string]$FileSrv = "10.10.10.11",
  [string]$Share = "labshare",
  [string]$User = "labadmin",
  [string]$Pass = "labadmin",
  [string]$OutDir = "$env:USERPROFILE"   # folder marker; orkestrator pakai C:\LabData (pasti ada)
)
$ErrorActionPreference = "SilentlyContinue"
if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$start = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$mark = Join-Path $OutDir "normal-markers.csv"
# SELALU tulis header fresh (overwrite) -> tiap run marker bersih (header + 1 baris N01).
"scenario,attack_cat,phase,target,start_utc,end_utc" | Out-File -Encoding ascii $mark
Write-Host "[N01-WIN] mulai $start durasi ${Duration}s workers=$Workers dari $env:COMPUTERNAME"

# worker script block: HANYA terima argumen scalar (Start-Job PS5.1 meratakan array).
$worker = {
  param($Duration, $Web, $FileSrv, $Share, $User, $Pass)
  $paths = @("/", "/login.php", "/index.php", "/vulnerabilities/", "/favicon.ico", "/robots.txt", "/instructions.php")
  $dns   = @("srv-web.lab.local", "srv-file.lab.local", "opnsense.lab.local", "client-1.lab.local")
  $deadline = (Get-Date).AddSeconds($Duration)
  while ((Get-Date) -lt $deadline) {
    switch (Get-Random -Maximum 5) {
      0 { $n = Get-Random -Minimum 2 -Maximum 4
          for ($k = 0; $k -lt $n; $k++) {
            $p = $paths | Get-Random
            Invoke-WebRequest -Uri "http://$Web$p" -TimeoutSec 6 -UseBasicParsing | Out-Null
          }
          Write-Host "  web x$n" }
      1 { $n = $dns | Get-Random
          Resolve-DnsName $n -QuickTimeout | Out-Null
          Write-Host "  dns $n" }
      2 { Test-Connection $FileSrv -Count 2 -Quiet | Out-Null
          Write-Host "  ping" }
      3 { cmd /c "net use \\$FileSrv\$Share /user:$User $Pass" 2>$null | Out-Null
          Get-ChildItem "\\$FileSrv\$Share" | Out-Null
          cmd /c "net use \\$FileSrv\$Share /delete" 2>$null | Out-Null
          Write-Host "  smb $Share" }
      4 { Invoke-WebRequest -Uri "http://$Web/favicon.ico" -TimeoutSec 6 -UseBasicParsing | Out-Null
          Invoke-WebRequest -Uri "http://$Web/dvwa/" -TimeoutSec 6 -UseBasicParsing | Out-Null
          Write-Host "  http dl" }
    }
    Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 3000)
  }
}

# try/finally: baris marker N01 HARUS tetap ditulis walau loop berhenti karena error.
try {
  $jobs = @()
  for ($w = 0; $w -lt $Workers; $w++) {
    $jobs += Start-Job -ScriptBlock $worker -ArgumentList $Duration,$Web,$FileSrv,$Share,$User,$Pass
  }
  $jobs | Wait-Job | Out-Null
  $jobs | Remove-Job -Force | Out-Null
}
finally {
  $end = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  "N01,Normal,windows,benign,$start,$end" | Out-File -Append -Encoding ascii $mark
  Write-Host "[N01-WIN] selesai $end (marker -> $mark)"
}
