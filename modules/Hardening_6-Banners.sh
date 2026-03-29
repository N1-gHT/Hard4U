#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.6: Configure Command Line Warning Banners
#
# Sub-sections covered:
#   1.6.1 Ensure /etc/motd is configured                    (/etc/motd)
#   1.6.2 Ensure /etc/issue is configured                   (/etc/issue)
#   1.6.3 Ensure /etc/issue.net is configured               (/etc/issue.net)
#   1.6.4 Ensure access to /etc/motd is configured          (root:root 0644)
#   1.6.5 Ensure access to /etc/issue is configured         (root:root 0644)
#   1.6.6 Ensure access to /etc/issue.net is configured     (root:root 0644)

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
# Global variables
# ---------------------------------------------------------------------------

OS_ID="$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')"
readonly OS_ID

readonly FORBIDDEN_PATTERN="(\\\v|\\\r|\\\m|\\\s|\b${OS_ID}\b)"

readonly -a BANNER_FILES=("/etc/motd" "/etc/issue" "/etc/issue.net")

readonly -a CIS_CONTENT_IDS=("1.6.1" "1.6.2" "1.6.3")
readonly -a CIS_PERM_IDS=("1.6.4" "1.6.5" "1.6.6")

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
# ---------------------------------------------------------------------------

print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=7 W_DESC=30 W_ST=6

    local S_ID S_DESC S_ST S_FULL
    S_ID=$(  _rep $(( W_ID   + 2 )) '─')
    S_DESC=$(_rep $(( W_DESC + 2 )) '─')
    S_ST=$(  _rep $(( W_ST   + 2 )) '─')
    S_FULL=$(
        _rep $(( W_ID + W_DESC + W_ST + 8 )) '─')
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
# Audit functions
# ---------------------------------------------------------------------------

audit_motd_contents() {
    log_debug "Checking banner content for forbidden patterns..."
    local audit_fail=0
    local last=$(( ${#BANNER_FILES[@]} - 1 ))

    _tree_label "Banner Content  (CIS 1.6.1 – 1.6.3)"

    for i in "${!BANNER_FILES[@]}"; do
        local l_file="${BANNER_FILES[$i]}"
        local cis_id="${CIS_CONTENT_IDS[$i]}"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if [[ ! -e "$l_file" ]]; then
            printf "  %s %-16s  ${C_YELLOW}[SKIP]${C_RESET} File not found\n" "${branch}" "${l_file}"
            log_debug "Skipping $l_file: does not exist."
            continue
        fi

        if grep -Psqi -- "$FORBIDDEN_PATTERN" "$l_file"; then
            printf "  %s %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} Contains forbidden system information\n" "${branch}" "${l_file}"
            record_result "$cis_id" "${l_file} content" "FAIL" "Forbidden content found"
            audit_fail=1
        else
            printf "  %s %-16s  ${C_GREEN}[PASS]${C_RESET} No forbidden content\n" "${branch}" "${l_file}"
            record_result "$cis_id" "${l_file} content" "PASS"
        fi
    done

    return "$audit_fail"
}

audit_banner_access() {
    log_debug "Auditing ownership and permissions for banner files..."
    local audit_fail=0
    local last=$(( ${#BANNER_FILES[@]} - 1 ))

    _tree_label "Banner Permissions  (CIS 1.6.4 – 1.6.6)"

    for i in "${!BANNER_FILES[@]}"; do
        local l_file="${BANNER_FILES[$i]}"
        local cis_id="${CIS_PERM_IDS[$i]}"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if [[ ! -e "$l_file" ]]; then
            printf "  %s %-16s  ${C_YELLOW}[SKIP]${C_RESET} File not found\n" "${branch}" "${l_file}"
            log_debug "Skipping $l_file: does not exist."
            continue
        fi

        local real_file
        if ! real_file=$(readlink -e "$l_file"); then
            printf "  %s %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} Cannot resolve canonical path\n" "${branch}" "${l_file}"
            record_result "$cis_id" "${l_file} permissions" "FAIL" "Cannot resolve path"
            audit_fail=1
            continue
        fi

        log_debug "Checking '$l_file' -> '$real_file'"

        local file_stat uid gid mode
        file_stat=$(stat -Lc '%a %u %g' "$real_file" 2>/dev/null)
        read -r mode uid gid <<< "$file_stat"

        local fail_reasons=()
        [[ "$uid" -ne 0 || "$gid" -ne 0 ]] && \
            fail_reasons+=("owner: $(stat -Lc '%U:%G' "$real_file") (expected root:root)")
        [[ "$mode" != "644" ]] && \
            fail_reasons+=("mode: $mode (expected 644)")

        if [[ "${#fail_reasons[@]}" -eq 0 ]]; then
            printf "  %s %-16s  ${C_GREEN}[PASS]${C_RESET} root:root  644\n" "${branch}" "${l_file}"
            record_result "$cis_id" "${l_file} permissions" "PASS"
        else
            local detail
            detail=$(printf '%s  ' "${fail_reasons[@]}")
            printf "  %s %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s\n" "${branch}" "${l_file}" "${detail}"
            record_result "$cis_id" "${l_file} permissions" "FAIL" "$detail"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

# ---------------------------------------------------------------------------
# Remediation functions
# ---------------------------------------------------------------------------

remediate_motd_contents() {
    log_info "Removing forbidden content from banner files..."

    for l_file in "${BANNER_FILES[@]}"; do
        [[ -e "$l_file" ]] || continue

        if grep -Psqi -- "$FORBIDDEN_PATTERN" "$l_file"; then
            log_info "Sanitizing '$l_file'..."

            if perl -i -pe 'BEGIN { $os = shift(@ARGV) }
                            s/\\v|\\r|\\m|\\s|\b\Q$os\E\b//gi' -- "$OS_ID" "$l_file"; then
                log_ok "'$l_file' sanitized successfully."
            else
                log_error "Failed to sanitize '$l_file'."
                return 1
            fi
        else
            log_debug "'$l_file' is already clean."
        fi
    done

    log_ok "Banner content remediation complete."
    log_info "Reminder: edit /etc/motd, /etc/issue and /etc/issue.net to add your organization's legal banner."
    return 0
}

remediate_banner_access() {
    print_section_header "REMEDIATION" "Fixing Banner File Permissions"
    local any_failure=false

    for l_file in "${BANNER_FILES[@]}"; do
        [[ -e "$l_file" ]] || continue

        local real_file
        if ! real_file=$(readlink -e "$l_file"); then
            log_warn "Cannot resolve canonical path for '$l_file'. Skipping."
            any_failure=true
            continue
        fi

        log_info "Applying root:root / 0644 to '$real_file'..."

        if chown root:root "$real_file" && chmod 0644 "$real_file"; then
            log_ok "Access fixed for '$real_file'."
        else
            log_error "Failed to fix access for '$real_file'."
            any_failure=true
        fi
    done

    [[ "$any_failure" == "true" ]] && return 1 || return 0
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

    _check_compliance audit_motd_contents \
        "Banner content is compliant." \
        "One or more banner files contain forbidden information." || global_status=1

    _check_compliance audit_banner_access \
        "Banner permissions are compliant." \
        "One or more banner files have incorrect permissions or ownership." || global_status=1

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

    _apply_remediation audit_motd_contents remediate_motd_contents \
        "Checking banner content..." \
        "Banner content is already compliant." || any_failure=true

    _apply_remediation audit_banner_access remediate_banner_access \
        "Checking banner file permissions..." \
        "Banner file permissions are already compliant." || any_failure=true

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

    _check_compliance audit_motd_contents \
        "Banner content is now compliant." \
        "Banner content remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_banner_access \
        "Banner permissions are now compliant." \
        "Banner permissions remediation FAILED." \
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
    echo "CIS Benchmark Debian 13 - Section 1.6: Configure Command Line Warning Banners"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply banner hardening configurations."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  SCRIPT_DEBUG=true   Enable debug output on stderr."
    echo "  NO_COLOR=true       Disable ANSI color output (useful for log files"
    echo "                      or when called from an orchestrator)."
}

show_interactive_menu() {
    echo -e "\n${C_BOLD}--- CIS 1.6 Banner Hardening — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply fixes)" > /dev/tty
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
    print_section_header "CIS 1.6" "Configure Command Line Warning Banners"
    log_debug "SCRIPT_DEBUG: ${SCRIPT_DEBUG:-false}"
    log_debug "OS_ID: ${OS_ID}"

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