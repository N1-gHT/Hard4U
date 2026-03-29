#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.3: Configure Integrity Checking
#
# Sub-sections covered:
#   6.3.1 - Ensure AIDE is installed                                            (Automated)
#   6.3.2 - Ensure filesystem integrity is regularly checked                    (Automated)
#   6.3.3 - Ensure cryptographic mechanisms protect audit tool integrity        (Automated)

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
readonly AIDE_PKGS="aide aide-common"
readonly AIDE_DB="/var/lib/aide/aide.db"
readonly AIDE_TIMER="dailyaidecheck.timer"
readonly AIDE_TIMER_SVC="dailyaidecheck.service"

readonly AIDE_CIS_CONF="/etc/aide/aide.conf.d/99_cis_rules"
readonly AIDE_BASE_CONF="/etc/aide/aide.conf"

readonly -a AIDE_AUDIT_TOOLS=(
    "/sbin/auditctl"
    "/sbin/auditd"
    "/sbin/ausearch"
    "/sbin/aureport"
    "/sbin/augenrules"
)
readonly AIDE_REQUIRED_FLAGS="p i n u g s b acl xattrs sha512"
readonly AIDE_RULE_STRING="p+i+n+u+g+s+b+acl+xattrs+sha512"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 6.3.1 – 6.3.3 (3 checks)
# ---------------------------------------------------------------------------
readonly -a AIDE_CHECKS=(
    "6.3.1|_audit_aide_installed  |_rem_aide_installed  |AIDE installed and initialized"
    "6.3.2|_audit_aide_scheduled  |_rem_aide_scheduled  |filesystem integrity regularly checked"
    "6.3.3|_audit_aide_audit_tools|_rem_aide_audit_tools|audit tools integrity protected"
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

    local W_ID=7 W_DESC=42 W_ST=6
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
        printf "  %s %-44s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-44s  " "$branch" "$desc"
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

_get_aide_conf() {
    if [[ -f "/var/lib/aide/aide.conf.autogenerated" ]]; then
        printf '%s' "/var/lib/aide/aide.conf.autogenerated"
    elif [[ -f "$AIDE_BASE_CONF" ]]; then
        printf '%s' "$AIDE_BASE_CONF"
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 6.3.1 — AIDE installed and database initialized
# ---------------------------------------------------------------------------
_audit_aide_installed() {
    local fail=0 pkg
    for pkg in $AIDE_PKGS; do
        _is_installed "$pkg" || { log_debug "Package '${pkg}' is NOT installed"; fail=1; }
    done
    [[ "$fail" -eq 1 ]] && return 1

    if [[ ! -f "$AIDE_DB" ]]; then
        log_debug "AIDE database not found: ${AIDE_DB}"
        return 1
    fi
    return 0
}

_rem_aide_installed() {
    export DEBIAN_FRONTEND=noninteractive
    log_info "Installing AIDE packages: ${AIDE_PKGS}..."
    apt-get update -qq 2>/dev/null || true
    local pkg
    for pkg in $AIDE_PKGS; do
        if ! _is_installed "$pkg"; then
            apt-get install -yq "$pkg" >/dev/null 2>&1 || {
                log_error "Failed to install ${pkg}"
                return 1
            }
        fi
    done

    if [[ ! -f "$AIDE_DB" ]]; then
        log_info "Initializing AIDE database (this may take several minutes)..."
        aideinit >/dev/null 2>&1
        if [[ -f "${AIDE_DB}.new" ]]; then
            mv "${AIDE_DB}.new" "$AIDE_DB"
        fi
    fi
}

# ---------------------------------------------------------------------------
# CIS 6.3.2 — filesystem integrity regularly checked (timer)
# ---------------------------------------------------------------------------
_audit_aide_scheduled() {
    local fail=0

    local timer_state
    timer_state=$(systemctl is-enabled "$AIDE_TIMER" 2>/dev/null || echo "unknown")
    if [[ "$timer_state" != "enabled" && "$timer_state" != "static" ]]; then
        log_debug "${AIDE_TIMER} is '${timer_state}' (expected enabled/static)"
        fail=1
    fi

    if ! systemctl is-active --quiet "$AIDE_TIMER" 2>/dev/null; then
        log_debug "${AIDE_TIMER} is NOT active"
        fail=1
    fi

    return "$fail"
}

_rem_aide_scheduled() {
    log_info "Enabling and starting ${AIDE_TIMER}..."
    systemctl unmask "$AIDE_TIMER" 2>/dev/null || true
    systemctl unmask "$AIDE_TIMER_SVC" 2>/dev/null || true
    systemctl --now enable "$AIDE_TIMER" >/dev/null 2>&1 || {
        log_error "Failed to enable ${AIDE_TIMER}"
        return 1
    }
}

# ---------------------------------------------------------------------------
# CIS 6.3.3 — cryptographic mechanisms for audit tools (AIDE rules)
# ---------------------------------------------------------------------------
_audit_aide_audit_tools() {
    command -v aide >/dev/null 2>&1 || { log_debug "AIDE is not installed"; return 1; }

    local aide_conf
    aide_conf=$(_get_aide_conf) || { log_debug "No AIDE config found"; return 1; }

    local fail=0
    local tool real_file aide_out flag
    for tool in "${AIDE_AUDIT_TOOLS[@]}"; do
        real_file=$(readlink -f "$tool" 2>/dev/null || true)
        [[ -f "$real_file" ]] || continue

        aide_out=$(aide --config "$aide_conf" -p "f:${real_file}" 2>/dev/null || true)
        for flag in $AIDE_REQUIRED_FLAGS; do
            if ! echo "$aide_out" | grep -Eq "(^|\+| )${flag}(\$|\+| )"; then
                log_debug "File ${real_file} missing AIDE flag: ${flag}"
                fail=1
                break
            fi
        done
    done
    return "$fail"
}

_rem_aide_audit_tools() {
    command -v aide >/dev/null 2>&1 || { log_error "AIDE is not installed — install it first (6.3.1)"; return 1; }

    local target_conf
    if [[ -d "/etc/aide/aide.conf.d" ]]; then
        target_conf="$AIDE_CIS_CONF"
        [[ -f "$target_conf" ]] || touch "$target_conf"
    else
        target_conf="$AIDE_BASE_CONF"
    fi

    local tool real_file
    for tool in "${AIDE_AUDIT_TOOLS[@]}"; do
        real_file=$(readlink -f "$tool" 2>/dev/null || true)
        [[ -f "$real_file" ]] || continue

        if ! grep -q "^${real_file} " "$target_conf" 2>/dev/null; then
            log_info "Adding AIDE rule: ${real_file} ${AIDE_RULE_STRING}"
            printf '%s %s\n' "$real_file" "$AIDE_RULE_STRING" >> "$target_conf"
        else
            log_info "Updating AIDE rule for ${real_file}"
            sed -ri "s|^${real_file}\s+.*$|${real_file} ${AIDE_RULE_STRING}|" "$target_conf"
        fi
    done

    if command -v update-aide.conf >/dev/null 2>&1; then
        update-aide.conf >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#AIDE_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${AIDE_CHECKS[@]}"; do
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

    _run_audit_checks "Integrity Checking  (CIS 6.3.1 – 6.3.3)" || global_status=1

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

    for entry in "${AIDE_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.3.1 – 6.3.3)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.3: Configure Integrity Checking (AIDE)"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply AIDE integrity checking hardening."
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
    echo -e "\n${C_BOLD}--- CIS 6.3 Integrity Checking (AIDE) — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply AIDE hardening)" > /dev/tty
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
    print_section_header "CIS 6.3" "Configure Integrity Checking (AIDE)"
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