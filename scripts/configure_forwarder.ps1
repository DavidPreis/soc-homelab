# configure_forwarder.ps1
# Run this AFTER installing the Splunk Universal Forwarder on the Windows 10 Victim VM.
# Sets up which logs to forward to the Splunk server.
# Run as Administrator.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
# EDIT THIS to match your Splunk server's IP
$SplunkServerIP = "192.168.100.30"
$SplunkPort     = "9997"
$SplunkIndex    = "soc_homelab"
# ─────────────────────────────────────────────

$ForwarderBase   = "C:\Program Files\SplunkUniversalForwarder"
$InputsConf      = "$ForwarderBase\etc\system\local\inputs.conf"
$OutputsConf     = "$ForwarderBase\etc\system\local\outputs.conf"

Write-Host "[*] Configuring Splunk Universal Forwarder..." -ForegroundColor Cyan

# --- Verify Splunk Forwarder is installed ---
if (-not (Test-Path $ForwarderBase)) {
    Write-Host "[-] Splunk Universal Forwarder not found at $ForwarderBase" -ForegroundColor Red
    Write-Host "    Download from: https://www.splunk.com/en_us/download/universal-forwarder.html"
    exit 1
}

# --- Write inputs.conf (what to collect) ---
Write-Host "[*] Writing inputs.conf..." -ForegroundColor Yellow

$InputsContent = @"
# Splunk Universal Forwarder - inputs.conf
# Configured by configure_forwarder.ps1

[WinEventLog://Security]
index = $SplunkIndex
disabled = false
evt_resolve_ad_obj = 1

[WinEventLog://System]
index = $SplunkIndex
disabled = false

[WinEventLog://Application]
index = $SplunkIndex
disabled = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index = $SplunkIndex
disabled = false
renderXml = false

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
index = $SplunkIndex
disabled = false

[WinEventLog://Windows PowerShell]
index = $SplunkIndex
disabled = false
"@

$InputsContent | Out-File -FilePath $InputsConf -Encoding ASCII -Force
Write-Host "[+] inputs.conf written." -ForegroundColor Green

# --- Write outputs.conf (where to send) ---
Write-Host "[*] Writing outputs.conf..." -ForegroundColor Yellow

$OutputsContent = @"
# Splunk Universal Forwarder - outputs.conf
# Configured by configure_forwarder.ps1

[tcpout]
defaultGroup = splunk_indexer

[tcpout:splunk_indexer]
server = ${SplunkServerIP}:${SplunkPort}
"@

$OutputsContent | Out-File -FilePath $OutputsConf -Encoding ASCII -Force
Write-Host "[+] outputs.conf written." -ForegroundColor Green

# --- Restart forwarder ---
Write-Host "[*] Restarting Splunk Forwarder service..." -ForegroundColor Yellow
Restart-Service -Name "SplunkForwarder" -Force
Start-Sleep -Seconds 5

$svc = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host "[+] SplunkForwarder is running!" -ForegroundColor Green
} else {
    Write-Host "[-] SplunkForwarder did not start. Check: " -ForegroundColor Red
    Write-Host "    $ForwarderBase\var\log\splunk\splunkd.log"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Forwarder configured!"                       -ForegroundColor Cyan
Write-Host " Sending logs to: ${SplunkServerIP}:${SplunkPort}" -ForegroundColor Cyan
Write-Host " Index: $SplunkIndex"                         -ForegroundColor Cyan
Write-Host ""
Write-Host " Verify in Splunk Web:"                       -ForegroundColor Cyan
Write-Host "   index=$SplunkIndex | stats count by host"  -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
