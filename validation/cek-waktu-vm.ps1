# Cek jam semua VM lab, satu VM menyala pada satu waktu (router tetap hidup).
# Jalankan di host:  powershell -ExecutionPolicy Bypass -File validation\cek-waktu-vm.ps1
# Skrip ini TIDAK login ke VM. Perintah di dalam VM kamu ketik sendiri di jendela VM,
# lalu hasilnya kamu ketik di sini. Skrip tidak pernah mematikan VM secara paksa.

$Router = "router-opnsense"
$VMs = @(
    @{ Name = "sensor";     Kind = "linux";   Ntp = "192.168.56.10" },
    @{ Name = "srv-web";    Kind = "linux";   Ntp = "10.10.10.1" },
    @{ Name = "srv-file";   Kind = "linux";   Ntp = "10.10.10.1" },
    @{ Name = "client-1";   Kind = "linux";   Ntp = "10.10.20.1" },
    @{ Name = "client-2";   Kind = "linux";   Ntp = "10.10.20.1" },
    @{ Name = "attacker";   Kind = "linux";   Ntp = "10.10.30.1" },
    @{ Name = "win-client"; Kind = "windows"; Ntp = "10.10.20.1" }
)
$Report = Join-Path $PSScriptRoot ("laporan-cek-waktu-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmm"))

function HostUtc { (Get-Date).ToUniversalTime().ToString("u") }

function VmInfo($vm) { & VBoxManage showvminfo $vm --machinereadable }

function VmState($vm) {
    $line = VmInfo $vm | Select-String '^VMState='
    if ($line) { return ($line.ToString() -replace '^VMState="?([^"]*)"?$', '$1') }
    return "unknown"
}

function StopVm($vm) {
    if ((VmState $vm) -ne "running") { return }
    Write-Host "Mematikan $vm (ACPI)..."
    & VBoxManage controlvm $vm acpipowerbutton | Out-Null
    for ($i = 0; $i -lt 36; $i++) {
        Start-Sleep -Seconds 5
        if ((VmState $vm) -ne "running") { return }
    }
    Read-Host "$vm belum mati setelah 3 menit. Matikan dari dalam VM (poweroff / Shut down), lalu tekan Enter"
    while ((VmState $vm) -eq "running") { Start-Sleep -Seconds 5 }
}

function NatLines($vm) {
    $l = VmInfo $vm | Select-String -Pattern 'natnet' -SimpleMatch
    if ($l) { return (($l | ForEach-Object { $_.ToString() }) -join "; ") }
    return "tidak ada"
}

"# Laporan cek waktu VM`n`nDibuat: $(HostUtc) (UTC host)`n" | Set-Content -Encoding UTF8 $Report

# --- Langkah 0: hanya router yang boleh menyala ---
foreach ($v in $VMs) { StopVm $v.Name }

# --- Langkah 1: betulkan RTC router (perlu mati sekali) ---
$rtc = (VmInfo $Router | Select-String '^rtcuseutc=').ToString()
Write-Host "Router sekarang: $rtc"
if ($rtc -notmatch 'on') {
    StopVm $Router
    & VBoxManage modifyvm $Router --rtcuseutc on
    $rtc = (VmInfo $Router | Select-String '^rtcuseutc=').ToString()
}
if ((VmState $Router) -ne "running") { & VBoxManage startvm $Router --type gui | Out-Null }

Read-Host "Tunggu router selesai boot. Di console OPNsense pilih 8, ketik: date -u   lalu LANGSUNG tekan Enter di sini"
$h = HostUtc
$r = Read-Host "Ketik hasil date -u dari router"
"## router-opnsense`n`n- $rtc`n- UTC host: $h`n- date -u router: $r`n- NIC NAT: $(NatLines $Router)`n" | Add-Content -Encoding UTF8 $Report
if ((Read-Host "Apakah jam router sudah sama dengan host (selisih di bawah 1 menit)? (y/n)") -ne "y") {
    "**BERHENTI: jam router masih beda dari host. VM lain belum dicek.**" | Add-Content -Encoding UTF8 $Report
    Write-Host "Berhenti. Laporan: $Report"
    exit 1
}

# --- Langkah 2: VM lain, satu per satu ---
"## VM lain`n`n| VM | UTC host | Jam VM (UTC) | Server NTP terbaca | Seharusnya | NIC NAT |`n|---|---|---|---|---|---|" | Add-Content -Encoding UTF8 $Report
foreach ($v in $VMs) {
    $n = $v.Name
    Write-Host "`n===== $n ====="
    $nat = NatLines $n
    & VBoxManage startvm $n --type gui | Out-Null
    if ($v.Kind -eq "linux") {
        Write-Host "Login di jendela VM, lalu jalankan:`n  date -u`n  timedatectl timesync-status | head -3"
        Read-Host "Setelah date -u muncul, LANGSUNG tekan Enter di sini"
        $h = HostUtc
        $t = Read-Host "Ketik hasil date -u"
        $s = Read-Host "Ketik isi baris 'Server:' (kosongkan kalau tidak ada)"
    } else {
        Write-Host "Login di jendela VM, buka PowerShell, lalu jalankan:`n  (Get-Date).ToUniversalTime().ToString('u')`n  w32tm /query /status"
        Read-Host "Setelah jam muncul, LANGSUNG tekan Enter di sini"
        $h = HostUtc
        $t = Read-Host "Ketik hasil jam UTC"
        $s = Read-Host "Ketik isi baris 'Source:'"
    }
    "| $n | $h | $t | $s | $($v.Ntp) | $nat |" | Add-Content -Encoding UTF8 $Report
    StopVm $n
}

"`n## Daftar NAT network di host`n`n``````" | Add-Content -Encoding UTF8 $Report
& VBoxManage list natnetworks | Add-Content -Encoding UTF8 $Report
"``````" | Add-Content -Encoding UTF8 $Report

Write-Host "`nSelesai. Laporan: $Report"
Get-Content $Report
