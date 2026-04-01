#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 2.2: Configure Client Services
#
# Sub-sections covered:
#   2.2.1 - Ensure nis client is not installed
#   2.2.2 - Ensure rsh client is not installed
#   2.2.3 - Ensure talk client is not installed
#   2.2.4 - Ensure telnet client is not installed
#   2.2.5 - Ensure ldap client is not installed
#   2.2.6 - Ensure ftp client is not installed

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
# shellcheck disable=SC2034  # Unused variables left for readability
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
# Global variables — DATA-DRIVEN
# ---------------------------------------------------------------------------

readonly -a CLIENT_SERVICES=(
    "2.2.1|nis|NIS Client"
    "2.2.2|rsh-client|RSH Client"
    "2.2.3|talk|Talk Client"
    "2.2.4|telnet inetutils-telnet|Telnet Client"
    "2.2.5|ldap-utils|LDAP Client"
    "2.2.6|ftp tnftp|FTP Client"
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
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=8 W_DESC=36 W_ST=6
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
# Tree row renderer + record_result
# ---------------------------------------------------------------------------
_audit_tree_row() {
    local cis_id="$1" desc="$2" branch="$3"
    shift 3
    local status=0
    "$@" || status=1
    if [[ "$status" -eq 0 ]]; then
        printf "  %s %-38s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-38s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Audit / Remediation helpers
# ---------------------------------------------------------------------------

_audit_client_pkgs() {
    local pkgs="$1"
    local fail=0
    for pkg in $pkgs; do
        if dpkg-query -s "$pkg" &>/dev/null; then
            log_debug "Package '$pkg' is installed."
            fail=1
        fi
    done
    return "$fail"
}

_remediate_client_pkgs() {
    local pkgs="$1"
    local fail=0
    local any_removed=false

    for pkg in $pkgs; do
        if dpkg-query -s "$pkg" &>/dev/null; then
            log_info "Purging: $pkg"
            if apt-get purge -y "$pkg" >/dev/null 2>&1; then
                log_ok "Package '$pkg' purged."
                any_removed=true
            else
                log_error "Failed to purge '$pkg'."
                fail=1
            fi
        fi
    done

    if [[ "$any_removed" == "true" ]]; then
        apt-get autoremove -y >/dev/null 2>&1 || true
    fi

    return "$fail"
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_apply_remediation() {
    local audit_func="$1" rem_func="$2" check_msg="$3" already_ok_msg="$4"
    log_info "$check_msg"
    if ! "$audit_func"; then
        "$rem_func" || return 1
    else
        log_ok "$already_ok_msg"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Phase 1: Audit Only
# ---------------------------------------------------------------------------
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0

    _tree_label "Client Services  (CIS 2.2.1 – 2.2.6)"

    local last_idx=$(( ${#CLIENT_SERVICES[@]} - 1 ))
    for i in "${!CLIENT_SERVICES[@]}"; do
        local cis_id pkgs name
        IFS='|' read -r cis_id pkgs name <<< "${CLIENT_SERVICES[$i]}"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"

        _audit_tree_row "$cis_id" "$name not installed" "$branch" \
            _audit_client_pkgs "$pkgs" || global_status=1
    done

    print_summary_table

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

    for entry in "${CLIENT_SERVICES[@]}"; do
        local cis_id pkgs name
        IFS='|' read -r cis_id pkgs name <<< "$entry"

        log_info "[$cis_id] Checking $name..."
        if ! _audit_client_pkgs "$pkgs"; then
            _remediate_client_pkgs "$pkgs" || any_failure=true
        else
            log_ok "[$cis_id] $name — already absent."
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
# Phase 3: Auto (Audit -> Remediation -> Re-Audit)
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

    _tree_label "Post-Remediation Verification  (CIS 2.2.1 – 2.2.6)"

    local last_idx=$(( ${#CLIENT_SERVICES[@]} - 1 ))
    for i in "${!CLIENT_SERVICES[@]}"; do
        local cis_id pkgs name
        IFS='|' read -r cis_id pkgs name <<< "${CLIENT_SERVICES[$i]}"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"

        _audit_tree_row "$cis_id" "$name not installed" "$branch" \
            _audit_client_pkgs "$pkgs" || verify_status=1
    done

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
    echo "CIS Benchmark Debian 13 - Section 2.2: Configure Client Services"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Remove insecure client packages."
    echo "  --auto         Audit, remove if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  SCRIPT_DEBUG=true   Enable debug output on stderr."
    echo "  NO_COLOR=true       Disable ANSI color output."
}

show_interactive_menu() {
    echo -e "\n${C_BOLD}--- CIS 2.2 Client Services — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Remove insecure client packages)" > /dev/tty
    echo "3) Auto             (Audit, remove if needed, then verify)" > /dev/tty
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
    print_section_header "CIS 2.2" "Configure Client Services"
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