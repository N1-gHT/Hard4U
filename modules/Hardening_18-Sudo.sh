#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.2: Configure Privilege Escalation
#
# Sub-sections covered:
#   5.2.1 - Ensure sudo is installed
#   5.2.2 - Ensure sudo commands use pty
#   5.2.3 - Ensure sudo log file exists
#   5.2.4 - Ensure users must provide password for escalation  (no NOPASSWD)
#   5.2.5 - Ensure re-authentication for privilege escalation is not disabled globally (no !authenticate)
#   5.2.6 - Ensure sudo timestamp_timeout is configured
#   5.2.7 - Ensure access to the su command is restricted

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
# Root check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    log_critical "This script must be run as root."
fi

# ---------------------------------------------------------------------------
# Global variables
# ---------------------------------------------------------------------------

readonly SUDO_PKG="sudo"
readonly SUDO_LDAP_PKG="sudo-ldap"
readonly SSSD_SUDO_PKG="libsss-sudo"
readonly SSSD_PKG="sssd"
readonly USE_SUDO_LDAP_LEGACY="${USE_SUDO_LDAP_LEGACY:-false}"
readonly USE_SUDO_LDAP_MODERN="${USE_SUDO_LDAP_MODERN:-false}"

readonly SUDOERS_DIR="/etc/sudoers.d"
readonly SUDOERS_CIS_FILE="${SUDOERS_DIR}/60-cis-hardening"
readonly SUDO_TIMESTAMP_TIMEOUT="15"

readonly PAM_SU_FILE="/etc/pam.d/su"
readonly SU_RESTRICT_GROUP="sugroup"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 5.2.1 – 5.2.7 (7 checks)
# ---------------------------------------------------------------------------
readonly -a SUDO_CHECKS=(
    "5.2.1|_audit_sudo_installed  |_rem_sudo_installed  |sudo mechanism is installed"
    "5.2.2|_audit_sudo_use_pty    |_rem_sudo_use_pty    |sudo use_pty configured"
    "5.2.3|_audit_sudo_logfile    |_rem_sudo_logfile    |sudo log file configured"
    "5.2.4|_audit_sudo_nopasswd   |_rem_sudo_nopasswd   |sudo NOPASSWD tag absent"
    "5.2.5|_audit_sudo_no_auth    |_rem_sudo_no_auth    |sudo !authenticate tag absent"
    "5.2.6|_audit_sudo_timeout    |_rem_sudo_timeout    |sudo timestamp_timeout configured (1-15)"
    "5.2.7|_audit_su_restriction  |_rem_su_restriction  |su command restricted"
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

    local W_ID=6 W_DESC=48 W_ST=6
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
# Tree helpers
# ---------------------------------------------------------------------------
_rep()        { local i; for (( i=0; i<$1; i++ )); do printf '%s' "$2"; done; }
_tree_label() { echo -e "\n  ${C_BOLD}$*${C_RESET}"; }

_audit_tree_row() {
    local cis_id="$1" desc="$2" branch="$3"
    shift 3
    local status=0
    "$@" || status=1
    if [[ "$status" -eq 0 ]]; then
        printf "  %s %-50s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-50s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# ---------------------------------------------------------------------------
# Generic helpers: sudo Defaults param (CIS 5.2.2 / 5.2.3)
# ---------------------------------------------------------------------------
_audit_sudo_param() {
    local config="$1"
    local key="${config%%=*}"

    if grep -rPiq -- "^\h*Defaults\h+([^#\n\r]+,\h*)?!${key}(?=[\s#]|$)" \
            /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        log_debug "sudo option '!${key}' found (explicitly disabled)"
        return 1
    fi

    if grep -rPiq -- "^\h*Defaults\h+([^#\n\r]+,\h*)?${config}(?=[\s#]|$)" \
            /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        return 0
    fi

    log_debug "sudo option '${config}' not found"
    return 1
}

_remediate_sudo_param() {
    local config="$1"
    local line="Defaults ${config}"

    [[ -d "$SUDOERS_DIR" ]] || { mkdir -p "$SUDOERS_DIR"; chmod 750 "$SUDOERS_DIR"; }
    [[ -f "$SUDOERS_CIS_FILE" ]] || { touch "$SUDOERS_CIS_FILE"; chmod 440 "$SUDOERS_CIS_FILE"; }

    if grep -Fq "$line" "$SUDOERS_CIS_FILE" 2>/dev/null; then
        return 0
    fi

    log_info "Adding '${line}' to ${SUDOERS_CIS_FILE}"
    printf '%s\n' "$line" >> "$SUDOERS_CIS_FILE"

    if command -v visudo >/dev/null 2>&1; then
        if ! visudo -cf "$SUDOERS_CIS_FILE" >/dev/null 2>&1; then
            log_error "Syntax check failed for ${SUDOERS_CIS_FILE}. Reverting."
            sed -i '$d' "$SUDOERS_CIS_FILE"
            return 1
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Generic helpers: forbidden sudoers tag (CIS 5.2.4 / 5.2.5)
# ---------------------------------------------------------------------------
_audit_sudo_forbidden() {
    local pattern="$1"
    if grep -rPiq "^\h*[^#\n\r].*${pattern}" \
            /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        log_debug "Forbidden pattern '${pattern}' found in sudoers"
        return 1
    fi
    return 0
}

_remediate_sudo_forbidden() {
    local pattern="$1"
    local any_fail=false

    while IFS= read -r l_file; do
        [[ -f "$l_file" ]] || continue
        log_info "Sanitizing: ${l_file}"
        cp "$l_file" "${l_file}.bak"
        sed -i "/^\h*[^#].*${pattern}/s|^|# CIS-REMOVED: |" "$l_file"
        if command -v visudo >/dev/null 2>&1; then
            if ! visudo -cf "$l_file" >/dev/null 2>&1; then
                log_error "Syntax check failed for ${l_file}. Reverting."
                mv "${l_file}.bak" "$l_file"
                any_fail=true
                continue
            fi
        fi
        rm -f "${l_file}.bak"
        log_ok "Sanitized: ${l_file}"
    done < <(grep -rlPi "^\h*[^#\n\r].*${pattern}" \
                /etc/sudoers /etc/sudoers.d/ 2>/dev/null || true)

    if [[ "$any_fail" == "true" ]]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.2.1 — sudo is installed
# ---------------------------------------------------------------------------
_audit_sudo_installed() {
    if [[ "$USE_SUDO_LDAP_LEGACY" == "true" ]]; then
        if _is_installed "$SUDO_LDAP_PKG"; then
            log_debug "Legacy sudo-ldap installed (as requested)"
            return 0
        fi
        log_debug "Legacy sudo-ldap requested but not installed"
        return 1
    fi

    if [[ "$USE_SUDO_LDAP_MODERN" == "true" ]]; then
        if _is_installed "$SSSD_SUDO_PKG" && _is_installed "$SSSD_PKG"; then
            log_debug "Modern SSSD sudo installed (as requested)"
            return 0
        fi
        log_debug "Modern SSSD sudo requested but not fully installed"
        return 1
    fi

    _is_installed "$SUDO_PKG"        && return 0
    _is_installed "$SUDO_LDAP_PKG"   && return 0
    if _is_installed "$SSSD_SUDO_PKG" && _is_installed "$SSSD_PKG"; then
        return 0
    fi

    log_debug "No valid sudo mechanism found"
    return 1
}

_rem_sudo_installed() {
    apt-get update -q
    if [[ "$USE_SUDO_LDAP_LEGACY" == "true" ]]; then
        log_info "Installing ${SUDO_LDAP_PKG}..."
        apt-get install -y "$SUDO_LDAP_PKG" && return 0
    elif [[ "$USE_SUDO_LDAP_MODERN" == "true" ]]; then
        log_info "Installing ${SSSD_SUDO_PKG} ${SSSD_PKG}..."
        apt-get install -y "$SSSD_SUDO_PKG" "$SSSD_PKG" && return 0
    else
        log_info "Installing ${SUDO_PKG}..."
        apt-get install -y "$SUDO_PKG" && return 0
    fi
    log_error "Failed to install the requested sudo mechanism."
    return 1
}

# ---------------------------------------------------------------------------
# CIS 5.2.2 — use_pty
# ---------------------------------------------------------------------------
_audit_sudo_use_pty() { _audit_sudo_param "use_pty"; }
_rem_sudo_use_pty()   { _remediate_sudo_param "use_pty"; }

# ---------------------------------------------------------------------------
# CIS 5.2.3 — log file
# ---------------------------------------------------------------------------
_audit_sudo_logfile() { _audit_sudo_param 'logfile="/var/log/sudo.log"'; }
_rem_sudo_logfile()   { _remediate_sudo_param 'logfile="/var/log/sudo.log"'; }

# ---------------------------------------------------------------------------
# CIS 5.2.4 — no NOPASSWD tag
# ---------------------------------------------------------------------------
_audit_sudo_nopasswd() { _audit_sudo_forbidden '\bNOPASSWD\b'; }
_rem_sudo_nopasswd()   { _remediate_sudo_forbidden '\bNOPASSWD\b'; }

# ---------------------------------------------------------------------------
# CIS 5.2.5 — no !authenticate tag
# ---------------------------------------------------------------------------
_audit_sudo_no_auth() { _audit_sudo_forbidden '!authenticate\b'; }
_rem_sudo_no_auth()   { _remediate_sudo_forbidden '!authenticate\b'; }

# ---------------------------------------------------------------------------
# CIS 5.2.6 — timestamp_timeout configured (1 – 15 minutes)
# ---------------------------------------------------------------------------
_audit_sudo_timeout() {
    if grep -rPiq '^\h*Defaults\h+([^#\n\r]+,\h*)?!timestamp_timeout\b' \
            /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        log_debug "timestamp_timeout is explicitly disabled"
        return 1
    fi

    local val
    val=$(grep -rPoh '^\h*Defaults\h+[^\n#]*\btimestamp_timeout\s*=\s*\K[-0-9]+' \
            /etc/sudoers /etc/sudoers.d/ 2>/dev/null | tail -1 || true)

    if [[ -z "$val" ]]; then
        log_debug "timestamp_timeout not configured"
        return 1
    fi

    if [[ ! "$val" =~ ^-?[0-9]+$ ]]; then
        log_debug "timestamp_timeout='${val}' not numeric"
        return 1
    fi

    if [[ "$val" -ge 1 && "$val" -le 15 ]]; then
        return 0
    fi

    log_debug "timestamp_timeout=${val} (expected 1–15)"
    return 1
}

_rem_sudo_timeout() {
    _remediate_sudo_param "timestamp_timeout=${SUDO_TIMESTAMP_TIMEOUT}"
}

# ---------------------------------------------------------------------------
# CIS 5.2.7 — su command restricted via pam_wheel.so + empty group
# ---------------------------------------------------------------------------
_audit_su_restriction() {
    [[ -f "$PAM_SU_FILE" ]] || return 0

    local pam_line
    pam_line=$(grep -Pi \
        '^\h*auth\h+(required|requisite)\h+pam_wheel\.so\h+([^#\n\r]+\h+)?use_uid\b\h+([^#\n\r]+\h+)?group=\H+\b' \
        "$PAM_SU_FILE" 2>/dev/null || true)

    if [[ -z "$pam_line" ]]; then
        log_debug "pam_wheel.so with use_uid and group= not found in ${PAM_SU_FILE}"
        return 1
    fi

    local group_name
    group_name=$(echo "$pam_line" | grep -oP 'group=\K\S+')

    local group_info
    group_info=$(grep "^${group_name}:" /etc/group 2>/dev/null || true)

    if [[ -z "$group_info" ]]; then
        log_debug "Group '${group_name}' defined in PAM does not exist in /etc/group"
        return 1
    fi

    local group_users
    group_users=$(echo "$group_info" | cut -d: -f4)

    if [[ -n "$group_users" ]]; then
        log_debug "Group '${group_name}' is not empty: ${group_users}"
        return 1
    fi

    return 0
}

_rem_su_restriction() {
    if ! getent group "$SU_RESTRICT_GROUP" >/dev/null 2>&1; then
        log_info "Creating empty group '${SU_RESTRICT_GROUP}'..."
        groupadd "$SU_RESTRICT_GROUP"
    else
        local group_users
        group_users=$(grep "^${SU_RESTRICT_GROUP}:" /etc/group | cut -d: -f4 || true)
        if [[ -n "$group_users" ]]; then
            log_warn "Group '${SU_RESTRICT_GROUP}' is not empty. Removing all members..."
            sed -i -E "s/^(${SU_RESTRICT_GROUP}:[^:]*:[^:]*:).*/\1/" /etc/group
        fi
    fi

    log_info "Configuring pam_wheel.so in ${PAM_SU_FILE}..."
    if grep -q "pam_wheel.so" "$PAM_SU_FILE" 2>/dev/null; then
        sed -i -E \
            "s|^\s*#?\s*auth\s+.*pam_wheel\.so.*|auth required pam_wheel.so use_uid group=${SU_RESTRICT_GROUP}|" \
            "$PAM_SU_FILE"
    else
        printf 'auth required pam_wheel.so use_uid group=%s\n' "$SU_RESTRICT_GROUP" \
            >> "$PAM_SU_FILE"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer — used for both audit phase and verify phase.
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#SUDO_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${SUDO_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        (( ++current_row ))
        if [[ $current_row -eq $total_rows ]]; then branch="└─"; else branch="├─"; fi
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

    _run_audit_checks "Privilege Escalation  (CIS 5.2.1 – 5.2.7)" || global_status=1

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

    for entry in "${SUDO_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        if ! "$audit_func"; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            "$rem_func" || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} — already compliant."
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.2.1 – 5.2.7)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.2: Configure Privilege Escalation"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply privilege escalation hardening."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  USE_SUDO_LDAP_LEGACY=true   Use sudo-ldap instead of standard sudo."
    echo "  USE_SUDO_LDAP_MODERN=true   Use libsss-sudo + sssd instead of standard sudo."
    echo "  SCRIPT_DEBUG=true           Enable debug output on stderr."
    echo "  NO_COLOR=true               Disable ANSI color output."
    echo ""
    echo "Note: pass env vars on the same line as sudo:"
    echo "  sudo SCRIPT_DEBUG=true bash $0 --audit"
}

show_interactive_menu() {
    echo -e "\n${C_BOLD}--- CIS 5.2 Privilege Escalation — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply privilege escalation hardening)" > /dev/tty
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
    print_section_header "CIS 5.2" "Configure Privilege Escalation"
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