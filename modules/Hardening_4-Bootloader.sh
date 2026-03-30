#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.4: Configure Bootloader
#
# Sub-sections covered:
#   1.4.1 - Ensure bootloader password is set
#   1.4.2 - Ensure access to bootloader config is configured (root:root 0600)

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors — auto-disabled when stdout is not a TTY or NO_COLOR=true
# Follows the no-color.org convention; compatible with non-interactive callers.
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
# Global variables
# ---------------------------------------------------------------------------

readonly GRUB_USER="root"
readonly GRUB_PASSWORD_FILE="/etc/grub.d/01_users"
readonly GRUB_LINUX_FILE="/etc/grub.d/10_linux"

readonly GRUB_CFG_PATH="/boot/grub/grub.cfg"
readonly GRUB_CFG_EXPECTED_MODE="0600"
readonly GRUB_CFG_EXPECTED_OWNER="root:root"

readonly -a GRUB_PASSWORD_PATTERNS=(
    "superuser definition|^set superusers"
    "password hash|^password_pbkdf2"
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
# CIS 1.4.1 — Bootloader password
# ---------------------------------------------------------------------------

audit_grub_password() {
    local audit_fail=0
    local last=$(( ${#GRUB_PASSWORD_PATTERNS[@]} - 1 ))

    _tree_label "Bootloader Password  (CIS 1.4.1)"

    if [[ ! -f "$GRUB_CFG_PATH" ]]; then
        printf "  └─ %-24s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s not found\n" "grub.cfg" "$GRUB_CFG_PATH"
        for entry in "${GRUB_PASSWORD_PATTERNS[@]}"; do
            local desc="${entry%%|*}"
            record_result "1.4.1" "$desc" "FAIL" "grub.cfg not found"
        done
        return 1
    fi

    for i in "${!GRUB_PASSWORD_PATTERNS[@]}"; do
        local entry="${GRUB_PASSWORD_PATTERNS[$i]}"
        local desc="${entry%%|*}"
        local pattern="${entry##*|}"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if grep -q "$pattern" "$GRUB_CFG_PATH"; then
            printf "  %s %-24s  ${C_GREEN}[PASS]${C_RESET} found in grub.cfg\n" "$branch" "$desc"
            record_result "1.4.1" "$desc" "PASS"
            log_debug "$(grep "$pattern" "$GRUB_CFG_PATH")"
        else
            printf "  %s %-24s  ${C_BRIGHT_RED}[FAIL]${C_RESET} MISSING from grub.cfg\n" "$branch" "$desc"
            record_result "1.4.1" "$desc" "FAIL" "not found in grub.cfg"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

remediate_grub_password() {
    print_section_header "REMEDIATION" "Setting GRUB Bootloader Password"

    log_warn "This step requires manual password entry to generate a secure hash."
    log_warn "Enter the password once, press Enter, and then re-enter it"

    local grub_hash
    if ! grub_hash=$(grub-mkpasswd-pbkdf2 --iteration-count=600000 --salt=64 \
            | grep "grub.pbkdf2.sha512" | awk '{print $NF}'); then
        log_error "Failed to generate GRUB password hash."
        return 1
    fi

    if [[ -z "$grub_hash" ]]; then
        log_error "Generated hash is empty. Aborting."
        return 1
    fi

    log_info "Writing $GRUB_PASSWORD_FILE..."

    cat > "$GRUB_PASSWORD_FILE" << OUTER
#!/bin/sh
cat << 'INNER'
set superusers="${GRUB_USER}"
password_pbkdf2 ${GRUB_USER} ${grub_hash}
INNER
OUTER

    chmod 755 "$GRUB_PASSWORD_FILE"
    log_ok "$GRUB_PASSWORD_FILE written successfully."

    if [[ -f "$GRUB_LINUX_FILE" ]]; then
        log_info "Configuring --unrestricted boot in $GRUB_LINUX_FILE..."
        sed -i 's/CLASS="--class gnu-linux --class gnu --class os"/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/' \
            "$GRUB_LINUX_FILE"
    fi

    log_info "Updating GRUB configuration..."
    if update-grub >/dev/null 2>&1; then
        log_ok "GRUB password set and configuration updated."
    else
        log_error "'update-grub' failed."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.4.2 — Bootloader config file access
# ---------------------------------------------------------------------------

audit_grub_cfg_access() {
    local audit_fail=0

    _tree_label "Bootloader Config Access  (CIS 1.4.2)"

    if [[ ! -f "$GRUB_CFG_PATH" ]]; then
        printf "  └─ %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s not found\n" "$GRUB_CFG_PATH" "$GRUB_CFG_PATH"
        record_result "1.4.2" "grub.cfg exists" "FAIL" "file not found"
        return 1
    fi

    local file_stat mode uid gid
    file_stat=$(stat -Lc '%a %u %g' "$GRUB_CFG_PATH" 2>/dev/null)
    read -r mode uid gid <<< "$file_stat"

    if [[ "$uid" -eq 0 && "$gid" -eq 0 ]]; then
        printf "  ├─ %-16s  ${C_GREEN}[PASS]${C_RESET} root:root\n" "ownership"
        record_result "1.4.2" "grub.cfg ownership" "PASS"
    else
        local actual_owner
        actual_owner=$(stat -Lc '%U:%G' "$GRUB_CFG_PATH")
        printf "  ├─ %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s (expected %s)\n" \
            "ownership" "$actual_owner" "$GRUB_CFG_EXPECTED_OWNER"
        record_result "1.4.2" "grub.cfg ownership" "FAIL" "$actual_owner"
        audit_fail=1
    fi

    local mode_ok=false
    case "$mode" in
        0|1|400|500|600) mode_ok=true ;;
        *00)
            local group_other="${mode: -2}"
            [[ "$group_other" == "00" ]] && mode_ok=true
            ;;
    esac

    if [[ "$mode_ok" == "true" ]]; then
        printf "  └─ %-16s  ${C_GREEN}[PASS]${C_RESET} %s (≤ 0600)\n" "permissions" "$mode"
        record_result "1.4.2" "grub.cfg permissions" "PASS"
    else
        printf "  └─ %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s (expected ≤ %s)\n" \
            "permissions" "$mode" "$GRUB_CFG_EXPECTED_MODE"
        record_result "1.4.2" "grub.cfg permissions" "FAIL" "mode=$mode"
        audit_fail=1
    fi

    return "$audit_fail"
}

remediate_grub_cfg_access() {
    print_section_header "REMEDIATION" "Fixing $GRUB_CFG_PATH Access"

    if [[ ! -f "$GRUB_CFG_PATH" ]]; then
        log_error "$GRUB_CFG_PATH does not exist. Cannot fix permissions."
        return 1
    fi

    log_info "Setting ownership to root:root and permissions to 0600 for $GRUB_CFG_PATH..."
    if chown root:root "$GRUB_CFG_PATH" && chmod 0600 "$GRUB_CFG_PATH"; then
        log_ok "Access for $GRUB_CFG_PATH fixed successfully."
    else
        log_error "Failed to fix access for $GRUB_CFG_PATH."
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

    _check_compliance audit_grub_password \
        "Bootloader password and superuser are configured." \
        "Bootloader password or superuser are missing." || global_status=1

    _check_compliance audit_grub_cfg_access \
        "Bootloader config permissions are correct (root:root 0600)." \
        "Bootloader config permissions are insecure." || global_status=1

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

    _apply_remediation audit_grub_password remediate_grub_password \
        "Checking bootloader password configuration..." \
        "Bootloader password already configured." || any_failure=true

    _apply_remediation audit_grub_cfg_access remediate_grub_cfg_access \
        "Checking bootloader config file permissions..." \
        "Bootloader config permissions already correct." || any_failure=true

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

    _check_compliance audit_grub_password \
        "Bootloader password is correctly configured." \
        "Bootloader password remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_grub_cfg_access \
        "Bootloader config permissions are correct." \
        "Bootloader config permissions remediation FAILED." \
        "Verification" || verify_status=1

    print_summary_table

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. System is now compliant."
        return 0
    else
        log_warn "Auto-remediation finished with pending items. Manual review required."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# User interface & main
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section 1.4: Configure Bootloader"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply bootloader configurations."
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
        echo -e "\n${C_BOLD}--- CIS 1.4 Bootloader Hardening — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Set password, fix permissions)" > /dev/tty
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
    print_section_header "CIS 1.4" "Configure Bootloader"
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