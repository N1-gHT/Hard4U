#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.3: Pluggable Authentication Modules (Part 1)
#
# Sub-sections covered:
#   5.3.1.1 - Ensure latest version of pam (libpam-runtime) is installed
#   5.3.1.2 - Ensure latest version of libpam-modules is installed
#   5.3.1.3 - Ensure latest version of libpam-pwquality is installed
#   5.3.2.1 - Ensure pam_unix module is enabled
#   5.3.2.2 - Ensure pam_faillock module is enabled
#   5.3.2.3 - Ensure pam_pwquality module is enabled
#   5.3.2.4 - Ensure pam_pwhistory module is enabled

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors -- auto-disabled when stdout is not a TTY or NO_COLOR=true
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
readonly PAM_FILES_ALL=(
    "/etc/pam.d/common-account"
    "/etc/pam.d/common-auth"
    "/etc/pam.d/common-password"
    "/etc/pam.d/common-session"
    "/etc/pam.d/common-session-noninteractive"
)
readonly PAM_FILES_AUTH=("/etc/pam.d/common-auth" "/etc/pam.d/common-account")
readonly PAM_FILES_PWD=("/etc/pam.d/common-password")

readonly PAM_CONFIGS_DIR="/usr/share/pam-configs"

readonly PROFILE_CONTENT_FAILLOCK="Name: Enable pam_faillock to deny access
Default: yes
Priority: 0
Auth-Type: Primary
Auth:
	[default=die]	pam_faillock.so authfail"

readonly PROFILE_CONTENT_FAILLOCK_NOTIFY="Name: Notify of failed login attempts and reset count upon success
Default: yes
Priority: 1024
Auth-Type: Primary
Auth:
	requisite	pam_faillock.so preauth
Account-Type: Primary
Account:
	required	pam_faillock.so"

readonly PROFILE_CONTENT_PWQUALITY="Name: Pwquality password strength checking
Default: yes
Priority: 1024
Conflicts: cracklib
Password-Type: Primary
Password:
	requisite	pam_pwquality.so retry=3"

readonly PROFILE_CONTENT_PWHISTORY="Name: pwhistory password history checking
Default: yes
Priority: 1024
Password-Type: Primary
Password:
	requisite	pam_pwhistory.so remember=24 enforce_for_root use_authtok"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array -- CIS 5.3.1.1 to 5.3.2.4 (7 checks)
# ---------------------------------------------------------------------------
readonly -a PAM_CHECKS=(
    "5.3.1.1|_audit_pkg_libpam_runtime  |_rem_pkg_libpam_runtime  |libpam-runtime up-to-date"
    "5.3.1.2|_audit_pkg_libpam_modules  |_rem_pkg_libpam_modules  |libpam-modules up-to-date"
    "5.3.1.3|_audit_pkg_libpam_pwquality|_rem_pkg_libpam_pwquality|libpam-pwquality up-to-date"
    "5.3.2.1|_audit_pam_unix            |_rem_pam_unix            |pam_unix module enabled"
    "5.3.2.2|_audit_pam_faillock        |_rem_pam_faillock        |pam_faillock module enabled"
    "5.3.2.3|_audit_pam_pwquality       |_rem_pam_pwquality       |pam_pwquality module enabled"
    "5.3.2.4|_audit_pam_pwhistory       |_rem_pam_pwhistory       |pam_pwhistory module enabled"
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

    local W_ID=8 W_DESC=42 W_ST=6
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
# Generic helpers: package audit / remediation
# ---------------------------------------------------------------------------
_audit_pkg() {
    local pkg="$1"
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        log_debug "Package '${pkg}' is not installed"
        return 1
    fi
    if apt list --upgradable 2>/dev/null | grep -Pq "^${pkg}/"; then
        log_debug "Package '${pkg}' has an available upgrade"
        return 1
    fi
    return 0
}

_rem_pkg() {
    local pkg="$1"
    log_info "Installing/upgrading ${pkg}..."
    apt-get update -q 2>/dev/null || true
    apt-get install -y "$pkg"
}

# CIS 5.3.1.1
_audit_pkg_libpam_runtime()   { _audit_pkg "libpam-runtime"; }
_rem_pkg_libpam_runtime()     { _rem_pkg   "libpam-runtime"; }

# CIS 5.3.1.2
_audit_pkg_libpam_modules()   { _audit_pkg "libpam-modules"; }
_rem_pkg_libpam_modules()     { _rem_pkg   "libpam-modules"; }

# CIS 5.3.1.3
_audit_pkg_libpam_pwquality() { _audit_pkg "libpam-pwquality"; }
_rem_pkg_libpam_pwquality()   { _rem_pkg   "libpam-pwquality"; }

# ---------------------------------------------------------------------------
# Generic helper: PAM module presence audit
# ---------------------------------------------------------------------------
_audit_pam_module() {
    local module="$1"; shift
    local files=("$@")
    local any_fail=false
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_debug "PAM file absent: ${file}"
            any_fail=true
            continue
        fi
        local module_re="${module//./\\.}"
        if ! grep -Pq -- "\b${module_re}\b" "$file" 2>/dev/null; then
            log_debug "Module '${module}' missing in ${file}"
            any_fail=true
        fi
    done
    [[ "$any_fail" == "true" ]] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# Generic helper: write a pam-auth-update profile file and activate it.
# ---------------------------------------------------------------------------
_enforce_pam_profile() {
    local profile_name="$1"
    local profile_content="${2:-}"
    local profile_path="${PAM_CONFIGS_DIR}/${profile_name}"

    if [[ -n "$profile_content" ]]; then
        log_info "Writing PAM profile: ${profile_name}"
        if ! printf '%s\n' "$profile_content" > "$profile_path"; then
            log_error "Failed to write ${profile_path}"
            return 1
        fi
        chmod 644 "$profile_path"
    fi

    log_info "Activating PAM profile via pam-auth-update: ${profile_name}"
    if ! env DEBIAN_FRONTEND=noninteractive pam-auth-update --enable "$profile_name"; then
        log_error "pam-auth-update failed for ${profile_name}"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.3.2.1 -- pam_unix enabled (all common PAM files)
# ---------------------------------------------------------------------------
_audit_pam_unix() { _audit_pam_module "pam_unix.so" "${PAM_FILES_ALL[@]}"; }
_rem_pam_unix()   { _enforce_pam_profile "unix"; }

# ---------------------------------------------------------------------------
# CIS 5.3.2.2 -- pam_faillock enabled (auth + account files)
# ---------------------------------------------------------------------------
_audit_pam_faillock() { _audit_pam_module "pam_faillock.so" "${PAM_FILES_AUTH[@]}"; }
_rem_pam_faillock() {
    local any_fail=false
    _enforce_pam_profile "faillock"        "$PROFILE_CONTENT_FAILLOCK"        || any_fail=true
    _enforce_pam_profile "faillock_notify" "$PROFILE_CONTENT_FAILLOCK_NOTIFY" || any_fail=true
    [[ "$any_fail" == "true" ]] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.3.2.3 -- pam_pwquality enabled (common-password)
# ---------------------------------------------------------------------------
_audit_pam_pwquality() { _audit_pam_module "pam_pwquality.so" "${PAM_FILES_PWD[@]}"; }
_rem_pam_pwquality()   { _enforce_pam_profile "pwquality" "$PROFILE_CONTENT_PWQUALITY"; }

# ---------------------------------------------------------------------------
# CIS 5.3.2.4 -- pam_pwhistory enabled (common-password)
# ---------------------------------------------------------------------------
_audit_pam_pwhistory() { _audit_pam_module "pam_pwhistory.so" "${PAM_FILES_PWD[@]}"; }
_rem_pam_pwhistory()   { _enforce_pam_profile "pwhistory" "$PROFILE_CONTENT_PWHISTORY"; }

# ---------------------------------------------------------------------------
# Shared audit tree renderer -- called in both audit and verify steps.
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#PAM_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${PAM_CHECKS[@]}"; do
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

    _run_audit_checks "PAM Packages & Modules  (CIS 5.3.1.1 - 5.3.2.4)" || global_status=1

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

    for entry in "${PAM_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        if ! "$audit_func"; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            "$rem_func" || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} -- already compliant."
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.3.1.1 - 5.3.2.4)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.3 PAM (Part 1): Packages & Auth-Update Profiles"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply PAM package and profile hardening."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  SCRIPT_DEBUG=true   Enable debug output on stderr."
    echo "  NO_COLOR=true       Disable ANSI color output."
    echo ""
    echo "Note: pass env vars on the same line as sudo:"
    echo "  sudo SCRIPT_DEBUG=true bash $0 --audit"
}

show_interactive_menu() {
    echo -e "\n${C_BOLD}--- CIS 5.3 PAM (Part 1) -- Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply PAM package and profile hardening)" > /dev/tty
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
    print_section_header "CIS 5.3" "Pluggable Authentication Modules -- Part 1"
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