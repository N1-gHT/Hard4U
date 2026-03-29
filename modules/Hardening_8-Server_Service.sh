#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 2.1: Configure Server Services
#
# Sub-sections covered:
#   2.1.1  - Ensure autofs services are not in use
#   2.1.2  - Ensure avahi daemon services are not in use
#   2.1.3  - Ensure dhcp server services are not in use
#   2.1.4  - Ensure dns server services are not in use
#   2.1.5  - Ensure dnsmasq services are not in use
#   2.1.6  - Ensure ftp server services are not in use
#   2.1.7  - Ensure ldap server services are not in use
#   2.1.8  - Ensure message access server services are not in use
#   2.1.9  - Ensure network file system services are not in use
#   2.1.10 - Ensure nis server services are not in use
#   2.1.11 - Ensure print server services are not in use
#   2.1.12 - Ensure rpcbind services are not in use
#   2.1.13 - Ensure rsync services are not in use
#   2.1.14 - Ensure samba file server services are not in use
#   2.1.15 - Ensure snmp services are not in use
#   2.1.16 - Ensure telnet-server services are not in use
#   2.1.17 - Ensure tftp server services are not in use
#   2.1.18 - Ensure web proxy server services are not in use
#   2.1.19 - Ensure web server services are not in use
#   2.1.20 - Ensure xinetd services are not in use
#   2.1.21 - Ensure X window server services are not in use
#   2.1.22 - Ensure mail transfer agents are configured for local-only mode
#   2.1.23 - Ensure only approved services are listening (Manual)

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors — auto-disabled when stdout is not a TTY or NO_COLOR=true
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BRIGHT_RED='\033[1;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

if [[ ! -t 1 || "${NO_COLOR:-}" == "true" ]]; then
    C_RESET='' C_BRIGHT_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_DIM=''
fi
readonly C_RESET C_BRIGHT_RED C_GREEN C_YELLOW C_BLUE C_BOLD C_DIM

# ---------------------------------------------------------------------------
# Log functions
# ---------------------------------------------------------------------------
log_info()     { echo -e "${C_BLUE}[INFO]     $*${C_RESET}"; }
log_ok()       { echo -e "${C_GREEN}[OK]       $*${C_RESET}"; }
log_warn()     { echo -e "${C_YELLOW}[WARN]     $*${C_RESET}" >&2; }
log_error()    { echo -e "${C_BRIGHT_RED}[ERROR]    $*${C_RESET}" >&2; }
log_critical() { echo -e "${C_BRIGHT_RED}${C_BOLD}[CRITICAL] $*${C_RESET}" >&2; exit 1; }
log_debug()    { [[ "${SCRIPT_DEBUG:-false}" == "true" ]] || return 0; echo -e "[DEBUG] $*" >&2; }

print_section_header() { echo -e "\n${C_BOLD}========== $1: $2 ==========${C_RESET}"; }

# ---------------------------------------------------------------------------
# Tree & Table helpers
# ---------------------------------------------------------------------------
_rep() { local i; for (( i=0; i<$1; i++ )); do printf '%s' "$2"; done; }
_tree_label() { echo -e "\n  ${C_BOLD}$*${C_RESET}"; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    log_critical "This script must be run as root."
fi

# ---------------------------------------------------------------------------
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------

readonly -a PACKAGES_TO_MASK_ONLY=()

readonly MTA_PORTS=("25" "465" "587")
readonly POSTFIX_MAIN_CF="/etc/postfix/main.cf"

readonly -a SERVICES_TO_DISABLE=(
    "2.1.1|autofs|autofs.service|Autofs"
    "2.1.2|avahi-daemon|avahi-daemon.socket avahi-daemon.service|Avahi daemon"
    "2.1.3|kea|kea-dhcp4-server.service kea-dhcp6-server.service kea-dhcp-ddns-server.service|DHCP Server (Kea)"
    "2.1.4|bind9|named.service|DNS Server (bind9)"
    "2.1.5|dnsmasq|dnsmasq.service|dnsmasq"
    "2.1.6|vsftpd|vsftpd.service|FTP Server (vsftpd)"
    "2.1.7|slapd|slapd.service|LDAP Server (slapd)"
    "2.1.8|dovecot-imapd dovecot-pop3d|dovecot.socket dovecot.service|Message Access Server (Dovecot)"
    "2.1.9|nfs-kernel-server|nfs-server.service|NFS Server"
    "2.1.10|ypserv|ypserv.service|NIS Server"
    "2.1.11|cups|cups.socket cups.service|Print Server (CUPS)"
    "2.1.12|rpcbind|rpcbind.socket rpcbind.service|rpcbind"
    "2.1.13|rsync|rsync.service|rsync"
    "2.1.14|samba|smbd.service|Samba file server"
    "2.1.15|snmpd|snmpd.service|SNMP server"
    "2.1.16|telnetd telnetd-ssl|inetutils-inetd.service|Telnet server"
    "2.1.17|tftpd-hpa|tftpd-hpa.service|TFTP server"
    "2.1.18|squid|squid.service|Web proxy server (Squid)"
    "2.1.19|apache2 nginx|apache2.socket apache2.service nginx.service|Web server (Apache/Nginx)"
    "2.1.20|xinetd|xinetd.service|xinetd"
    "2.1.21|xserver-common||X Window Server"
)

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
declare -a _RESULT_IDS=()
declare -a _RESULT_DESCS=()
declare -a _RESULT_STATUSES=()
declare -a _RESULT_DETAILS=()

record_result() {
    _RESULT_IDS+=("$1")
    _RESULT_DESCS+=("$2")
    _RESULT_STATUSES+=("$3")
    _RESULT_DETAILS+=("${4:-}")
}

reset_results() {
    _RESULT_IDS=()
    _RESULT_DESCS=()
    _RESULT_STATUSES=()
    _RESULT_DETAILS=()
}

# ---------------------------------------------------------------------------
# Summary table
# Column inner widths: W_ID=7  W_DESC=34  W_ST=6
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=7 W_DESC=34 W_ST=6

    local S_ID S_DESC S_ST S_FULL
    S_ID=$(  _rep $(( W_ID   + 2 )) '─')
    S_DESC=$(_rep $(( W_DESC + 2 )) '─')
    S_ST=$(  _rep $(( W_ST   + 2 )) '─')
    S_FULL=$(_rep $(( W_ID + W_DESC + W_ST + 8 )) '─')

    local W_SUMMARY=$(( W_ID + W_DESC + W_ST + 7 ))

    echo ""
    echo -e "${C_BOLD}  ┌${S_ID}┬${S_DESC}┬${S_ST}┐${C_RESET}"
    printf   "  ${C_BOLD}│ %-*s │ %-*s │ %-*s │${C_RESET}\n" \
        "$W_ID" "CIS" "$W_DESC" "Description" "$W_ST" "Status"
    echo -e "${C_BOLD}  ├${S_ID}┼${S_DESC}┼${S_ST}┤${C_RESET}"

    for i in "${!_RESULT_IDS[@]}"; do
        local st="${_RESULT_STATUSES[$i]}"
        local row_color=""
        [[ "$st" == "FAIL" ]] && row_color="${C_BRIGHT_RED}"
        printf "  ${row_color}│ %-*s │ %-*s │ %-*s │${C_RESET}\n" \
            "$W_ID" "${_RESULT_IDS[$i]}" \
            "$W_DESC" "${_RESULT_DESCS[$i]}" \
            "$W_ST" "$st"
    done

    echo -e "  ├${S_FULL}┤"

    local summary_color="${C_GREEN}"
    [[ $fail_count -gt 0 ]] && summary_color="${C_YELLOW}"

    printf "  ${summary_color}│ %-*s│${C_RESET}\n" "$W_SUMMARY" \
        " ${pass_count}/${total} checks -- PASS: ${pass_count}  FAIL: ${fail_count}"

    echo -e "  └${S_FULL}┘"
    echo ""
}

# ---------------------------------------------------------------------------
# Service helpers
# ---------------------------------------------------------------------------

_audit_service() {
    local pkgs="$1"
    local svcs="$2"

    local pkg_found=false
    for pkg in $pkgs; do
        if dpkg-query -s "$pkg" &>/dev/null; then
            pkg_found=true
            break
        fi
    done

    if [[ "$pkg_found" == "false" ]]; then
        log_debug "None of '$pkgs' installed — compliant."
        return 0
    fi

    if [[ -z "$svcs" ]]; then
        log_debug "Package '$pkgs' installed, no services to check → non-compliant."
        return 1
    fi

    local fail=0
    for svc in $svcs; do
        if systemctl is-enabled "$svc" 2>/dev/null | grep -q 'enabled'; then
            log_debug "Service $svc is ENABLED."
            fail=1
        fi
        if systemctl is-active "$svc" 2>/dev/null | grep -q '^active'; then
            log_debug "Service $svc is ACTIVE."
            fail=1
        fi
    done

    return "$fail"
}

_remediate_service() {
    local pkgs="$1"
    local svcs="$2"
    local any_mask_needed=false

    for pkg in $pkgs; do
        dpkg-query -s "$pkg" &>/dev/null || continue

        local mask_only=false
        for protected in "${PACKAGES_TO_MASK_ONLY[@]}"; do
            if [[ "$pkg" == "$protected" ]]; then
                log_info "Package '$pkg' is in mask-only policy — skipping purge."
                mask_only=true
                break
            fi
        done

        if [[ "$mask_only" == "false" ]]; then
            local dry_out remove_count
            dry_out=$(apt-get purge -s "$pkg" 2>/dev/null || true)
            remove_count=$(echo "$dry_out" | grep -c '^Remv' || true)

            if [[ "$remove_count" -gt 1 ]]; then
                log_warn "Purging '$pkg' would remove $remove_count packages — falling back to mask."
                mask_only=true
            else
                log_info "Purging '$pkg'..."
                if apt-get purge -y "$pkg" >/dev/null 2>&1; then
                    log_ok "Package '$pkg' purged."
                else
                    log_error "Purge failed for '$pkg' — falling back to mask."
                    mask_only=true
                fi
            fi
        fi

        [[ "$mask_only" == "true" ]] && any_mask_needed=true
    done

    if [[ "$any_mask_needed" == "true" ]]; then
        if [[ -z "$svcs" ]]; then
            log_error "Cannot mask: no services defined for '$pkgs'."
            return 1
        fi
        _mask_services "$svcs" || return 1
    fi

    apt-get autoremove -y >/dev/null 2>&1 || true
    return 0
}

_mask_services() {
    log_info "Stopping and masking: $*"
    local failed=false

    if ! systemctl stop "$@" 2>/dev/null; then
        log_warn "Some units could not be stopped (may already be inactive)."
    fi
    if ! systemctl mask "$@" 2>/dev/null; then
        log_error "Failed to mask: $*"
        failed=true
    else
        log_ok "Units masked: $*"
    fi

    [[ "$failed" == "true" ]] && return 1 || return 0
}

# ---------------------------------------------------------------------------
# CIS 2.1.22 — MTA local-only mode
# ---------------------------------------------------------------------------

audit_mta_local_only() {
    local fail=0

    for port in "${MTA_PORTS[@]}"; do
        if ss -plntu 2>/dev/null | grep -P -- ":${port}\b" \
                | grep -Pvq -- '\h+(127\.0\.0\.1|\[?::1\]?):'; then
            log_warn "MTA port $port is listening on a non-loopback interface."
            fail=1
        fi
    done

    if command -v postconf &>/dev/null; then
        local interfaces
        interfaces=$(postconf -h inet_interfaces 2>/dev/null || true)
        if [[ "$interfaces" != "loopback-only" && "$interfaces" != "localhost" ]]; then
            log_warn "Postfix inet_interfaces = '$interfaces' (expected loopback-only)."
            fail=1
        fi
    fi

    return "$fail"
}

remediate_mta_local_only() {
    if [[ -f "$POSTFIX_MAIN_CF" ]] && command -v postconf &>/dev/null; then
        log_info "Restricting Postfix to loopback-only..."
        postconf -e "inet_interfaces = loopback-only"
        systemctl restart postfix
        log_ok "Postfix configured for loopback-only mode."
    else
        log_warn "Postfix not detected. If using Exim4/Sendmail, configure manually."
    fi
    return 0
}

_audit_one_entry() {
    local cis_id="$1" pkgs="$2" svcs="$3" name="$4" branch="$5"

    if _audit_service "$pkgs" "$svcs"; then
        printf "  %s %-34s  ${C_GREEN}[PASS]${C_RESET}\n" "$branch" "$name"
        record_result "$cis_id" "$name" "PASS"
        return 0
    else
        printf "  %s %-34s  ${C_BRIGHT_RED}[FAIL]${C_RESET}\n" "$branch" "$name"
        record_result "$cis_id" "$name" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_check_compliance() {
    local audit_func="$1"
    local msg_ok="$2"
    local msg_fail="$3"
    local prefix="${4:-Audit}"

    if "$audit_func"; then
        log_ok "${prefix}: ${msg_ok}"
        return 0
    else
        log_warn "${prefix}: ${msg_fail}"
        return 1
    fi
}

_apply_remediation() {
    local audit_func="$1"
    local rem_func="$2"
    local check_msg="$3"
    local already_ok_msg="$4"

    log_info "$check_msg"
    if ! "$audit_func"; then
        "$rem_func" || return 1
    else
        log_ok "$already_ok_msg"
    fi
    return 0
}

# Phase 1: Audit Only
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0

    _tree_label "Server Services  (CIS 2.1.1 – 2.1.21)"

    local last_idx=$(( ${#SERVICES_TO_DISABLE[@]} - 1 ))
    for i in "${!SERVICES_TO_DISABLE[@]}"; do
        local entry="${SERVICES_TO_DISABLE[$i]}"
        local cis_id pkgs svcs name
        IFS='|' read -r cis_id pkgs svcs name <<< "$entry"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"

        _audit_one_entry "$cis_id" "$pkgs" "$svcs" "$name" "$branch" || global_status=1
    done

    _tree_label "Mail Transfer Agent  (CIS 2.1.22)"
    if audit_mta_local_only; then
        log_ok "MTA is configured for local-only mode."
        record_result "2.1.22" "MTA local-only mode" "PASS"
    else
        log_warn "MTA is listening on public interfaces."
        record_result "2.1.22" "MTA local-only mode" "FAIL"
        global_status=1
    fi

    log_info "CIS 2.1.23 (Manual): Verify that only approved services are listening" \
             "on network interfaces — run 'ss -plntu' to review."

    print_summary_table

    if [[ "$global_status" -eq 0 ]]; then
        log_ok "Global Audit: SYSTEM IS COMPLIANT."
    else
        log_warn "Global Audit: SYSTEM IS NOT COMPLIANT."
    fi

    return "$global_status"
}

# Phase 2: Remediation Only
run_phase_remediation() {
    print_section_header "MODE" "REMEDIATION ONLY"
    local any_failure=false

    for entry in "${SERVICES_TO_DISABLE[@]}"; do
        local cis_id pkgs svcs name
        IFS='|' read -r cis_id pkgs svcs name <<< "$entry"

        if ! _audit_service "$pkgs" "$svcs"; then
            log_info "[$cis_id] Remediating: $name..."
            _remediate_service "$pkgs" "$svcs" || any_failure=true
        else
            log_ok "[$cis_id] $name — already compliant."
        fi
    done

    _apply_remediation audit_mta_local_only remediate_mta_local_only \
        "Checking MTA network configuration..." \
        "MTA is already restricted to loopback." || any_failure=true

    echo ""
    if [[ "$any_failure" == "true" ]]; then
        log_error "Remediation completed with errors."
        return 1
    else
        log_ok "Remediation completed successfully."
        return 0
    fi
}

# Phase 3: Auto (Audit -> Remediation -> Re-Audit)
run_phase_auto() {
    print_section_header "MODE" "AUTO (Audit + Fix + Verify)"

    if run_phase_audit; then
        log_ok "System is already compliant. No changes needed."
        return 0
    fi

    echo ""
    log_info "Non-compliant items found. Starting remediation..."

    local remediation_status=0
    run_phase_remediation || remediation_status=$?

    echo ""
    log_info "Verifying post-remediation compliance..."

    reset_results
    local verify_status=0

    _tree_label "Post-Remediation Verification  (CIS 2.1.1 – 2.1.21)"

    local last_idx=$(( ${#SERVICES_TO_DISABLE[@]} - 1 ))
    for i in "${!SERVICES_TO_DISABLE[@]}"; do
        local entry="${SERVICES_TO_DISABLE[$i]}"
        local cis_id pkgs svcs name
        IFS='|' read -r cis_id pkgs svcs name <<< "$entry"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"

        _audit_one_entry "$cis_id" "$pkgs" "$svcs" "$name" "$branch" || verify_status=1
    done

    _tree_label "Mail Transfer Agent  (CIS 2.1.22)"
    if audit_mta_local_only; then
        log_ok "MTA is configured for local-only mode."
        record_result "2.1.22" "MTA local-only mode" "PASS"
    else
        log_warn "MTA remediation FAILED or requires manual intervention."
        record_result "2.1.22" "MTA local-only mode" "FAIL"
        verify_status=1
    fi

    print_summary_table

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. System is now compliant."
        return 0
    else
        log_warn "Auto-remediation finished with pending items. Manual review may be required."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# User interface & main
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section 2.1: Configure Server Services"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Disable or remove non-compliant server services."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  SCRIPT_DEBUG=true   Enable debug output on stderr."
    echo "  NO_COLOR=true       Disable ANSI color output."
}

show_interactive_menu() {
        echo -e "\n${C_BOLD}--- CIS 2.1 Server Services — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Disable / remove non-compliant services)" > /dev/tty
    echo "3) Auto             (Audit, fix if needed, then verify)" > /dev/tty
    echo "4) Exit" > /dev/tty
    echo "" > /dev/tty
 
    local choice
    IFS= read -rp "Enter your choice [1-4]: " choice < /dev/tty
    echo "" > /dev/tty

    case "$choice" in
        1) echo "audit" ;;
        2) echo "remediation" ;;
        3) echo "auto" ;;
        4) echo "exit" ;;
        *) echo "invalid" ;;
    esac
}

main() {
    print_section_header "CIS 2.1" "Configure Server Services"
    log_debug "SCRIPT_DEBUG: ${SCRIPT_DEBUG:-false}"

    local mode=""

    if [[ "$#" -gt 0 ]]; then
        case "$1" in
            --audit)       mode="audit" ;;
            --remediation) mode="remediation" ;;
            --auto)        mode="auto" ;;
            --help|-h)     usage; exit 0 ;;
            *)             log_error "Unknown argument: $1"; usage; exit 1 ;;
        esac
    else
        mode=$(show_interactive_menu)

        case "$mode" in
            audit|remediation|auto) ;;
            exit)    log_info "Exiting per user request."; exit 0 ;;
            invalid) log_critical "Invalid selection. Exiting." ;;
            *)       log_critical "Unexpected error in menu selection." ;;
        esac
    fi

    case "$mode" in
        audit)       run_phase_audit ;;
        remediation) run_phase_remediation ;;
        auto)        run_phase_auto ;;
    esac
}

main "$@"