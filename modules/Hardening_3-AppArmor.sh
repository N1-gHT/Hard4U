#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.3.1: Configure AppArmor
#
# Sub-sections covered:
#   1.3.1.1 - Ensure AppArmor packages are installed
#   1.3.1.2 - Ensure AppArmor is enabled (bootloader + service)
#   1.3.1.3 - Ensure all AppArmor profiles are enforcing
#   1.3.1.4 - Ensure apparmor_restrict_unprivileged_unconfined is enabled

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

export DEBIAN_FRONTEND=noninteractive

readonly -a REQUIRED_PKGS=("apparmor" "apparmor-utils")

readonly -a GRUB_REQUIRED_PARAMS=("apparmor=1" "security=apparmor")
readonly    GRUB_CFG_FILE="/boot/grub/grub.cfg"
readonly    GRUB_DEFAULT_FILE="/etc/default/grub"

declare -rA SERVICE_CHECKS=(
    ["is-enabled"]="enabled at boot"
    ["is-active"]="currently running"
)

readonly SYSCTL_PARAM="kernel.apparmor_restrict_unprivileged_unconfined"
readonly SYSCTL_CONF_FILE="/etc/sysctl.d/60-apparmor_restrict.conf"

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
# Column inner widths: W_ID=7  W_DESC=36  W_ST=6
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=7 W_DESC=36 W_ST=6

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
# CIS 1.3.1.1 — AppArmor packages
# ---------------------------------------------------------------------------

audit_apparmor_packages() {
    local audit_fail=0
    local last=$(( ${#REQUIRED_PKGS[@]} - 1 ))

    _tree_label "AppArmor Packages  (CIS 1.3.1.1)"

    for i in "${!REQUIRED_PKGS[@]}"; do
        local pkg="${REQUIRED_PKGS[$i]}"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            printf "  %s %-18s  ${C_GREEN}[PASS]${C_RESET} installed\n" "$branch" "$pkg"
            record_result "1.3.1.1" "pkg: $pkg" "PASS"
        else
            printf "  %s %-18s  ${C_BRIGHT_RED}[FAIL]${C_RESET} NOT installed\n" "$branch" "$pkg"
            record_result "1.3.1.1" "pkg: $pkg" "FAIL" "not installed"
            audit_fail=1
        fi
    done

    if [[ -d "/sys/kernel/security/apparmor" ]]; then
        log_debug "AppArmor kernel module is active (/sys/kernel/security/apparmor exists)."
    else
        log_warn "AppArmor does not appear active in the running kernel — check GRUB parameters."
        local kconf
        kconf="/boot/config-$(uname -r)"
        if [[ -f "$kconf" ]]; then
            if grep -q "CONFIG_SECURITY_APPARMOR=y" "$kconf"; then
                log_warn "  Kernel has AppArmor built-in but it may be disabled via boot parameters."
            else
                log_warn "  Kernel config does not have AppArmor built in."
            fi
        fi
    fi

    return "$audit_fail"
}

install_apparmor_packages() {
    local needs_install=false

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            needs_install=true
            break
        fi
    done

    if [[ "$needs_install" == "false" ]]; then
        log_ok "All required AppArmor packages are already installed."
        return 0
    fi

    print_section_header "REMEDIATION" "AppArmor Packages Installation"
    log_info "Running apt-get update..."

    if ! apt-get update -q; then
        log_warn "apt-get update encountered issues. Attempting to proceed..."
    fi

    log_info "Installing: ${REQUIRED_PKGS[*]}..."

    if apt-get install -y -q "${REQUIRED_PKGS[@]}"; then
        log_ok "AppArmor packages installed successfully."
    else
        log_error "Failed to install AppArmor packages."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.3.1.2 — AppArmor enabled (bootloader parameters + service)
# The CIS benchmark treats GRUB config and service state as one combined check.
# ---------------------------------------------------------------------------

audit_apparmor_enabled() {
    local audit_fail=0

    _tree_label "AppArmor Enabled — GRUB + Service  (CIS 1.3.1.2)"

    if [[ ! -f "$GRUB_CFG_FILE" ]]; then
        log_warn "File '$GRUB_CFG_FILE' not found. Cannot verify GRUB parameters."
        for param in "${GRUB_REQUIRED_PARAMS[@]}"; do
            printf "  ├─ %-22s  ${C_BRIGHT_RED}[FAIL]${C_RESET} grub.cfg not found\n" "grub: $param"
            record_result "1.3.1.2" "grub: $param" "FAIL" "grub.cfg not found"
        done
        audit_fail=1
    else
        for param in "${GRUB_REQUIRED_PARAMS[@]}"; do
            if grep -qE "^\s*linux\s+.*\b${param}\b" "$GRUB_CFG_FILE"; then
                printf "  ├─ %-22s  ${C_GREEN}[PASS]${C_RESET} found in grub.cfg\n" "grub: $param"
                record_result "1.3.1.2" "grub: $param" "PASS"
            else
                printf "  ├─ %-22s  ${C_BRIGHT_RED}[FAIL]${C_RESET} MISSING from grub.cfg\n" "grub: $param"
                record_result "1.3.1.2" "grub: $param" "FAIL" "missing"
                audit_fail=1
            fi
        done
    fi

    local -a svc_checks=("is-enabled" "is-active")
    local last=$(( ${#svc_checks[@]} - 1 ))

    for i in "${!svc_checks[@]}"; do
        local check="${svc_checks[$i]}"
        local desc="${SERVICE_CHECKS[$check]}"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if systemctl "$check" apparmor &>/dev/null; then
            printf "  %s %-22s  ${C_GREEN}[PASS]${C_RESET} %s\n" "$branch" "service: $check" "$desc"
            record_result "1.3.1.2" "service: $check" "PASS"
        else
            printf "  %s %-22s  ${C_BRIGHT_RED}[FAIL]${C_RESET} NOT %s\n" "$branch" "service: $check" "$desc"
            record_result "1.3.1.2" "service: $check" "FAIL" "not $desc"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

_remediate_apparmor_enabled() {
    local any_failure=false
    local reboot_required=false

    log_info "Checking GRUB configuration..."
    if ! audit_apparmor_enabled >/dev/null 2>&1; then
        if _remediate_grub_sequence; then
            log_ok "GRUB updated successfully."
            reboot_required=true
        else
            log_error "GRUB remediation failed."
            any_failure=true
        fi
    else
        log_ok "GRUB is already correctly configured."
    fi

    enable_apparmor_service || {
        log_warn "Service configuration encountered issues (reboot may be required)."
        any_failure=true
    }

    [[ "$reboot_required" == "true" ]] && REBOOT_REQUIRED=true

    [[ "$any_failure" == "false" ]]
}

configure_grub_for_apparmor() {
    local params_to_add=()
    local current_cmdline=""
    local backup_file
    backup_file="${GRUB_DEFAULT_FILE}.bak_$(date +%Y%m%d_%H%M%S)"

    if [[ ! -f "$GRUB_DEFAULT_FILE" ]]; then
        log_error "File '$GRUB_DEFAULT_FILE' not found. Cannot configure GRUB."
        return 1
    fi

    log_info "Creating backup: $backup_file..."
    if ! cp -p "$GRUB_DEFAULT_FILE" "$backup_file"; then
        log_warn "Failed to create backup. Aborting for safety."
        return 1
    fi
# shellcheck source=/dev/null
    if current_cmdline=$(source "$GRUB_DEFAULT_FILE" && echo "${GRUB_CMDLINE_LINUX:-}"); then
        log_debug "Current GRUB_CMDLINE_LINUX: '$current_cmdline'"
    else
        log_warn "Could not source '$GRUB_DEFAULT_FILE'. Assuming GRUB_CMDLINE_LINUX is empty."
        current_cmdline=""
    fi

    for param in "${GRUB_REQUIRED_PARAMS[@]}"; do
        [[ " $current_cmdline " =~ \ ${param}\  ]] || params_to_add+=("$param")
    done

    if [[ ${#params_to_add[@]} -eq 0 ]]; then
        log_ok "All required AppArmor parameters already present in '$GRUB_DEFAULT_FILE'."
        return 0
    fi

    log_info "Missing parameters: ${params_to_add[*]}"

    local new_cmdline
    new_cmdline="$(echo "${current_cmdline} ${params_to_add[*]}" | tr -s ' ' | sed 's/^ //')"

    log_info "Updating '$GRUB_DEFAULT_FILE'..."

    local sed_result=0
    if grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_DEFAULT_FILE"; then
        if ! sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${new_cmdline}\"|" \
                "$GRUB_DEFAULT_FILE"; then
            sed_result=1
        fi
    else
        if ! { echo ""; echo "GRUB_CMDLINE_LINUX=\"${new_cmdline}\""; } >> "$GRUB_DEFAULT_FILE"; then
            sed_result=1
        fi
    fi

    if [[ $sed_result -ne 0 ]]; then
        log_error "Failed to write to '$GRUB_DEFAULT_FILE'. Restoring backup..."
        cp "$backup_file" "$GRUB_DEFAULT_FILE"
        return 1
    fi

    log_ok "GRUB_CMDLINE_LINUX updated successfully."
}

update_grub_config() {
    log_info "Regenerating GRUB configuration..."

    if command -v update-grub &>/dev/null; then
        if update-grub >/dev/null 2>&1; then
            log_ok "GRUB configuration updated via 'update-grub'."
            return 0
        else
            log_error "'update-grub' failed."
            return 1
        fi
    elif command -v grub-mkconfig &>/dev/null; then
        log_info "'update-grub' not found. Falling back to 'grub-mkconfig'..."
        if grub-mkconfig -o "$GRUB_CFG_FILE" >/dev/null 2>&1; then
            log_ok "GRUB configuration updated via 'grub-mkconfig'."
            return 0
        else
            log_error "'grub-mkconfig' failed."
            return 1
        fi
    else
        log_critical "Neither 'update-grub' nor 'grub-mkconfig' found."
    fi
}

_remediate_grub_sequence() {
    configure_grub_for_apparmor || return 1
    update_grub_config          || return 1
}

enable_apparmor_service() {
    log_info "Configuring AppArmor service..."
    local success=true

    if systemctl is-enabled apparmor 2>&1 | grep -q "masked"; then
        log_info "Unmasking AppArmor service..."
        systemctl unmask apparmor
    fi

    if systemctl is-enabled apparmor &>/dev/null; then
        log_ok "Service 'apparmor' is already enabled."
    else
        log_info "Enabling 'apparmor' service..."
        if systemctl enable apparmor &>/dev/null; then
            log_ok "Service 'apparmor' enabled successfully."
        else
            log_error "Failed to enable 'apparmor' service."
            success=false
        fi
    fi

    if systemctl is-active apparmor &>/dev/null; then
        log_ok "Service 'apparmor' is already running."
    else
        log_info "Starting 'apparmor' service..."
        if systemctl start apparmor &>/dev/null; then
            log_ok "Service 'apparmor' started successfully."
        else
            log_warn "Could not start 'apparmor' immediately — a reboot may be required."
        fi
    fi

    [[ "$success" == "true" ]]
}

# ---------------------------------------------------------------------------
# CIS 1.3.1.3 — AppArmor profiles enforcement
# ---------------------------------------------------------------------------

audit_apparmor_profiles() {
    local audit_fail=0

    _tree_label "AppArmor Profiles  (CIS 1.3.1.3)"

    if ! command -v aa-status &>/dev/null; then
        printf "  └─ %-18s  ${C_BRIGHT_RED}[FAIL]${C_RESET} 'aa-status' not found (install apparmor-utils)\n" "aa-status"
        record_result "1.3.1.3" "profiles: aa-status available" "FAIL" "command not found"
        return 1
    fi

    local status_output
    if ! status_output=$(aa-status --verbose 2>&1); then
        printf "  └─ %-18s  ${C_BRIGHT_RED}[FAIL]${C_RESET} aa-status returned an error\n" "aa-status"
        record_result "1.3.1.3" "profiles: aa-status" "FAIL" "command error"
        return 1
    fi

    log_debug "Raw aa-status output:\n$status_output"

    read -r prof_loaded prof_enforce prof_complain \
             proc_defined proc_enforce proc_complain proc_unconfined \
        <<< "$(awk '
            /profiles are loaded/     { loaded=$1 }
            /profiles are in enforce/ { enf=$1 }
            /profiles are in complain/{ comp=$1 }
            /processes have profiles/ { p_def=$1 }
            /processes are in enforce/{ p_enf=$1 }
            /processes are in complain/{ p_comp=$1 }
            /processes are unconfined/ { p_unc=$1 }
            END { print loaded+0, enf+0, comp+0, p_def+0, p_enf+0, p_comp+0, p_unc+0 }
        ' <<< "$status_output")"

    if [[ "$prof_loaded" -gt 0 ]]; then
        printf "  ├─ %-18s  ${C_GREEN}[PASS]${C_RESET} %s profiles loaded\n" "profiles loaded" "$prof_loaded"
        record_result "1.3.1.3" "profiles: loaded" "PASS" "$prof_loaded loaded"
    else
        printf "  ├─ %-18s  ${C_BRIGHT_RED}[FAIL]${C_RESET} no profiles loaded\n" "profiles loaded"
        record_result "1.3.1.3" "profiles: loaded" "FAIL" "0 profiles"
        audit_fail=1
    fi

    if [[ "$prof_complain" -eq 0 ]]; then
        printf "  ├─ %-18s  ${C_GREEN}[PASS]${C_RESET} %s enforcing, 0 in complain\n" "profiles enforce" "$prof_enforce"
        record_result "1.3.1.3" "profiles: all enforcing" "PASS"
    else
        printf "  ├─ %-18s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s in complain mode (expected 0)\n" "profiles complain" "$prof_complain"
        record_result "1.3.1.3" "profiles: all enforcing" "FAIL" "$prof_complain in complain"
        audit_fail=1
    fi

    printf "  ├─ %-18s  ${C_DIM}[INFO]${C_RESET} %s with profiles (%s enforce, %s complain)\n" \
        "processes" "$proc_defined" "$proc_enforce" "$proc_complain"

    if [[ "$proc_unconfined" -gt 0 ]]; then
        printf "  └─ %-18s  ${C_YELLOW}[WARN]${C_RESET} %s processes unconfined but have a profile\n" \
            "procs unconfined" "$proc_unconfined"
        record_result "1.3.1.3" "processes: unconfined w/ profile" "FAIL" "$proc_unconfined processes"
        audit_fail=1
    else
        printf "  └─ %-18s  ${C_GREEN}[PASS]${C_RESET} 0 unconfined processes with a profile\n" "procs unconfined"
        record_result "1.3.1.3" "processes: unconfined w/ profile" "PASS"
    fi

    return "$audit_fail"
}

enforce_all_apparmor_profiles() {
    print_section_header "REMEDIATION" "Enforcing AppArmor Profiles"

    if ! command -v aa-enforce &>/dev/null; then
        log_error "'aa-enforce' not found. Install 'apparmor-utils'."
        return 1
    fi

    log_info "Switching all profiles to ENFORCE mode..."
    log_warn "Note: enforcing may break applications with immature profiles."
    log_warn "Consider running in 'complain' mode first and reviewing logs with 'aa-logprof'."

    local total=0 success=0 fail=0

    while IFS= read -r -d $'\0' profile_file; do
        local profile_name
        profile_name=$(basename "$profile_file")
        [[ "$profile_name" == "README" ]] && continue

        (( ++total ))
        local output
        if output=$(aa-enforce "$profile_file" 2>&1); then
            log_ok "  $profile_name → ENFORCE"
            (( ++success ))
        else
            log_warn "  $profile_name → FAILED: $output"
            (( ++fail ))
        fi
    done < <(find /etc/apparmor.d/ -maxdepth 1 -type f -not -name ".*" -print0)

    echo ""
    if [[ "$total" -eq 0 ]]; then
        log_warn "No profiles found in /etc/apparmor.d/."
    else
        log_info "Processed $total profiles — success: $success  failed: $fail"
    fi

    command -v aa-logprof &>/dev/null && \
        log_info "Tip: use 'aa-logprof' to refine blocked application profiles."
}

# ---------------------------------------------------------------------------
# CIS 1.3.1.4 — Unprivileged unconfined restriction (sysctl)
# ---------------------------------------------------------------------------

audit_unprivileged_restriction() {
    local audit_fail=0

    _tree_label "Unprivileged Restriction  (CIS 1.3.1.4)"

    local current_val
    current_val=$(sysctl -n "$SYSCTL_PARAM" 2>/dev/null || echo "not_found")

    if [[ "$current_val" == "1" ]]; then
        printf "  ├─ %-16s  ${C_GREEN}[PASS]${C_RESET} runtime value = 1\n" "sysctl runtime"
        record_result "1.3.1.4" "sysctl: runtime value" "PASS"
    else
        printf "  ├─ %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} runtime value = '%s' (expected 1)\n" \
            "sysctl runtime" "$current_val"
        record_result "1.3.1.4" "sysctl: runtime value" "FAIL" "value=$current_val"
        audit_fail=1
    fi

    local persistence_found
    persistence_found=$(grep -Prs "^\s*${SYSCTL_PARAM}\s*=\s*1\b" \
        /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null || true)

    if [[ -n "$persistence_found" ]]; then
        printf "  └─ %-16s  ${C_GREEN}[PASS]${C_RESET} configured in sysctl.d\n" "sysctl persist"
        log_debug "Found in:\n$persistence_found"
        record_result "1.3.1.4" "sysctl: persistence" "PASS"
    else
        printf "  └─ %-16s  ${C_BRIGHT_RED}[FAIL]${C_RESET} NOT configured in sysctl.d\n" "sysctl persist"
        record_result "1.3.1.4" "sysctl: persistence" "FAIL" "not persisted"
        audit_fail=1
    fi

    return "$audit_fail"
}

remediate_unprivileged_restriction() {
    log_info "Applying remediation for $SYSCTL_PARAM..."

    log_info "Writing $SYSCTL_CONF_FILE..."
    if ! printf '%s = 1\n' "$SYSCTL_PARAM" > "$SYSCTL_CONF_FILE"; then
        log_error "Failed to write to $SYSCTL_CONF_FILE."
        return 1
    fi

    log_info "Applying runtime value via sysctl -w..."
    if ! sysctl -w "$SYSCTL_PARAM=1" >/dev/null; then
        log_error "Failed to set $SYSCTL_PARAM via sysctl -w."
        return 1
    fi

    log_info "Refreshing all sysctl settings..."
    sysctl --system >/dev/null

    log_ok "$SYSCTL_PARAM set to 1 (runtime + persistent)."
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

    _check_compliance audit_apparmor_packages \
        "All AppArmor packages are installed." \
        "One or more AppArmor packages are missing." || global_status=1

    _check_compliance audit_apparmor_enabled \
        "AppArmor is enabled (GRUB + service)." \
        "AppArmor is not fully enabled (GRUB or service issue)." || global_status=1

    _check_compliance audit_apparmor_profiles \
        "All AppArmor profiles are enforcing." \
        "One or more profiles are in complain mode or unconfined." || global_status=1

    _check_compliance audit_unprivileged_restriction \
        "Unprivileged unconfined restriction is active." \
        "Unprivileged unconfined restriction is not active." || global_status=1

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
    REBOOT_REQUIRED=false

    _apply_remediation audit_apparmor_packages install_apparmor_packages \
        "Checking AppArmor packages..." \
        "AppArmor packages already installed." || any_failure=true

    _apply_remediation audit_apparmor_enabled _remediate_apparmor_enabled \
        "Checking AppArmor enabled state (GRUB + service)..." \
        "AppArmor already enabled." || any_failure=true

    enforce_all_apparmor_profiles || any_failure=true

    _apply_remediation audit_unprivileged_restriction remediate_unprivileged_restriction \
        "Checking unprivileged restriction..." \
        "Unprivileged restriction already active." || any_failure=true

    echo ""
    if [[ "${REBOOT_REQUIRED:-false}" == "true" ]]; then
        log_warn "A SYSTEM REBOOT IS REQUIRED to apply GRUB/kernel parameter changes."
    fi

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

    _check_compliance audit_apparmor_packages \
        "Packages compliant." \
        "Packages still missing." \
        "Verification" || verify_status=1

    _check_compliance audit_apparmor_enabled \
        "AppArmor enabled (GRUB + service)." \
        "AppArmor not fully enabled (reboot likely required)." \
        "Verification" || verify_status=1

    _check_compliance audit_apparmor_profiles \
        "All profiles are enforcing." \
        "Profile enforcement still pending." \
        "Verification" || verify_status=1

    _check_compliance audit_unprivileged_restriction \
        "Unprivileged restriction is active." \
        "Unprivileged restriction still inactive." \
        "Verification" || verify_status=1

    print_summary_table

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. System is now compliant."
        return 0
    else
        log_warn "Auto-remediation finished with pending items (reboot may be required)."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# User interface & main
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section 1.3.1: Configure AppArmor"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply AppArmor configurations (packages, GRUB, profiles, sysctl)."
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
    echo -e "\n${C_BOLD}--- CIS 1.3.1 AppArmor Hardening — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Install packages, configure GRUB, enforce profiles)" > /dev/tty
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
    print_section_header "CIS 1.3.1" "Configure AppArmor"
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