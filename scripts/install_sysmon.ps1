# install_sysmon.ps1
# Run this script as Administrator on the Windows 10 Victim VM
# It downloads Sysmon, the SwiftOnSecurity config, and installs everything.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "[*] Starting Sysmon installation..." -ForegroundColor Cyan

# --- Config ---
$TempDir       = "$env:TEMP\SysmonSetup"
$SysmonZip     = "$TempDir\Sysmon.zip"
$SysmonDir     = "$TempDir\Sysmon"
$SysmonExe     = "$SysmonDir\Sysmon64.exe"
$ConfigUrl     = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"
$ConfigPath    = "$TempDir\sysmonconfig.xml"
$SysmonDownUrl = "https://download.sysinternals.com/files/Sysmon.zip"

# --- Create temp folder ---
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# --- Download Sysmon ---
Write-Host "[*] Downloading Sysmon from Sysinternals..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $SysmonDownUrl -OutFile $SysmonZip -UseBasicParsing

# --- Extract ---
Write-Host "[*] Extracting..." -ForegroundColor Yellow
Expand-Archive -Path $SysmonZip -DestinationPath $SysmonDir -Force

# --- Download config ---
Write-Host "[*] Downloading SwiftOnSecurity Sysmon config..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $ConfigUrl -OutFile $ConfigPath -UseBasicParsing

# --- Check if Sysmon already installed ---
$sysmonService = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if ($sysmonService) {
    Write-Host "[!] Sysmon already installed. Updating config..." -ForegroundColor Yellow
    & $SysmonExe -c $ConfigPath
} else {
    # --- Install ---
    Write-Host "[*] Installing Sysmon..." -ForegroundColor Yellow
    & $SysmonExe -accepteula -i $ConfigPath
}

# --- Verify ---
Start-Sleep -Seconds 3
$sysmonService = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if ($sysmonService -and $sysmonService.Status -eq "Running") {
    Write-Host "[+] Sysmon installed and running successfully!" -ForegroundColor Green
    Write-Host "[+] Check Event Viewer: Applications and Services Logs > Microsoft > Windows > Sysmon > Operational"
} else {
    Write-Host "[-] Something went wrong. Check manually in Services." -ForegroundColor Red
}

# --- Enable PowerShell Script Block Logging ---
Write-Host "[*] Enabling PowerShell Script Block Logging..." -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1
Write-Host "[+] Script Block Logging enabled (Event ID 4104)" -ForegroundColor Green

# --- Increase Security log size ---
Write-Host "[*] Increasing Windows Security log size to 1 GB..." -ForegroundColor Yellow
wevtutil sl Security /ms:1073741824
wevtutil sl System /ms:524288000
Write-Host "[+] Log sizes updated." -ForegroundColor Green

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Sysmon setup complete. Next: install the"   -ForegroundColor Cyan
Write-Host " Splunk Universal Forwarder."                 -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
