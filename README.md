# SOC Homelab — From Zero to Detection

A hands-on Security Operations Center (SOC) homelab that simulates real attack scenarios and detection workflows inside an isolated virtual environment. Built with VMware, Kali Linux, Windows 10, and Splunk.

**FULL DEMO VIDEO: https://www.youtube.com/watch?v=92BU_cwrwBY**

> **Host specs used in this build:** Windows 11 host, 16 GB RAM, VMware Workstation

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Download OS Images](#step-1--download-os-images)
4. [Step 2 — Create Your Core VMs in VMware](#step-2--create-your-core-vms-in-vmware)
5. [Step 3 — Configure Isolated Network](#step-3--configure-isolated-network)
6. [Step 4 — Set Up Splunk on Ubuntu Server](#step-4--set-up-splunk-on-ubuntu-server)
7. [Step 5 — Configure Windows Victim (Sysmon + Splunk Forwarder)](#step-5--configure-windows-victim-sysmon--splunk-forwarder)
8. [Step 6 — Generate Real Attack Traffic from Kali](#step-6--generate-real-attack-traffic-from-kali)
9. [Step 7 — Build Detection Rules in Splunk](#step-7--build-detection-rules-in-splunk)
10. [Step 8 — Map to MITRE ATT&CK](#step-8--map-to-mitre-attck)
11. [Detection Rules Reference](#detection-rules-reference)
12. [Resources](#resources)

---

---

## Prerequisites

- **VMware Workstation Pro** (free for personal use as of 2024 — recommended over VirtualBox for better networking control and snapshot performance)
- ~120 GB free disk space
- 16 GB RAM (the lab uses around 10 GB when all 3 VMs are running simultaneously)
- Internet connection for initial downloads

VMware is the better choice here over VirtualBox — the host-only virtual networking is more reliable, VM isolation is cleaner, and snapshots/clones are noticeably faster. All of these matter when you're regularly resetting state after attacks.

---

## Step 1 — Download OS Images

Get all three ISOs downloaded before setting up any VMs.

### 1a. Kali Linux (Attacker)

1. Go to: https://www.kali.org/get-kali/#kali-installer-images
2. Download the **64-bit Installer** (the standard `.iso`, not the live version)
3. File size: ~4 GB

### 1b. Windows 10 (Victim)

The official Microsoft evaluation ISO works well here — fully functional for 90 days which is more than enough for a lab.

1. Go to: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise
2. Click **Download the ISO** → select **64-bit**
3. File name will be something like `WIN10_22H2_EVAL.iso`
4. File size: ~5 GB

> **Note:** The 90-day limit is a non-issue in practice — take a VM snapshot right after setup is complete and revert to it whenever needed. The timer resets on revert.

### 1c. Ubuntu Server 24.04 LTS (Splunk Host)

1. Go to: https://ubuntu.com/download/server
2. Download **Ubuntu Server 24.04 LTS**
3. File size: ~1.5 GB

---

## Step 2 — Create Your Core VMs in VMware

Open VMware Workstation. For each VM: **File → New Virtual Machine → Typical**.

### VM 1: Kali Linux (Attacker)

| Setting | Value |
|---|---|
| Name | `Kali-Attacker` |
| ISO | `kali-linux-*.iso` |
| Guest OS | Linux → Debian 12.x 64-bit |
| RAM | **2 GB** |
| CPU | 2 cores |
| Disk | 40 GB (store as single file) |
| Network | *Set in Step 3* |

**Installation notes:**
- Choose **Graphical Install**
- Set hostname: `kali-attacker`
- Create a user (e.g., `attacker` / password of your choice)
- At disk partitioning: use **Guided – use entire disk**
- When asked about desktop environment: keep defaults (GNOME + standard tools)

### VM 2: Windows 10 Victim

| Setting | Value |
|---|---|
| Name | `Win10-Victim` |
| ISO | `WIN10_22H2_EVAL.iso` |
| Guest OS | Windows 10 x64 |
| RAM | **4 GB** |
| CPU | 2 cores |
| Disk | 60 GB |
| Network | *Set in Step 3* |

**Installation notes:**
- Choose **Windows 10 Enterprise Evaluation**
- Select **Custom Install**
- When asked for a product key, click **I don't have a product key**
- Create a local account (skip Microsoft account sign-in — click "Domain join instead")
- After install: install **VMware Tools** (VM menu → Install VMware Tools) for better performance

### VM 3: Ubuntu Server (Splunk)

| Setting | Value |
|---|---|
| Name | `Splunk-Server` |
| ISO | `ubuntu-24.04-live-server.iso` |
| Guest OS | Ubuntu 64-bit |
| RAM | **4 GB** |
| CPU | 2 cores |
| Disk | 60 GB |
| Network | *Set in Step 3* |

**Installation notes:**
- Accept all Ubuntu defaults
- Set server name: `splunk-server`
- Create user: `splunkadmin` (or your preference)
- **Do NOT install OpenSSH server** unless you want SSH access from host (optional but useful)
- Skip all snaps on the final screen

---

## Step 3 — Configure Isolated Network

All three VMs need to be on the same isolated network so they can talk to each other but can't reach the internet during attack simulation.

### In VMware: Create a Custom Host-Only Network

1. In VMware go to **Edit → Virtual Network Editor**
2. Click **Add Network** → select `VMnet2` (or any unused number)
3. Set type to **Host-only**
4. Subnet: `192.168.100.0` / Mask: `255.255.255.0`
5. **Uncheck** "Use local DHCP service" (we'll set static IPs)
6. Click **Apply → OK**

### Assign Each VM to VMnet2

For each VM, before powering on: right-click VM → **Settings → Network Adapter → Custom: VMnet2**

### Set Static IPs After Boot

Boot each VM and assign static IPs:

**Kali Linux** — edit `/etc/network/interfaces`:
```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.100.10
    netmask 255.255.255.0
    gateway 192.168.100.1
```
Apply with: `sudo systemctl restart networking`

**Windows 10** — Control Panel → Network → Adapter Settings → IPv4 Properties:
```
IP:      192.168.100.20
Netmask: 255.255.255.0
Gateway: 192.168.100.1
DNS:     8.8.8.8
```

**Splunk Server (Ubuntu)** — edit `/etc/netplan/00-installer-config.yaml`:
```yaml
network:
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.100.30/24]
      nameservers:
        addresses: [8.8.8.8]
      routes:
        - to: default
          via: 192.168.100.1
  version: 2
```
Apply with: `sudo netplan apply`

**Verify connectivity:** From Kali, run `ping 192.168.100.20` and `ping 192.168.100.30`. All three machines should be able to ping each other.

> **Note:** Also ensure **"Connect a host virtual adapter to this network"** is checked for VMnet2 in **Edit → Virtual Network Editor** — this allows your host browser to reach the Splunk web UI.

---

## Step 4 — Set Up Splunk on Ubuntu Server

### 4a. Download Splunk Enterprise (Free Trial)

> **Important — Internet Access:** The Splunk VM is on a host-only network with no internet access. Before downloading, temporarily switch its network adapter to NAT and update the network config to use DHCP:
>
> **1. Switch adapter to NAT:** In VMware right-click the Splunk VM → **Settings → Network Adapter → NAT**
>
> **2. Switch to DHCP temporarily:**
> ```bash
> sudo nano /etc/netplan/00-installer-config.yaml
> ```
> Replace contents with:
> ```yaml
> network:
>   ethernets:
>     ens33:
>       dhcp4: yes
>   version: 2
> ```
> Then run: `sudo netplan apply`
>
> **3.** Download and install Splunk (steps below)
>
> **4. Restore static IP after install:** Switch adapter back to **Custom: VMnet2**, then restore the netplan config:
> ```yaml
> network:
>   ethernets:
>     ens33:
>       dhcp4: no
>       addresses: [192.168.100.30/24]
>       nameservers:
>         addresses: [8.8.8.8]
>       routes:
>         - to: default
>           via: 192.168.100.1
>   version: 2
> ```
> Run `sudo netplan apply` to restore the static IP before proceeding.

On the Splunk Server VM, run:

```bash
# Download Splunk Enterprise .deb (check https://www.splunk.com/en_us/download/splunk-enterprise.html for latest URL)
wget -O splunk.deb 'https://download.splunk.com/products/splunk/releases/9.3.0/linux/splunk-9.3.0-51ccf43db5bd-linux-2.6-amd64.deb'

# Install
sudo dpkg -i splunk.deb
```

> Get the latest download URL from: https://www.splunk.com/en_us/download/splunk-enterprise.html (free account required)

### 4b. Start Splunk and Enable on Boot

```bash
sudo /opt/splunk/bin/splunk start --accept-license
sudo /opt/splunk/bin/splunk enable boot-start

# Set admin credentials when prompted (remember these!)
```

### 4c. Configure Splunk to Receive Logs

```bash
# Enable receiving on port 9997 (for Universal Forwarder)
sudo /opt/splunk/bin/splunk enable listen 9997 -auth admin:yourpassword
```

### 4d. Access Splunk Web UI

From your **host machine** browser (not the VM), navigate to:
```
http://192.168.100.30:8000
```
Log in with the admin credentials you set. You should see the Splunk dashboard.

### 4e. Create an Index for Lab Logs

In Splunk Web: **Settings → Indexes → New Index**
- Index name: `soc_homelab`
- Keep all other defaults → Save

---

## Step 5 — Configure Windows Victim (Sysmon + Splunk Forwarder)

> **Network config for this step:** Steps 5a and 5c require downloading files from the internet. Temporarily switch the Windows VM to NAT before starting:
> 1. In VMware right-click the Windows VM → **Settings → Network Adapter → NAT**
> 2. Set the Windows VM network adapter to DHCP: **Control Panel → Network and Sharing Center → Change adapter settings → right-click your adapter → Properties → IPv4 → Obtain an IP address automatically → OK**
> 3. Complete steps 5a through 5c
> 4. Switch the adapter back to **Custom: VMnet2** when done, then re-enter the static IP: **Control Panel → Network and Sharing Center → Change adapter settings → right-click your adapter → Properties → IPv4** and set:
>    - IP address: `192.168.100.20`
>    - Subnet mask: `255.255.255.0`
>    - Default gateway: `192.168.100.1`
>    - DNS: `8.8.8.8`

Boot your Windows 10 VM. All steps below run on the Windows VM.

### 5a. Install Sysmon

Sysmon provides deep Windows telemetry — process creations, network connections, file hashes, and more.

```powershell
# Run PowerShell as Administrator

# Download Sysmon from Microsoft Sysinternals
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "$env:TEMP\Sysmon.zip"
Expand-Archive "$env:TEMP\Sysmon.zip" -DestinationPath "$env:TEMP\Sysmon"

# Download SwiftOnSecurity's recommended Sysmon config (community standard)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile "$env:TEMP\sysmonconfig.xml"

# Install Sysmon with the config
& "$env:TEMP\Sysmon\Sysmon64.exe" -accepteula -i "$env:TEMP\sysmonconfig.xml"
```

Verify: Open **Event Viewer → Applications and Services Logs → Microsoft → Windows → Sysmon → Operational** — you should see events populating.

### 5b. Enable Key Windows Event Logs

```powershell
# Enable PowerShell Script Block Logging
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
New-Item -Path $regPath -Force | Out-Null
Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1

# Increase Security log size to prevent overwriting
wevtutil sl Security /ms:1073741824
wevtutil sl System /ms:524288000
```

### 5c. Install Splunk Universal Forwarder

1. On your **host machine**, download from: https://www.splunk.com/en_us/download/universal-forwarder.html
   - Choose **Windows 64-bit MSI**
2. Transfer the MSI to the Windows VM (drag-and-drop into VM, or use a shared folder)
3. Run the installer with these settings:
   - **Install as:** Local System
   - **Receiving Indexer:** `192.168.100.30:9997`
   - **Admin username:** `admin`
   - **Admin password:** (set something)
4. After install, configure what to forward:

```powershell
# In PowerShell as Administrator — tell the forwarder what to send

$splunkInputs = @"
[WinEventLog://Security]
index = soc_homelab
disabled = false

[WinEventLog://System]
index = soc_homelab
disabled = false

[WinEventLog://Application]
index = soc_homelab
disabled = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index = soc_homelab
disabled = false
renderXml = false

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
index = soc_homelab
disabled = false
"@

$splunkInputs | Out-File -FilePath "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" -Encoding ASCII

# Restart forwarder to apply
Restart-Service SplunkForwarder
```

### 5d. Verify Logs Are Arriving in Splunk

In Splunk Web, go to **Search & Reporting** and run:
```
index=soc_homelab | stats count by host
```
Your Windows VM's hostname should appear with a count of events. If it does, everything is wired up correctly.

---

## Step 6 — Generate Real Attack Traffic from Kali

> **Network config for this step:** All three VMs must be back on VMnet2 before running any attacks. Verify before starting:
> - All VM network adapters set to **Custom: VMnet2** in VMware settings
> - Kali: `ip a` shows `192.168.100.10`
> - Windows: `ipconfig` shows `192.168.100.20`
> - Splunk: `ip a` shows `192.168.100.30`
>
> No internet access is needed — all attack tools come pre-installed on Kali. If a tool is missing, briefly switch Kali to NAT, run `sudo apt install <tool> -y`, then switch back to VMnet2.

Boot your Kali VM. All attacks below target the Windows VM at `192.168.100.20`.

> **Important:** This is an isolated lab. Never run these tools against machines you don't own.

### 6a. Network Reconnaissance (Port Scan)

```bash
# Full port scan with service detection
nmap -sV -sC -p- 192.168.100.20 -oN scans/windows_fullscan.txt
```

**What the flags do:**
- `-sV` — probe open ports to identify what service and version is running
- `-sC` — run default nmap scripts for additional enumeration
- `-p-` — scan all 65,535 ports (takes a few minutes)
- `-oN` — save output to a file

### 6b. Brute Force SMB

**How it works:**
SMB (Server Message Block) is a network protocol Windows uses for file sharing, printer sharing, and remote authentication. Port 445 is open by default on Windows 10. In this attack:
1. Metasploit connects to port 445 on the victim machine
2. It attempts to authenticate using each password in the wordlist one by one
3. Windows logs each failed attempt as EventCode 4625 (failed logon) in the Security log
4. If a correct password is found, Windows logs a EventCode 4624 (successful logon)
5. Each attempt uses Logon Type 3 (network logon) since it's coming over the network via SMB

This simulates a real-world credential attack where an attacker targets a known username with common passwords — one of the most common attack techniques seen in SOC environments.

**MITRE:** T1110.001 (Brute Force: Password Guessing) + T1021.002 (Remote Services: SMB)

First create a wordlist on Kali:
```bash
echo -e "password\nadmin\nPassword1\nWelcome1\nlab123" > ~/wordlist.txt
```

Then launch Metasploit:
```bash
msfconsole -q
```

Run the SMB brute force:
```
use auxiliary/scanner/smb/smb_login
set RHOSTS 192.168.100.20
set SMBUser victim
set PASS_FILE /home/attacker0/wordlist.txt
set VERBOSE true
run
```

This generates failed login attempts (EventCode 4625) in Splunk for each incorrect password tried.

> **Note:** You can also run `auxiliary/scanner/smb/smb_version` as a pre-attack reconnaissance step — it identifies the SMB version, OS, and hostname of the target without attempting any authentication. This represents the reconnaissance phase an attacker would typically perform before choosing an attack technique.

### 6c. Simulate a Malicious Process (on Windows VM)

On the Windows VM, open **regular (victim) PowerShell** and run these enumeration commands. These are the kinds of commands an attacker runs immediately after gaining access to understand their environment:

```powershell
whoami
ipconfig /all
netstat -an
tasklist
```

### 6d. Reverse Shell Simulation (Safe Version)

On Kali — set up a listener:
```bash
nc -lvnp 4444
```

On the Windows VM, open **regular (victim) PowerShell** (simulating a victim clicking a malicious payload):
```powershell
# Safe simulation — just a TCP connection, no actual exploit
$client = New-Object System.Net.Sockets.TCPClient('192.168.100.10', 4444)
$stream = $client.GetStream()
```
This generates a Sysmon EventCode 3 (network connection) event in Splunk.

### 6e. Simulate Persistence — Create a New Local Admin Account

On the Windows VM, open **Administrator (admin) PowerShell** and run:

```powershell
# Create a fake attacker backdoor account
net user hacker Password123 /add
net localgroup administrators hacker /add
```

This generates EventCode 4720 (new user created) and EventCode 4732 (user added to admin group) in Splunk — simulating a common post-compromise persistence technique where an attacker creates a backdoor account.

Clean it up after Splunk captures the events (still in **admin PowerShell**):

```powershell
net user hacker /delete
```

---

## Step 7 — Build Detection Rules in Splunk

Go to Splunk Web → **Search & Reporting**. The queries below detect each attack simulated in Step 6.

### Rule 1: Port Scan Detection

```spl
index=soc_homelab EventCode=3
| rex field=Message "DestinationPort: (?<DestPort>\d+)"
| rex field=Message "SourceIp: (?<SrcIp>[^\r\n]+)"
| where SrcIp="192.168.100.10"
| bin _time span=5m
| stats dc(DestPort) as unique_ports by _time, SrcIp
| where unique_ports > 3
| eval alert="Possible Port Scan from " + SrcIp
| table _time, SrcIp, unique_ports, alert
| sort -_time
```

### Rule 2: Brute Force Login Detection

```spl
index=soc_homelab EventCode=4625
| bucket _time span=2m
| stats count by _time
| where count > 4
| eval alert="Brute Force Attempt - " + count + " failures in 2 min"
```

### Rule 3: Suspicious PowerShell Execution

```spl
index=soc_homelab EventCode=4104
| where len(Message) < 500
| search Message="*whoami*" OR Message="*ipconfig*"
    OR Message="*netstat*" OR Message="*tasklist*"
| table _time, host, User, Message
| sort -_time
```

### Rule 4: Reverse Shell / Outbound Connection from PowerShell

```spl
index=soc_homelab EventCode=3
| rex field=Message "Image: (?<Image>[^\r\n]+)"
| where like(Image, "%powershell.exe")
| rex field=Message "DestinationIp: (?<DestIp>[^\r\n]+)"
| rex field=Message "DestinationPort: (?<DestPort>\d+)"
| table _time, host, Image, DestIp, DestPort, User
| eval alert="PowerShell Initiated Network Connection"
```

### Rule 5: New Local Admin Account Created

```spl
index=soc_homelab EventCode=4732
| search Message="*Administrators*"
| rex field=Message "Account Name:\s+(?<AddedBy>\S+)"
| rex field=Message "Group Name:\s+(?<GroupName>\S+)"
| table _time, host, AddedBy, GroupName
| sort -_time
```

### Save Rules as Alerts

For each rule you want to monitor continuously:
1. Run the search
2. Click **Save As → Alert**
3. Alert type: **Real-time**
4. Trigger condition: **Per-Result**
5. Check **Throttle**
6. Suppress results containing field value: `*`
7. Suppress triggering for: **8 minutes**
8. Add action: **Add to Triggered Alerts**
9. View triggered alerts under **Activity → Triggered Alerts**

> **Important — Rules 1 and 2 use aggregation (stats/bucket) and don't work reliably as real-time alerts.** Set these two to **Scheduled** instead:
> - Alert type: **Scheduled**
> - Cron expression: `*/5 * * * *`
> - Time range: **Last 5 minutes**
> - Keep throttle enabled with the same settings above
>
> Rules 3, 4, and 5 can stay as real-time since they trigger on individual events without aggregation.

---

## Step 8 — Map to MITRE ATT&CK

Each attack simulated in this lab maps to a documented MITRE ATT&CK technique.

| Attack Simulated | MITRE Technique | Tactic | Splunk Rule |
|---|---|---|---|
| nmap port scan | T1046 — Network Service Discovery | Discovery | Rule 1 |
| Metasploit SMB brute force | T1110.001 — Brute Force: Password Guessing + T1021.002 — Remote Services: SMB | Credential Access | Rule 2 |
| PowerShell enumeration | T1059.001 — PowerShell | Execution | Rule 3 |
| Reverse shell via PowerShell | T1059.001 + T1571 — Non-Standard Port | Execution / C2 | Rule 4 |
| New local admin created | T1136.001 — Create Local Account | Persistence | Rule 5 |
| Process enumeration (tasklist) | T1057 — Process Discovery | Discovery | Rule 3 |

Reference: https://attack.mitre.org/

---

## Detection Rules Reference

See [`splunk_rules.md`](splunk_rules.md) for all SPL queries with full explanations and MITRE mappings.

---

## Resources

- [Splunk Free Trial](https://www.splunk.com/en_us/download/splunk-enterprise.html)
- [Sysmon Download](https://docs.microsoft.com/en-us/sysinternals/downloads/sysmon)
- [SwiftOnSecurity Sysmon Config](https://github.com/SwiftOnSecurity/sysmon-config)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [Kali Linux Tools List](https://www.kali.org/tools/)
- [Splunk SPL Reference](https://docs.splunk.com/Documentation/Splunk/latest/SearchReference/WhatsInThisManual)
- [Windows Security Event IDs Cheat Sheet](https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/)

---

*Built for learning purposes in an isolated lab environment. Never run offensive tools against systems you don't own.*
