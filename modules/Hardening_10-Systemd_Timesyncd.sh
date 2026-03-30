#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 2.3: Configure Time Synchronization
#
# Sub-sections covered:
#   2.3.1.1 - Ensure a single time synchronization daemon is in use            (Automated)
#   2.3.2.1 - Ensure systemd-timesyncd configured with authorized timeserver   (Automated)
#   2.3.2.2 - Ensure systemd-timesyncd is enabled and running                  (Automated)

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------
readonly TIMESYNCD_SVC="systemd-timesyncd.service"
readonly TIMESYNCD_DROPIN="/etc/systemd/timesyncd.conf.d/99-cis.conf"
readonly TIMESYNCD_MAIN_CONF="systemd/timesyncd.conf"

readonly CIS_NTP_SERVERS="0.debian.pool.ntp.org 1.debian.pool.ntp.org"
readonly CIS_FALLBACK_SERVERS="2.debian.pool.ntp.org 3.debian.pool.ntp.org"

readonly -a TIME_SYNC_DAEMONS=(
    "systemd-timesyncd.service"
    "chrony.service"
    "ntp.service"
)

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — built dynamically in main() based on active daemon
# ---------------------------------------------------------------------------
declare -a TIMESYNCD_CHECKS=()

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

    local W_ID=9 W_DESC=40 W_ST=6
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
        printf "  %s %-42s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-42s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Generic utility helpers
# ---------------------------------------------------------------------------

_is_chrony_active() {
    systemctl is-active --quiet chrony.service 2>/dev/null
}

_get_timesyncd_param() {
    local key="$1"
    systemd-analyze cat-config "$TIMESYNCD_MAIN_CONF" 2>/dev/null \
        | grep -E "^${key}=" | tail -1 | cut -d= -f2-
}

_set_timesyncd_param() {
    local key="$1" value="$2"
    local dropin_dir
    dropin_dir=$(dirname "$TIMESYNCD_DROPIN")
    [[ -d "$dropin_dir" ]] || mkdir -p "$dropin_dir"

    if [[ ! -f "$TIMESYNCD_DROPIN" ]]; then
        printf '[Time]\n' > "$TIMESYNCD_DROPIN"
    fi

    if grep -q "^${key}=" "$TIMESYNCD_DROPIN" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$TIMESYNCD_DROPIN"
    else
        sed -i "/^\[Time\]/a ${key}=${value}" "$TIMESYNCD_DROPIN"
    fi
}

# ---------------------------------------------------------------------------
# CIS 2.3.1.1 — single time synchronization daemon in use
# ---------------------------------------------------------------------------
_audit_single_time_daemon() {
    local active_count=0 active_list="" svc
    for svc in "${TIME_SYNC_DAEMONS[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            (( ++active_count ))
            active_list+="${svc} "
        fi
    done

    if [[ "$active_count" -eq 1 ]]; then
        return 0
    elif [[ "$active_count" -eq 0 ]]; then
        log_debug "No time sync daemon is active"
        return 1
    else
        log_debug "Multiple time sync daemons active: ${active_list}"
        return 1
    fi
}

_rem_single_time_daemon() {
    local active_count=0 svc
    for svc in "${TIME_SYNC_DAEMONS[@]}"; do
        systemctl is-active --quiet "$svc" 2>/dev/null && (( ++active_count ))
    done

    if [[ "$active_count" -eq 0 ]]; then
        log_info "No time sync daemon active — enabling ${TIMESYNCD_SVC}..."
        systemctl unmask "$TIMESYNCD_SVC" 2>/dev/null || true
        systemctl --now enable "$TIMESYNCD_SVC" >/dev/null 2>&1
    elif [[ "$active_count" -gt 1 ]]; then
        log_warn "Multiple time sync daemons active — manual intervention recommended."
        log_warn "Disable all but one: systemctl disable --now <daemon>"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 2.3.2.1 — systemd-timesyncd configured with authorized timeserver
# ---------------------------------------------------------------------------
_audit_timesyncd_servers() {
    local fail=0

    local ntp_val
    ntp_val=$(_get_timesyncd_param "NTP")
    if [[ -z "$ntp_val" ]]; then
        log_debug "NTP servers not configured in timesyncd"
        fail=1
    fi

    local fallback_val
    fallback_val=$(_get_timesyncd_param "FallbackNTP")
    if [[ -z "$fallback_val" ]]; then
        log_debug "FallbackNTP servers not configured in timesyncd"
        fail=1
    fi

    return "$fail"
}

_rem_timesyncd_servers() {
    log_info "Configuring NTP servers → ${CIS_NTP_SERVERS}"
    _set_timesyncd_param "NTP" "$CIS_NTP_SERVERS"

    log_info "Configuring FallbackNTP servers → ${CIS_FALLBACK_SERVERS}"
    _set_timesyncd_param "FallbackNTP" "$CIS_FALLBACK_SERVERS"

    systemctl reload-or-restart "$TIMESYNCD_SVC" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# CIS 2.3.2.2 — systemd-timesyncd enabled and running
# ---------------------------------------------------------------------------
_audit_timesyncd_svc() {
    local fail=0
    systemctl is-enabled "$TIMESYNCD_SVC" 2>/dev/null | grep -q 'enabled' || {
        log_debug "${TIMESYNCD_SVC} is NOT enabled"; fail=1
    }
    systemctl is-active --quiet "$TIMESYNCD_SVC" 2>/dev/null || {
        log_debug "${TIMESYNCD_SVC} is NOT active"; fail=1
    }
    return "$fail"
}

_rem_timesyncd_svc() {
    log_info "Enabling and starting ${TIMESYNCD_SVC}..."
    systemctl unmask "$TIMESYNCD_SVC" 2>/dev/null || true
    systemctl --now enable "$TIMESYNCD_SVC" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#TIMESYNCD_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${TIMESYNCD_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
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

    _run_audit_checks "Time Synchronization  (CIS 2.3)" || global_status=1

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

    for entry in "${TIMESYNCD_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 2.3)" \
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
    echo "CIS Benchmark Debian 13 - Section 2.3: Configure Time Synchronization"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply time synchronization hardening."
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
    echo -e "\n${C_BOLD}--- CIS 2.3 Time Synchronization — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply time sync hardening)" > /dev/tty
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
    print_section_header "CIS 2.3" "Configure Time Synchronization"
    log_debug "SCRIPT_DEBUG: ${SCRIPT_DEBUG:-false}"

    TIMESYNCD_CHECKS=(
        "2.3.1.1|_audit_single_time_daemon  |_rem_single_time_daemon  |single time sync daemon in use"
    )
    if _is_chrony_active; then
        log_info "Chrony is the active time daemon — CIS 2.3.2.x (timesyncd) checks skipped."
    else
        TIMESYNCD_CHECKS+=(
            "2.3.2.1|_audit_timesyncd_servers   |_rem_timesyncd_servers   |timesyncd authorized timeserver"
            "2.3.2.2|_audit_timesyncd_svc       |_rem_timesyncd_svc       |timesyncd enabled and running"
        )
    fi

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