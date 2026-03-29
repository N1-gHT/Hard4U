#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.2.1 / 6.2.2: Configure auditd Service & Data Retention
#
# Sub-sections covered:
#   6.2.1.1 - Ensure auditd packages are installed                              (Automated)
#   6.2.1.2 - Ensure auditd service is enabled and active                       (Automated)
#   6.2.1.3 - Ensure auditing for processes that start prior to auditd is enabled (Automated)
#   6.2.1.4 - Ensure audit_backlog_limit is configured                          (Automated)
#   6.2.2.1 - Ensure audit log storage size is configured                       (Automated)
#   6.2.2.2 - Ensure audit logs are not automatically deleted                   (Automated)
#   6.2.2.3 - Ensure system is disabled when audit logs are full                (Automated)
#   6.2.2.4 - Ensure system warns when audit logs are low on space              (Automated)

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------
readonly AUDITD_PKG="auditd"
readonly AUDISPD_PKG="audispd-plugins"
readonly AUDITD_SVC="auditd.service"

readonly GRUB_DEFAULT_FILE="/etc/default/grub"
readonly GRUB_AUDIT_PARAM="audit=1"
readonly GRUB_BACKLOG_PARAM="audit_backlog_limit=8192"

readonly AUDITD_CONF="/etc/audit/auditd.conf"

readonly AUDITD_MAX_LOG_FILE="30"

readonly AUDITD_MAX_LOG_FILE_ACTION="keep_logs"

readonly -a AUDITD_DISK_FULL_PARAMS=(
    "disk_full_action=halt"
    "disk_error_action=halt"
)

readonly -a AUDITD_SPACE_LEFT_PARAMS=(
    "space_left_action=email"
    "admin_space_left_action=single"
)

_GRUB_NEEDS_UPDATE=false
_AUDITD_NEEDS_RESTART=false

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 6.2.1.1 – 6.2.2.4 (8 checks)
# ---------------------------------------------------------------------------
readonly -a AUDITD_CHECKS=(
    "6.2.1.1|_audit_auditd_pkgs          |_rem_auditd_pkgs          |auditd packages installed"
    "6.2.1.2|_audit_auditd_svc           |_rem_auditd_svc           |auditd service enabled and active"
    "6.2.1.3|_audit_grub_audit           |_rem_grub_audit           |auditing for pre-auditd processes enabled"
    "6.2.1.4|_audit_grub_backlog         |_rem_grub_backlog         |audit_backlog_limit configured"
    "6.2.2.1|_audit_auditd_log_size      |_rem_auditd_log_size      |audit log storage size configured"
    "6.2.2.2|_audit_auditd_log_retention |_rem_auditd_log_retention |audit logs not auto-deleted"
    "6.2.2.3|_audit_auditd_disk_full     |_rem_auditd_disk_full     |system disabled when audit logs full"
    "6.2.2.4|_audit_auditd_space_warn    |_rem_auditd_space_warn    |system warns when audit logs low"
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

    local W_ID=9 W_DESC=48 W_ST=6
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
# Generic utility helpers
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

_audit_grub_param() {
    local param="$1"

    local grub_line
    grub_line=$(grep -E '^GRUB_CMDLINE_LINUX=' "$GRUB_DEFAULT_FILE" 2>/dev/null || true)
    if ! echo "$grub_line" | grep -q "\b${param}\b"; then
        log_debug "GRUB param '${param}' missing from ${GRUB_DEFAULT_FILE}"
        return 1
    fi

    if ! grep -q "\b${param}\b" /proc/cmdline; then
        log_debug "GRUB param '${param}' missing from running kernel (/proc/cmdline)"
        return 1
    fi
    return 0
}

_remediate_grub_param() {
    local param="$1"

    if [[ ! -f "$GRUB_DEFAULT_FILE" ]]; then
        log_error "File ${GRUB_DEFAULT_FILE} not found. Cannot remediate GRUB."
        return 1
    fi

    log_info "Ensuring '${param}' is in GRUB_CMDLINE_LINUX..."
    if grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_DEFAULT_FILE"; then
        if ! grep -q "^GRUB_CMDLINE_LINUX=.*\"[^\"]*\b${param}\b" "$GRUB_DEFAULT_FILE"; then
            sed -i "s/^GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 ${param}\"/" "$GRUB_DEFAULT_FILE"
            sed -i "s/^GRUB_CMDLINE_LINUX='\(.*\)'/GRUB_CMDLINE_LINUX='\1 ${param}'/" "$GRUB_DEFAULT_FILE"
        fi
    else
        printf 'GRUB_CMDLINE_LINUX="%s"\n' "$param" >> "$GRUB_DEFAULT_FILE"
    fi
    _GRUB_NEEDS_UPDATE=true
}

_audit_auditd_conf_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    local current_val
    current_val=$(grep -Pi "^\h*${key}\h*=" "$AUDITD_CONF" 2>/dev/null \
        | tail -1 | awk -F'=' '{print $2}' | xargs || true)

    if [[ "$current_val" == "$expected_val" ]]; then
        return 0
    fi
    log_debug "auditd: '${key}'='${current_val}' (expected '${expected_val}')"
    return 1
}

_remediate_auditd_conf_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    log_info "Setting auditd ${key} → ${expected_val}"
    if grep -Piq "^\h*#?\h*${key}\h*=" "$AUDITD_CONF" 2>/dev/null; then
        sed -i -E "s/^\s*#?\s*${key}\s*=.*/${key} = ${expected_val}/I" "$AUDITD_CONF"
    else
        printf '%s = %s\n' "$key" "$expected_val" >> "$AUDITD_CONF"
    fi
    _AUDITD_NEEDS_RESTART=true
}

_audit_auditd_conf_params() {
    local fail=0
    local config
    for config in "$@"; do
        _audit_auditd_conf_param "$config" || fail=1
    done
    return "$fail"
}

_remediate_auditd_conf_params() {
    local config
    for config in "$@"; do
        _audit_auditd_conf_param "$config" || _remediate_auditd_conf_param "$config"
    done
}

# ---------------------------------------------------------------------------
# CIS 6.2.1.1 — auditd packages installed (auditd + audispd-plugins)
# ---------------------------------------------------------------------------
_audit_auditd_pkgs() {
    local fail=0
    _is_installed "$AUDITD_PKG"  || { log_debug "Package '${AUDITD_PKG}' is NOT installed"; fail=1; }
    _is_installed "$AUDISPD_PKG" || { log_debug "Package '${AUDISPD_PKG}' is NOT installed"; fail=1; }
    return "$fail"
}

_rem_auditd_pkgs() {
    log_info "Installing audit packages..."
    apt-get update -qq 2>/dev/null || true
    local pkg
    for pkg in "$AUDITD_PKG" "$AUDISPD_PKG"; do
        if ! _is_installed "$pkg"; then
            log_info "Installing ${pkg}..."
            apt-get install -y "$pkg" >/dev/null
        fi
    done
}

# ---------------------------------------------------------------------------
# CIS 6.2.1.2 — auditd service enabled and active
# ---------------------------------------------------------------------------
_audit_auditd_svc() {
    local fail=0
    systemctl is-enabled "$AUDITD_SVC" 2>/dev/null | grep -q 'enabled' || {
        log_debug "${AUDITD_SVC} is NOT enabled"; fail=1
    }
    systemctl is-active "$AUDITD_SVC" 2>/dev/null | grep -q '^active' || {
        log_debug "${AUDITD_SVC} is NOT active"; fail=1
    }
    return "$fail"
}

_rem_auditd_svc() {
    log_info "Unmasking, enabling and starting ${AUDITD_SVC}..."
    systemctl unmask "$AUDITD_SVC" 2>/dev/null || true
    systemctl --now enable "$AUDITD_SVC" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# CIS 6.2.1.3 — audit=1 in GRUB (pre-auditd auditing)
# ---------------------------------------------------------------------------
_audit_grub_audit()  { _audit_grub_param "$GRUB_AUDIT_PARAM"; }
_rem_grub_audit()    { _remediate_grub_param "$GRUB_AUDIT_PARAM"; }

# ---------------------------------------------------------------------------
# CIS 6.2.1.4 — audit_backlog_limit in GRUB
# ---------------------------------------------------------------------------
_audit_grub_backlog() { _audit_grub_param "$GRUB_BACKLOG_PARAM"; }
_rem_grub_backlog()   { _remediate_grub_param "$GRUB_BACKLOG_PARAM"; }

# ---------------------------------------------------------------------------
# CIS 6.2.2.1 — max_log_file (audit log storage size)
# ---------------------------------------------------------------------------
_audit_auditd_log_size()  { _audit_auditd_conf_param "max_log_file=${AUDITD_MAX_LOG_FILE}"; }
_rem_auditd_log_size()    { _remediate_auditd_conf_param "max_log_file=${AUDITD_MAX_LOG_FILE}"; }

# ---------------------------------------------------------------------------
# CIS 6.2.2.2 — max_log_file_action=keep_logs (no auto-delete)
# ---------------------------------------------------------------------------
_audit_auditd_log_retention()  { _audit_auditd_conf_param "max_log_file_action=${AUDITD_MAX_LOG_FILE_ACTION}"; }
_rem_auditd_log_retention()    { _remediate_auditd_conf_param "max_log_file_action=${AUDITD_MAX_LOG_FILE_ACTION}"; }

# ---------------------------------------------------------------------------
# CIS 6.2.2.3 — disk_full_action + disk_error_action = halt
# ---------------------------------------------------------------------------
_audit_auditd_disk_full()  { _audit_auditd_conf_params "${AUDITD_DISK_FULL_PARAMS[@]}"; }
_rem_auditd_disk_full()    { _remediate_auditd_conf_params "${AUDITD_DISK_FULL_PARAMS[@]}"; }

# ---------------------------------------------------------------------------
# CIS 6.2.2.4 — space_left_action + admin_space_left_action
# ---------------------------------------------------------------------------
_audit_auditd_space_warn()  { _audit_auditd_conf_params "${AUDITD_SPACE_LEFT_PARAMS[@]}"; }
_rem_auditd_space_warn()    { _remediate_auditd_conf_params "${AUDITD_SPACE_LEFT_PARAMS[@]}"; }

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#AUDITD_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${AUDITD_CHECKS[@]}"; do
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

    _run_audit_checks "auditd Service & Data Retention  (CIS 6.2.1.1 – 6.2.2.4)" || global_status=1

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
    _GRUB_NEEDS_UPDATE=false
    _AUDITD_NEEDS_RESTART=false

    for entry in "${AUDITD_CHECKS[@]}"; do
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

    if [[ "$_GRUB_NEEDS_UPDATE" == "true" ]]; then
        log_info "Updating GRUB configuration (update-grub)..."
        if update-grub >/dev/null 2>&1; then
            log_warn "GRUB was updated. A SYSTEM REBOOT IS REQUIRED to apply kernel parameters."
        else
            log_error "Failed to execute update-grub."
            any_failure=true
        fi
    fi

    if [[ "$_AUDITD_NEEDS_RESTART" == "true" ]]; then
        log_info "Restarting auditd to apply new configuration..."
        service auditd restart 2>/dev/null || any_failure=true
    fi

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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.2.1.1 – 6.2.2.4)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.2.1 / 6.2.2: Configure auditd Service & Data Retention"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply auditd hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 6.2.1/6.2.2 auditd Service & Retention — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply auditd hardening)" > /dev/tty
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
    print_section_header "CIS 6.2.1/6.2.2" "Configure auditd Service & Data Retention"
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