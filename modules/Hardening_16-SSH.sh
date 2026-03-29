#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.1: Configure SSH Server
#
# Sub-sections covered:
#   5.1.1 - Ensure access to /etc/ssh/sshd_config is configured
#   5.1.2 - Ensure access to SSH private host key files is configured
#   5.1.3 - Ensure access to SSH public host key files is configured
#   5.1.4 - Ensure sshd access is configured
#   5.1.5 - Ensure sshd Banner is configured

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
readonly SSH_PACKAGE="openssh-server"
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
readonly SSH_ALLOWED_GROUP="sudo"
readonly SSH_BANNER_TARGET="/etc/issue.net"

OS_NAME_ID="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
readonly OS_NAME_ID
readonly SSH_FORBIDDEN_REGEX="(\\\v|\\\r|\\\m|\\\s|\b${OS_NAME_ID}\b)"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array
# ---------------------------------------------------------------------------
readonly -a SSH_CHECKS=(
    "5.1.1|_audit_sshd_config_access|_remediate_sshd_config_access|Access to /etc/ssh/sshd_config configured"
    "5.1.2|_audit_ssh_private_keys|_remediate_ssh_private_keys|SSH private host key files access configured"
    "5.1.3|_audit_ssh_public_keys|_remediate_ssh_public_keys|SSH public host key files access configured"
    "5.1.4|_audit_sshd_access_control|_remediate_sshd_access_control|sshd access configured"
    "5.1.5|_audit_sshd_banner|_remediate_sshd_banner|sshd Banner configured"
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

    local W_ID=9 W_DESC=52 W_ST=6
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
        printf "  %s %-54s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-54s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Internal utility functions
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

_get_ssh_private_keys() {
    command -v sshd >/dev/null 2>&1 || return 0
    sshd -T 2>/dev/null | awk '$1=="hostkey" {print $2}'
}

_get_ssh_public_keys() {
    command -v sshd >/dev/null 2>&1 || return 0
    sshd -T 2>/dev/null | awk '$1=="hostkey" {print $2".pub"}'
}

_sshd_get_config() {
    local param="$1"
    sshd -T 2>/dev/null | grep -Pi "^${param}\s+" | awk '{print $2}' | xargs || true
}

_check_path_perms() {
    local path="$1" exp_mode="$2" exp_uid="$3" exp_gid="$4"
    [[ -f "$path" ]] || return 0

    local stat_out
    stat_out=$(stat -Lc '%a %u %g' "$path" 2>/dev/null) || {
        log_debug "stat failed on $path"
        return 1
    }
    local mode uid gid
    read -r mode uid gid <<< "$stat_out"

    if [[ "$mode" != "$exp_mode" || "$uid" != "$exp_uid" || "$gid" != "$exp_gid" ]]; then
        log_debug "Perm mismatch $path: mode=$mode (exp $exp_mode)" \
            "uid=$uid (exp $exp_uid) gid=$gid (exp $exp_gid)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.1.1 — /etc/ssh/sshd_config access
# ---------------------------------------------------------------------------
_audit_sshd_config_access() {
    _is_installed "$SSH_PACKAGE" || return 0

    local fail=0
    _check_path_perms "$SSHD_CONFIG" "600" "0" "0" || fail=1

    if [[ -d "$SSHD_CONFIG_DIR" ]]; then
        while IFS= read -r -d '' f; do
            _check_path_perms "$f" "600" "0" "0" || fail=1
        done < <(find "$SSHD_CONFIG_DIR" -type f -name '*.conf' -print0 2>/dev/null)
    fi
    return "$fail"
}

_remediate_sshd_config_access() {
    _is_installed "$SSH_PACKAGE" || return 0

    log_info "Securing $SSHD_CONFIG..."
    chown root:root "$SSHD_CONFIG"
    chmod 600 "$SSHD_CONFIG"

    if [[ -d "$SSHD_CONFIG_DIR" ]]; then
        log_info "Securing $SSHD_CONFIG_DIR/*.conf..."
        find "$SSHD_CONFIG_DIR" -type f -name '*.conf' \
            -exec chown root:root {} + \
            -exec chmod 600 {} +
    fi
    log_ok "sshd_config permissions secured."
}

# ---------------------------------------------------------------------------
# CIS 5.1.2 — SSH private host key files access
# ---------------------------------------------------------------------------
_audit_ssh_private_keys() {
    _is_installed "$SSH_PACKAGE" || return 0

    local fail=0
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        _check_path_perms "$key" "600" "0" "0" || fail=1
    done < <(_get_ssh_private_keys)
    return "$fail"
}

_remediate_ssh_private_keys() {
    _is_installed "$SSH_PACKAGE" || return 0

    local any_failure=false
    while IFS= read -r key; do
        [[ -n "$key" && -f "$key" ]] || continue
        log_info "Securing private key: $key"
        if chown root:root "$key" && chmod 600 "$key"; then
            log_debug "Secured $key"
        else
            log_error "Failed to secure $key"
            any_failure=true
        fi
    done < <(_get_ssh_private_keys)

    [[ "$any_failure" == "false" ]]
}

# ---------------------------------------------------------------------------
# CIS 5.1.3 — SSH public host key files access
# ---------------------------------------------------------------------------
_audit_ssh_public_keys() {
    _is_installed "$SSH_PACKAGE" || return 0

    local fail=0
    while IFS= read -r key; do
        [[ -n "$key" && -f "$key" ]] || continue
        _check_path_perms "$key" "644" "0" "0" || fail=1
    done < <(_get_ssh_public_keys)
    return "$fail"
}

_remediate_ssh_public_keys() {
    _is_installed "$SSH_PACKAGE" || return 0

    local any_failure=false
    while IFS= read -r key; do
        [[ -n "$key" && -f "$key" ]] || continue
        log_info "Securing public key: $key"
        if chown root:root "$key" && chmod 644 "$key"; then
            log_debug "Secured $key"
        else
            log_error "Failed to secure $key"
            any_failure=true
        fi
    done < <(_get_ssh_public_keys)

    [[ "$any_failure" == "false" ]]
}

# ---------------------------------------------------------------------------
# CIS 5.1.4 — sshd access control (AllowUsers / AllowGroups / DenyUsers / DenyGroups)
# ---------------------------------------------------------------------------
_audit_sshd_access_control() {
    _is_installed "$SSH_PACKAGE" || return 0

    if sshd -T 2>/dev/null | grep -Piq '^\h*(allow|deny)(users|groups)\h+\H+'; then
        return 0
    fi
    log_debug "No AllowUsers/AllowGroups/DenyUsers/DenyGroups defined in sshd -T output"
    return 1
}

_remediate_sshd_access_control() {
    _is_installed "$SSH_PACKAGE" || return 0

    log_info "No SSH access control detected."

    if ! grep -qi "^[[:space:]]*AllowGroups" "$SSHD_CONFIG"; then
        log_info "Adding 'AllowGroups ${SSH_ALLOWED_GROUP}' to $SSHD_CONFIG..."
        sed -i "1iAllowGroups ${SSH_ALLOWED_GROUP}" "$SSHD_CONFIG"
        log_ok "Access restricted to group '${SSH_ALLOWED_GROUP}'."
    else
        log_info "AllowGroups directive exists — check $SSHD_CONFIG for empty or incorrect value."
    fi

    systemctl reload sshd 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# CIS 5.1.5 — sshd Banner
# ---------------------------------------------------------------------------
_audit_sshd_banner() {
    _is_installed "$SSH_PACKAGE" || return 0

    local banner_path
    banner_path=$(_sshd_get_config "banner")

    if [[ -z "$banner_path" || "$banner_path" == "none" ]]; then
        log_debug "SSH Banner is not configured (banner=none)"
        return 1
    fi

    if [[ ! -f "$banner_path" ]]; then
        log_debug "SSH Banner file '$banner_path' does not exist"
        return 1
    fi

    if grep -Psiq "$SSH_FORBIDDEN_REGEX" "$banner_path" 2>/dev/null; then
        log_debug "SSH Banner contains forbidden system information"
        return 1
    fi

    return 0
}

_remediate_sshd_banner() {
    _is_installed "$SSH_PACKAGE" || return 0

    if grep -qi "^[[:space:]]*Banner" "$SSHD_CONFIG" 2>/dev/null; then
        log_info "Updating Banner directive to point to $SSH_BANNER_TARGET..."
        sed -i "s|^#\?[[:space:]]*Banner.*|Banner ${SSH_BANNER_TARGET}|" "$SSHD_CONFIG"
    else
        log_info "Adding Banner directive to $SSHD_CONFIG..."
        echo "Banner ${SSH_BANNER_TARGET}" >> "$SSHD_CONFIG"
    fi

    log_info "Writing compliant banner to $SSH_BANNER_TARGET..."
    printf 'Authorized users only. All activity may be monitored and reported.\n' \
        > "$SSH_BANNER_TARGET"
    chown root:root "$SSH_BANNER_TARGET"
    chmod 644 "$SSH_BANNER_TARGET"

    systemctl reload sshd 2>/dev/null || true
    log_ok "SSH Banner configured."
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer — called in audit and verify step.
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#SSH_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${SSH_CHECKS[@]}"; do
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

    _run_audit_checks "SSH Server  (CIS 5.1.1 – 5.1.5)" || global_status=1

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

    for entry in "${SSH_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.1.1 – 5.1.5)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.1: Configure SSH Server"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply SSH server hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 5.1 SSH Server — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply SSH hardening)" > /dev/tty
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
    print_section_header "CIS 5.1" "Configure SSH Server"
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