#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 2.4: Configure Job Schedulers
#
# Sub-sections covered:
#   2.4.1.1 - Ensure cron daemon is enabled and active
#   2.4.1.2 - Ensure access to /etc/crontab is configured
#   2.4.1.3 - Ensure access to /etc/cron.hourly is configured
#   2.4.1.4 - Ensure access to /etc/cron.daily is configured
#   2.4.1.5 - Ensure access to /etc/cron.weekly is configured
#   2.4.1.6 - Ensure access to /etc/cron.monthly is configured
#   2.4.1.7 - Ensure access to /etc/cron.yearly is configured
#   2.4.1.8 - Ensure access to /etc/cron.d is configured
#   2.4.1.9 - Ensure access to crontab is configured
#   2.4.2.1 - Ensure access to at is configured

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
readonly CRON_PKG="cron"
readonly CRON_SVC="cron.service"
readonly CRON_ALLOW="/etc/cron.allow"
readonly CRON_DENY="/etc/cron.deny"

readonly AT_PKG="at"
readonly AT_ALLOW="/etc/at.allow"
readonly AT_DENY="/etc/at.deny"

# ---------------------------------------------------------------------------
# DATA-DRIVEN arrays
# ---------------------------------------------------------------------------
readonly -a PATH_PERMISSION_CHECKS=(
    "2.4.1.2|/etc/crontab|600|/etc/crontab access configured"
    "2.4.1.3|/etc/cron.hourly|700|/etc/cron.hourly access configured"
    "2.4.1.4|/etc/cron.daily|700|/etc/cron.daily access configured"
    "2.4.1.5|/etc/cron.weekly|700|/etc/cron.weekly access configured"
    "2.4.1.6|/etc/cron.monthly|700|/etc/cron.monthly access configured"
    "2.4.1.7|/etc/cron.yearly|700|/etc/cron.yearly access configured"
    "2.4.1.8|/etc/cron.d|700|/etc/cron.d access configured"
)

readonly -a ACCESS_CONTROL_CHECKS=(
    "2.4.1.9|${CRON_ALLOW}|${CRON_DENY}|${CRON_PKG}|_get_cron_group|crontab access configured"
    "2.4.2.1|${AT_ALLOW}|${AT_DENY}|${AT_PKG}|_get_at_group|at access configured"
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

    echo -e "  ├${S_FULL}┤"
    local summary_color="${C_GREEN}"
    [[ $fail_count -gt 0 ]] && summary_color="${C_YELLOW}"
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

_is_service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

_is_service_enabled() {
    systemctl is-enabled "$1" 2>/dev/null | grep -qE '(enabled|alias|static)'
}

_get_cron_group() {
    grep -q "^crontab:" /etc/group && echo "crontab" || echo "root"
}

_get_at_group() {
    grep -q "^daemon:" /etc/group && echo "daemon" || echo "root"
}

# ---------------------------------------------------------------------------
# CIS 2.4.1.1 — Cron daemon enabled and running
# ---------------------------------------------------------------------------

_audit_cron_status() {
    _is_installed "$CRON_PKG" || return 0

    local fail=0
    _is_service_enabled "$CRON_SVC" || { log_debug "$CRON_SVC not enabled"; fail=1; }
    _is_service_active  "$CRON_SVC" || { log_debug "$CRON_SVC not active";  fail=1; }
    return "$fail"
}

_remediate_cron_status() {
    _is_installed "$CRON_PKG" || return 0

    log_info "Unmasking and enabling $CRON_SVC..."
    systemctl unmask "$CRON_SVC" 2>/dev/null || true
    systemctl enable --now "$CRON_SVC" || return 1
    log_ok "$CRON_SVC enabled and started."
}

# ---------------------------------------------------------------------------
# CIS 2.4.1.2 – 2.4.1.8 — Generic path permission checker / fixer
# ---------------------------------------------------------------------------

_audit_path_perms() {
    local l_path="$1" l_expected_mode="$2"

    _is_installed "$CRON_PKG" || return 0
    [[ -e "$l_path" ]]        || return 0

    local file_stat mode uid gid
    file_stat=$(stat -Lc '%a %u %g' "$l_path" 2>/dev/null)
    read -r mode uid gid <<< "$file_stat"

    local fail=0
    if [[ "$uid" -ne 0 || "$gid" -ne 0 ]]; then
        log_debug "$l_path ownership: uid=$uid gid=$gid (expected 0:0)"
        fail=1
    fi
    if [[ "$mode" != "$l_expected_mode" ]]; then
        log_debug "$l_path mode: $mode (expected $l_expected_mode)"
        fail=1
    fi
    return "$fail"
}

_remediate_path_perms() {
    local l_path="$1" l_expected_mode="$2"

    _is_installed "$CRON_PKG" || return 0
    [[ -e "$l_path" ]]        || return 0

    log_info "Securing $l_path (root:root ${l_expected_mode})..."
    chown root:root "$l_path" || return 1
    chmod "$l_expected_mode" "$l_path" || return 1
    log_ok "$l_path secured."
}

# ---------------------------------------------------------------------------
# CIS 2.4.1.9 / 2.4.2.1 — Generic access-control file checker / fixer
# ---------------------------------------------------------------------------

_audit_allow_deny_perms() {
    local l_file="$1" l_expected_group="$2"

    local file_stat mode uid group_name
    file_stat=$(stat -Lc '%a %u %G' "$l_file" 2>/dev/null)
    read -r mode uid group_name <<< "$file_stat"

    local fail=0
    [[ "$uid" -ne 0 ]] && {
        log_debug "$l_file owner uid=$uid (expected 0/root)"
        fail=1
    }
    if [[ "$group_name" != "root" && "$group_name" != "$l_expected_group" ]]; then
        log_debug "$l_file group=$group_name (expected root or $l_expected_group)"
        fail=1
    fi
    [[ "$mode" != "640" ]] && {
        log_debug "$l_file mode=$mode (expected 640)"
        fail=1
    }
    return "$fail"
}

_audit_access_control() {
    local l_allow="$1" l_deny="$2" l_pkg="$3" l_group_func="$4"

    _is_installed "$l_pkg" || return 0

    local fail=0
    local target_group
    target_group=$("$l_group_func")

    if [[ ! -f "$l_allow" ]]; then
        log_debug "$l_allow does not exist (must be present)"
        fail=1
    else
        _audit_allow_deny_perms "$l_allow" "$target_group" || fail=1
    fi

    if [[ -f "$l_deny" ]]; then
        _audit_allow_deny_perms "$l_deny" "$target_group" || fail=1
    fi

    return "$fail"
}

_remediate_access_control() {
    local l_allow="$1" l_deny="$2" l_pkg="$3" l_group_func="$4"

    _is_installed "$l_pkg" || return 0

    local target_group
    target_group=$("$l_group_func")
    local fail=0

    [[ -f "$l_allow" ]] || touch "$l_allow"
    log_info "Securing $l_allow (root:${target_group} 0640)..."
    if chown root:"$target_group" "$l_allow" && chmod 0640 "$l_allow"; then
        log_ok "$l_allow secured."
    else
        log_error "Failed to secure $l_allow."
        fail=1
    fi

    if [[ -f "$l_deny" ]]; then
        log_info "Securing existing $l_deny (root:${target_group} 0640)..."
        if chown root:"$target_group" "$l_deny" && chmod 0640 "$l_deny"; then
            log_ok "$l_deny secured."
        else
            log_error "Failed to secure $l_deny."
            fail=1
        fi
    fi

    return "$fail"
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows=$(( 1 + ${#PATH_PERMISSION_CHECKS[@]} + ${#ACCESS_CONTROL_CHECKS[@]} ))
    local current_row=0
    local branch

    (( ++current_row ))
    [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
    _audit_tree_row "2.4.1.1" "Cron daemon enabled and running" "$branch" \
        _audit_cron_status || global_status=1

    for entry in "${PATH_PERMISSION_CHECKS[@]}"; do
        local cis_id path mode desc
        IFS='|' read -r cis_id path mode desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_path_perms "$path" "$mode" || global_status=1
    done

    for entry in "${ACCESS_CONTROL_CHECKS[@]}"; do
        local cis_id allow deny pkg group_func desc
        IFS='|' read -r cis_id allow deny pkg group_func desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_access_control "$allow" "$deny" "$pkg" "$group_func" || global_status=1
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

    _run_audit_checks "Job Schedulers  (CIS 2.4.1.1 – 2.4.2.1)" || global_status=1

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

    if ! _audit_cron_status; then
        log_info "[2.4.1.1] Remediating: Cron daemon enabled and running..."
        _remediate_cron_status || any_failure=true
    else
        log_ok "[2.4.1.1] Cron daemon — already compliant."
    fi

    for entry in "${PATH_PERMISSION_CHECKS[@]}"; do
        local cis_id path mode desc
        IFS='|' read -r cis_id path mode desc <<< "$entry"
        if ! _audit_path_perms "$path" "$mode"; then
            log_info "[$cis_id] Remediating: $desc..."
            _remediate_path_perms "$path" "$mode" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    for entry in "${ACCESS_CONTROL_CHECKS[@]}"; do
        local cis_id allow deny pkg group_func desc
        IFS='|' read -r cis_id allow deny pkg group_func desc <<< "$entry"
        if ! _audit_access_control "$allow" "$deny" "$pkg" "$group_func"; then
            log_info "[$cis_id] Remediating: $desc..."
            _remediate_access_control "$allow" "$deny" "$pkg" "$group_func" || any_failure=true
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
    _run_audit_checks "Post-Remediation Verification  (CIS 2.4.1.1 – 2.4.2.1)" \
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
    echo "CIS Benchmark Debian 13 - Section 2.4: Configure Job Schedulers"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply job scheduler configurations."
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
    echo -e "\n${C_BOLD}--- CIS 2.4 Job Schedulers — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply job scheduler configurations)" > /dev/tty
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
    print_section_header "CIS 2.4" "Configure Job Schedulers"
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