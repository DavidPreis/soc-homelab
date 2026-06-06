# Splunk Detection Rules — SOC Homelab

All queries target `index=soc_homelab`. Adjust the index name if you used something different during setup.

---

## Quick Reference Table

| Rule | EventCode(s) | MITRE Technique | Tactic |
|---|---|---|---|
| Port Scan | Sysmon 3 | T1046 | Discovery |
| Brute Force Login | 4625 | T1110.001 | Credential Access |
| Suspicious PowerShell Script | 4104 | T1059.001 | Execution |
| PowerShell Network Connection | Sysmon 3 | T1071 / T1571 | C2 |
| New Local Admin Account | 4732 | T1098 | Privilege Escalation |

---

## Credential Access

### Rule 1 — Brute Force: Multiple Failed Logins

Detects more than 4 failed login attempts within a 2-minute window.

**MITRE:** [T1110.001 — Brute Force: Password Guessing](https://attack.mitre.org/techniques/T1110/001/)

```spl
index=soc_homelab EventCode=4625
| bucket _time span=2m
| stats count by _time
| where count > 4
| eval alert="BRUTE FORCE — " + count + " failed logins in 2 min"
```

---

## Execution

### Rule 2 — Suspicious PowerShell Execution

Detects commonly abused PowerShell commands logged by Script Block Logging (Event 4104).

**MITRE:** [T1059.001 — Command and Scripting Interpreter: PowerShell](https://attack.mitre.org/techniques/T1059/001/)

```spl
index=soc_homelab EventCode=4104
| where len(Message) < 500
| search Message="*whoami*" OR Message="*ipconfig*"
    OR Message="*netstat*" OR Message="*tasklist*"
| table _time, host, User, Message
| sort -_time
```

---

### Rule 3 — Encoded PowerShell Command

Detects `powershell.exe -EncodedCommand` — a classic obfuscation technique.

**MITRE:** [T1027 — Obfuscated Files or Information](https://attack.mitre.org/techniques/T1027/)

```spl
index=soc_homelab EventCode=4688 OR source="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=1
| search (CommandLine="*-EncodedCommand*" OR CommandLine="*-enc *" OR CommandLine="*-e *")
    AND (NewProcessName="*powershell*" OR Image="*powershell*")
| table _time, host, User, CommandLine, ParentImage
| eval alert="ENCODED POWERSHELL COMMAND DETECTED"
```

---

## Discovery

### Rule 4 — Port Scan (High Unique Destination Ports)

Detects a single source scanning many ports in a short window using Sysmon network connection events.

**MITRE:** [T1046 — Network Service Discovery](https://attack.mitre.org/techniques/T1046/)

```spl
index=soc_homelab EventCode=3
| rex field=Message "DestinationPort: (?<DestPort>\d+)"
| rex field=Message "SourceIp: (?<SrcIp>[^\r\n]+)"
| where SrcIp="192.168.100.10"
| bin _time span=5m
| stats dc(DestPort) as unique_ports by _time, SrcIp
| where unique_ports > 3
| eval alert="PORT SCAN — " + unique_ports + " ports hit from " + SrcIp
| table _time, SrcIp, unique_ports, alert
| sort -_time
```

---

### Rule 5 — System/Network Enumeration Commands

Detects common post-compromise discovery commands run from cmd or PowerShell.

**MITRE:** [T1082 — System Information Discovery](https://attack.mitre.org/techniques/T1082/) | [T1057 — Process Discovery](https://attack.mitre.org/techniques/T1057/)

```spl
index=soc_homelab source="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=1
| search CommandLine IN (
    "*whoami*", "*net user*", "*net group*", "*net localgroup*",
    "*ipconfig*", "*systeminfo*", "*tasklist*", "*netstat*",
    "*arp -a*", "*route print*", "*quser*"
  )
| table _time, host, User, Image, CommandLine, ParentImage
| eval alert="SYSTEM ENUMERATION COMMAND"
```

---

## Lateral Movement & C2

### Rule 6 — PowerShell Outbound Network Connection

Detects PowerShell establishing outbound TCP connections — a common reverse shell indicator.

**MITRE:** [T1059.001](https://attack.mitre.org/techniques/T1059/001/) + [T1571 — Non-Standard Port](https://attack.mitre.org/techniques/T1571/)

```spl
index=soc_homelab EventCode=3
| rex field=Message "Image: (?<Image>[^\r\n]+)"
| where like(Image, "%powershell.exe")
| rex field=Message "DestinationIp: (?<DestIp>[^\r\n]+)"
| rex field=Message "DestinationPort: (?<DestPort>\d+)"
| table _time, host, Image, DestIp, DestPort, User
| eval alert="PowerShell Initiated Network Connection"
```

---

### Rule 7 — SMB Lateral Movement

Detects inbound SMB connections (port 445) from unexpected sources.

**MITRE:** [T1021.002 — Remote Services: SMB/Windows Admin Shares](https://attack.mitre.org/techniques/T1021/002/)

```spl
index=soc_homelab source="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=3
| search DestinationPort=445
| stats count dc(SourceIp) as unique_sources by DestinationIp
| where unique_sources > 2
| eval alert="MULTIPLE SMB CONNECTIONS — possible lateral movement scan"
```

---

## Persistence

### Rule 8 — New Local Admin Account Created

**MITRE:** [T1098 — Account Manipulation](https://attack.mitre.org/techniques/T1098/)

```spl
index=soc_homelab EventCode=4732
| search Message="*Administrators*"
| rex field=Message "Account Name:\s+(?<AddedBy>\S+)"
| rex field=Message "Group Name:\s+(?<GroupName>\S+)"
| table _time, host, AddedBy, GroupName
| sort -_time
```

---

### Rule 9 — Scheduled Task Created

**MITRE:** [T1053.005 — Scheduled Task/Job: Scheduled Task](https://attack.mitre.org/techniques/T1053/005/)

```spl
index=soc_homelab EventCode=4698
| table _time, host, SubjectUserName, TaskName, TaskContent
| eval alert="SCHEDULED TASK CREATED: " + TaskName
```

---

### Rule 10 — New Service Installed

**MITRE:** [T1543.003 — Create or Modify System Process: Windows Service](https://attack.mitre.org/techniques/T1543/003/)

```spl
index=soc_homelab EventCode=7045
| table _time, host, ServiceName, ServiceFileName, ServiceType, ServiceAccount
| eval alert="NEW SERVICE INSTALLED: " + ServiceName
```

---

## Useful General Searches

### View All Recent Events by Type
```spl
index=soc_homelab
| stats count by EventCode
| sort -count
```

### Timeline of Events from a Specific Host
```spl
index=soc_homelab host="WIN10-VICTIM"
| sort _time
| table _time, EventCode, Message
```

### Top Source IPs Generating Failures
```spl
index=soc_homelab EventCode=4625
| stats count by IpAddress
| sort -count
| head 10
```

### All Sysmon Events
```spl
index=soc_homelab source="XmlWinEventLog:Microsoft-Windows-Sysmon/Operational"
| stats count by EventCode
| sort EventCode
```

---

## Sysmon Event ID Reference

| EventCode | Description |
|---|---|
| 1 | Process creation |
| 2 | File creation time changed |
| 3 | Network connection |
| 5 | Process terminated |
| 6 | Driver loaded |
| 7 | Image loaded (DLL) |
| 8 | CreateRemoteThread |
| 10 | Process access (credential theft indicator) |
| 11 | File created |
| 12/13/14 | Registry events |
| 15 | File stream created |
| 22 | DNS query |
| 23 | File delete |
| 25 | Process tampering |

## Windows Security Event ID Reference

| EventCode | Description |
|---|---|
| 4624 | Successful logon |
| 4625 | Failed logon |
| 4648 | Logon with explicit credentials |
| 4688 | New process created |
| 4698 | Scheduled task created |
| 4720 | User account created |
| 4732 | Member added to security-enabled local group |
| 4756 | Member added to universal security group |
| 7045 | New service installed |
