#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 4.1: Configure Uncomplicated Firewall (UFW)
#
# Sub-sections covered:
#   4.1.1 - Ensure ufw is installed
#   4.1.2 - Ensure ufw service is configured
#   4.1.3 - Ensure ufw incoming default is configured
#   4.1.4 - Ensure ufw outgoing default is configured
#   4.1.5 - Ensure ufw routed default is configured

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
# Root check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    log_critical "This script must be run as root."
fi

# ---------------------------------------------------------------------------
# Global variables
# ---------------------------------------------------------------------------
readonly UFW_PKG="ufw"
readonly UFW_SVC="ufw.service"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array
# ---------------------------------------------------------------------------
readonly -a FIREWALL_CHECKS=(
    "4.1.1|_audit_ufw_installed|_remediate_ufw_installed|ufw installed"
    "4.1.2|_audit_ufw_service|_remediate_ufw_service|ufw service configured"
    "4.1.3|_audit_ufw_default_incoming|_remediate_ufw_default_incoming|ufw incoming default configured"
    "4.1.4|_audit_ufw_default_outgoing|_remediate_ufw_default_outgoing|ufw outgoing default configured"
    "4.1.5|_audit_ufw_default_routed|_remediate_ufw_default_routed|ufw routed default configured"
)

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
declare -a _RESULT_IDS=()
declare -a _RESULT_DESCS=()
declare -a _RESULT_STATUSES=()
declare -a _RESULT_DETAILS=()

record_result() {
    _RESULT_IDS+=("$1"); _RESULT_DESCS+=("$2")
    _RESULT_STATUSES+=("$3"); _RESULT_DETAILS+=("${4:-}")
}
reset_results() {
    _RESULT_IDS=(); _RESULT_DESCS=(); _RESULT_STATUSES=(); _RESULT_DETAILS=()
}

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        case "$status" in
            PASS) (( ++pass_count )) ;;
            FAIL) (( ++fail_count )) ;;
        esac
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=9 W_DESC=46 W_ST=6
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

    local summary_color="${C_GREEN}"
    [[ $fail_count -gt 0 ]] && summary_color="${C_YELLOW}"
    echo -e "  ├${S_FULL}┤"
    printf "  ${summary_color}│ %-*s│${C_RESET}\n" "$W_SUMMARY" \
        " ${pass_count}/${total} checks -- PASS: ${pass_count}  FAIL: ${fail_count}"
    echo -e "  └${S_FULL}┘"
    echo ""
}

# ---------------------------------------------------------------------------
# Tree & table helpers
# ---------------------------------------------------------------------------
_rep() { local i; for (( i=0; i<$1; i++ )); do printf '%s' "$2"; done; }
_tree_label() { echo -e "\n  ${C_BOLD}$*${C_RESET}"; }

_audit_tree_row() {
    local cis_id="$1" desc="$2" branch="$3"
    shift 3
    local status=0
    "$@" || status=1
    if [[ "$status" -eq 0 ]]; then
        printf "  %s %-48s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-48s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

_ufw_available() {
    command -v ufw >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# CIS 4.1.1 — ufw installed
# ---------------------------------------------------------------------------
_audit_ufw_installed() {
    _is_installed "$UFW_PKG"
}

_remediate_ufw_installed() {
    log_info "Installing $UFW_PKG..."
    apt-get update -q
    if apt-get install -y "$UFW_PKG" >/dev/null 2>&1; then
        log_ok "$UFW_PKG installed successfully."
    else
        log_error "Failed to install $UFW_PKG."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 4.1.2 — ufw service configured (enabled, active, and framework active)
# ---------------------------------------------------------------------------
_audit_ufw_service() {
    local fail=0

    if ! systemctl is-enabled "$UFW_SVC" 2>/dev/null | grep -q 'enabled'; then
        log_debug "UFW service is not enabled"
        fail=1
    fi
    if ! systemctl is-active --quiet "$UFW_SVC" 2>/dev/null; then
        log_debug "UFW service is not active"
        fail=1
    fi
    if _ufw_available && ! ufw status 2>/dev/null | grep -q 'Status: active'; then
        log_debug "UFW framework status is not active"
        fail=1
    fi

    return "$fail"
}

_remediate_ufw_service() {
    log_warn "Applying anti-lockout rule: allowing SSH (port 22/tcp)..."
    log_info "Refine this rule later according to your local site policy."
    ufw allow proto tcp from any to any port 22 >/dev/null 2>&1 || true

    log_info "Unmasking and enabling $UFW_SVC..."
    systemctl unmask "$UFW_SVC" 2>/dev/null || true

    if ! systemctl enable --now "$UFW_SVC" 2>/dev/null; then
        log_error "Failed to enable $UFW_SVC."
        return 1
    fi

    log_info "Activating UFW framework..."
    if ! ufw --force enable >/dev/null 2>&1; then
        log_error "Failed to activate UFW framework."
        return 1
    fi
    log_ok "UFW is now enabled and active."
}

# ---------------------------------------------------------------------------
# CIS 4.1.3 — ufw incoming default deny/reject
# ---------------------------------------------------------------------------
_audit_ufw_default_incoming() {
    _ufw_available || return 1
    ufw status verbose 2>/dev/null \
        | grep -qiE "Default:\s+(deny|reject)\s*\(incoming\)"
    log_debug "UFW incoming default: $(ufw status verbose 2>/dev/null | grep -i default || true)"
}

_remediate_ufw_default_incoming() {
    _ufw_available || { log_error "ufw command not found."; return 1; }
    log_info "Setting default incoming policy to 'deny'..."
    if ufw default deny incoming >/dev/null 2>&1; then
        log_ok "UFW default incoming → deny."
    else
        log_error "Failed to set UFW default incoming policy."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 4.1.4 — ufw outgoing default deny/reject
# ---------------------------------------------------------------------------
_audit_ufw_default_outgoing() {
    _ufw_available || return 1
    ufw status verbose 2>/dev/null \
        | grep -qiE "Default:.*\b(deny|reject)\b.*\(outgoing\)"
    log_debug "UFW outgoing default: $(ufw status verbose 2>/dev/null | grep -i default || true)"
}

_remediate_ufw_default_outgoing() {
    _ufw_available || { log_error "ufw command not found."; return 1; }

    log_warn "Applying safe outgoing rules before denying all traffic..."
    ufw allow out to any port 53  comment 'Allow DNS'           >/dev/null 2>&1 || true
    ufw allow out to any port 853 comment 'Allow DNS over TLS'  >/dev/null 2>&1 || true
    ufw allow out 80/tcp          comment 'Allow HTTP'          >/dev/null 2>&1 || true
    ufw allow out 443/tcp         comment 'Allow HTTPS'         >/dev/null 2>&1 || true
    ufw allow out 123/udp         comment 'Allow NTP'           >/dev/null 2>&1 || true

    log_info "Setting default outgoing policy to 'deny'..."
    if ufw default deny outgoing >/dev/null 2>&1; then
        log_ok "UFW default outgoing → deny."
    else
        log_error "Failed to set UFW default outgoing policy."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 4.1.5 — ufw routed default disabled/deny
# ---------------------------------------------------------------------------
_audit_ufw_default_routed() {
    _ufw_available || return 1
    ufw status verbose 2>/dev/null \
        | grep -qiE "Default:.*\b(disabled|deny|reject)\b.*\(routed\)"
    log_debug "UFW routed default: $(ufw status verbose 2>/dev/null | grep -i default || true)"
}

_remediate_ufw_default_routed() {
    _ufw_available || { log_error "ufw command not found."; return 1; }
    log_info "Setting default routed policy to 'disabled'..."
    if ufw default disabled routed >/dev/null 2>&1; then
        log_ok "UFW default routed → disabled."
    else
        log_error "Failed to set UFW default routed policy."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#FIREWALL_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${FIREWALL_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
    done

    print_summary_table
    return "$global_status"
}

# ---------------------------------------------------------------------------
# Phase 1: Audit Only
# ---------------------------------------------------------------------------
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0

    _run_audit_checks "Host Based Firewall  (CIS 4.1.1 – 4.1.5)" \
        || global_status=1

    if [[ "$global_status" -eq 0 ]]; then
        log_ok "Global Audit: SYSTEM IS COMPLIANT."
    else
        log_warn "Global Audit: SYSTEM IS NOT COMPLIANT."
    fi
    return "$global_status"
}

# ---------------------------------------------------------------------------
# Phase 2: Remediation Only
# ---------------------------------------------------------------------------
run_phase_remediation() {
    print_section_header "MODE" "REMEDIATION ONLY"
    local any_failure=false

    for entry in "${FIREWALL_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        if ! "$audit_func"; then
            log_info "[$cis_id] Remediating: $desc..."
            "$rem_func" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    echo ""
    if [[ "$any_failure" == "true" ]]; then
        log_error "Remediation completed with errors."
        return 1
    else
        log_ok "Remediation completed successfully."
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Phase 3: Auto (Audit → Remediation → Re-Audit)
# ---------------------------------------------------------------------------
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
    _run_audit_checks "Post-Remediation Verification  (CIS 4.1.1 – 4.1.5)" \
        || verify_status=1

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
    echo "CIS Benchmark Debian 13 - Section 4.1: Configure Uncomplicated Firewall"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply UFW firewall configurations."
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
    echo -e "\n${C_BOLD}--- CIS 4.1 UFW Firewall — Select Operation Mode ---${C_RESET}" >&2
    echo "1) Audit Only       (Check compliance, no changes)" >&2
    echo "2) Remediation Only (Apply UFW hardening)" >&2
    echo "3) Auto             (Audit, fix if needed, then verify)" >&2
    echo "4) Exit" >&2
    echo "" >&2
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
    print_section_header "CIS 4.1" "Configure Uncomplicated Firewall"
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