#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 3.1 & 3.2: Network Devices and Kernel Modules
#
# Sub-sections covered:
#   3.1.1 - Ensure IPv6 status is identified (Manual)
#   3.1.2 - Ensure wireless interfaces are not available
#   3.1.3 - Ensure bluetooth services are not in use
#   3.2.1 - Ensure atm kernel module is not available
#   3.2.2 - Ensure can kernel module is not available
#   3.2.3 - Ensure dccp kernel module is not available
#   3.2.4 - Ensure rds kernel module is not available
#   3.2.5 - Ensure sctp kernel module is not available
#   3.2.6 - Ensure tipc kernel module is not available

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

readonly DISABLE_IPV6="false"
readonly SYSCTL_IPV6_CONF="/etc/sysctl.d/60-ipv6-disable.conf"

readonly WIRELESS_BLACKLIST_CONF="/etc/modprobe.d/cis-disable-wireless.conf"
WIRELESS_MODULES_DIR="/lib/modules/$(uname -r)/kernel/drivers/net/wireless"
readonly WIRELESS_MODULES_DIR

readonly BLUETOOTH_PKG="bluez"
readonly BLUETOOTH_SVC="bluetooth.service"

readonly NET_MODULES_BLACKLIST_CONF="/etc/modprobe.d/cis-disable-net-protocols.conf"

# ---------------------------------------------------------------------------
# DATA-DRIVEN arrays
# ---------------------------------------------------------------------------
readonly -a SECTION_CHECKS=(
    "3.1.2|_audit_wireless_interfaces|_remediate_wireless_interfaces|Wireless interfaces not available"
    "3.1.3|_audit_bluetooth|_remediate_bluetooth|Bluetooth services not in use"
)

readonly -a NET_MODULE_CHECKS=(
    "3.2.1|atm|atm kernel module not available"
    "3.2.2|can|can kernel module not available"
    "3.2.3|dccp|dccp kernel module not available"
    "3.2.4|rds|rds kernel module not available"
    "3.2.5|sctp|sctp kernel module not available"
    "3.2.6|tipc|tipc kernel module not available"
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
        if   [[ "$status" == "PASS" ]]; then (( ++pass_count ))
        elif [[ "$status" != "INFO" ]]; then (( ++fail_count ))
        fi
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
        [[ "$st" == "INFO" ]] && row_color="${C_DIM}"
        printf "  ${row_color}│ %-*s │ %-*s │ %-*s │${C_RESET}\n" \
            "$W_ID" "${_RESULT_IDS[$i]}" \
            "$W_DESC" "${_RESULT_DESCS[$i]}" \
            "$W_ST" "$st"
    done

    echo -e "  ├${S_FULL}┤"
    local summary_color="${C_GREEN}"
    [[ $fail_count -gt 0 ]] && summary_color="${C_YELLOW}"
    local info_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        [[ "$status" == "INFO" ]] && (( ++info_count ))
    done
    local counted=$(( total - info_count ))
    printf "  ${summary_color}│ %-*s│${C_RESET}\n" "$W_SUMMARY" \
        " ${pass_count}/${counted} checks -- PASS: ${pass_count}  FAIL: ${fail_count}"
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

_audit_tree_row_manual() {
    local cis_id="$1" desc="$2" branch="$3" detail="$4"
    printf "  %s %-48s  " "$branch" "$desc"
    echo -e "${C_DIM}[INFO]${C_RESET}"
    log_info "  ${detail}"
    record_result "$cis_id" "$desc" "INFO"
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

# ---------------------------------------------------------------------------
# CIS 3.1.1 — IPv6 status identified (Manual)
# ---------------------------------------------------------------------------

_get_ipv6_state() {
    if grep -Pqs -- '^\h*1\b' /sys/module/ipv6/parameters/disable 2>/dev/null; then
        echo "disabled"; return 0
    fi
    local all_disabled default_disabled
    all_disabled=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)
    default_disabled=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo 0)
    if [[ "$all_disabled" -eq 1 && "$default_disabled" -eq 1 ]]; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

_remediate_ipv6_status() {
    if [[ "$DISABLE_IPV6" == "true" ]]; then
        log_info "Disabling IPv6 via sysctl..."
        {
            printf 'net.ipv6.conf.all.disable_ipv6 = 1\n'
            printf 'net.ipv6.conf.default.disable_ipv6 = 1\n'
        } > "$SYSCTL_IPV6_CONF"
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        sysctl --system >/dev/null 2>&1
        log_ok "IPv6 disabled via sysctl."
    else
        log_info "Ensuring IPv6 is enabled (removing disable config if present)..."
        [[ -f "$SYSCTL_IPV6_CONF" ]] && rm -f "$SYSCTL_IPV6_CONF"
        sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null
        sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null
        log_ok "IPv6 enabled."
    fi
}

# ---------------------------------------------------------------------------
# CIS 3.1.2 — Wireless interfaces not available
# ---------------------------------------------------------------------------

_audit_wireless_interfaces() {
    local fail=0

    while IFS= read -r dev_path; do
        local driver_link="${dev_path%/wireless}/device/driver/module"
        if [[ -e "$driver_link" ]]; then
            local driver_name
            driver_name=$(basename "$(readlink -f "$driver_link")")
            if lsmod | grep -q "^${driver_name}\b"; then
                log_debug "Wireless driver loaded and active: $driver_name"
                fail=1
            fi
        fi
    done < <(find /sys/class/net/ -maxdepth 3 -type d -name wireless 2>/dev/null)

    if [[ "$fail" -eq 1 && ! -s "$WIRELESS_BLACKLIST_CONF" ]]; then
        log_debug "Wireless interfaces active and no blacklist config present"
        return 1
    fi

    return "$fail"
}

_remediate_wireless_interfaces() {
    if [[ ! -d "$WIRELESS_MODULES_DIR" ]]; then
        log_info "No wireless kernel modules directory found. Nothing to disable."
        return 0
    fi

    log_info "Generating blacklist for all wireless modules in $WIRELESS_MODULES_DIR..."
    : > "$WIRELESS_BLACKLIST_CONF"

    while IFS= read -r ko_file; do
        local mod_name
        mod_name=$(basename "$ko_file")
        mod_name="${mod_name%.ko.zst}"
        mod_name="${mod_name%.ko.xz}"
        mod_name="${mod_name%.ko}"
        printf 'install %s /bin/false\nblacklist %s\n\n' "$mod_name" "$mod_name"
    done < <(find "$WIRELESS_MODULES_DIR" -name '*.ko*' 2>/dev/null) \
        >> "$WIRELESS_BLACKLIST_CONF"

    if [[ ! -s "$WIRELESS_BLACKLIST_CONF" ]]; then
        log_error "Failed to generate wireless blacklist — no modules found."
        return 1
    fi

    log_ok "Blacklist written to $WIRELESS_BLACKLIST_CONF."

    log_info "Unloading active wireless modules..."
    while IFS= read -r dev_path; do
        local driver_link="${dev_path%/wireless}/device/driver/module"
        if [[ -e "$driver_link" ]]; then
            local driver_name
            driver_name=$(basename "$(readlink -f "$driver_link")")
            log_info "Unloading module: $driver_name"
            modprobe -r "$driver_name" 2>/dev/null || true
            ip link set "$(basename "${dev_path%/wireless}")" down 2>/dev/null || true
        fi
    done < <(find /sys/class/net/ -maxdepth 3 -type d -name wireless 2>/dev/null)

    log_info "Updating module dependencies..."
    depmod -a
}

# ---------------------------------------------------------------------------
# CIS 3.1.3 — Bluetooth services not in use
# ---------------------------------------------------------------------------

_audit_bluetooth() {
    _is_installed "$BLUETOOTH_PKG" || return 0

    local fail=0
    if _is_service_enabled "$BLUETOOTH_SVC"; then
        log_debug "$BLUETOOTH_SVC is enabled"
        fail=1
    fi
    if _is_service_active "$BLUETOOTH_SVC"; then
        log_debug "$BLUETOOTH_SVC is active"
        fail=1
    fi
    return "$fail"
}

_remediate_bluetooth() {
    _is_installed "$BLUETOOTH_PKG" || return 0

    log_info "Stopping and masking $BLUETOOTH_SVC..."
    systemctl stop "$BLUETOOTH_SVC" 2>/dev/null || true
    systemctl mask "$BLUETOOTH_SVC" 2>/dev/null || true

    log_info "Attempting to purge $BLUETOOTH_PKG..."
    if apt-get purge -y "$BLUETOOTH_PKG" >/dev/null 2>&1; then
        log_ok "$BLUETOOTH_PKG purged successfully."
        apt-get autoremove -y >/dev/null 2>&1 || true
    else
        log_warn "Could not purge $BLUETOOTH_PKG — service remains masked."
    fi
}

# ---------------------------------------------------------------------------
# CIS 3.2.1–3.2.6 — Network kernel modules not available
# ---------------------------------------------------------------------------

_audit_module_disabled() {
    local module_name="$1"

    if lsmod | grep -q "^${module_name}\b"; then
        log_debug "Module '$module_name' is currently loaded"
        return 1
    fi

    local check_load
    if ! check_load=$(modprobe -n -v "$module_name" 2>&1); then
        log_debug "Module '$module_name' not found in kernel (compliant)"
        return 0
    fi

    if echo "$check_load" | grep -qE "install[[:space:]]+/bin/(true|false)"; then
        return 0
    fi

    log_debug "Module '$module_name' is loadable (non-compliant)"
    return 1
}

_remediate_net_modules() {
    log_info "Writing blacklist for network protocol modules to $NET_MODULES_BLACKLIST_CONF..."
    : > "$NET_MODULES_BLACKLIST_CONF"

    for entry in "${NET_MODULE_CHECKS[@]}"; do
        local cis_id module desc
        IFS='|' read -r cis_id module desc <<< "$entry"
        printf 'install %s /bin/false\nblacklist %s\n\n' "$module" "$module" \
            >> "$NET_MODULES_BLACKLIST_CONF"
        if lsmod | grep -q "^${module}\b"; then
            log_info "Unloading module: $module"
            modprobe -r "$module" 2>/dev/null \
                || log_warn "Could not unload $module (may be in use)"
        fi
    done

    log_ok "Blacklist written to $NET_MODULES_BLACKLIST_CONF."
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows=$(( 1 + ${#SECTION_CHECKS[@]} + ${#NET_MODULE_CHECKS[@]} ))
    local current_row=0
    local branch

    (( ++current_row ))
    [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
    local ipv6_state
    ipv6_state=$(_get_ipv6_state)
    _audit_tree_row_manual "3.1.1" "IPv6 status identified (Manual)" "$branch" \
        "IPv6 state: ${ipv6_state} | policy DISABLE_IPV6=${DISABLE_IPV6}"

    for entry in "${SECTION_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
    done


    for entry in "${NET_MODULE_CHECKS[@]}"; do
        local cis_id module desc
        IFS='|' read -r cis_id module desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_module_disabled "$module" || { global_status=1; }
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

    _run_audit_checks "Network Devices & Kernel Modules  (CIS 3.1 – 3.2)" \
        || global_status=1

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

    log_info "[3.1.1] Applying IPv6 policy (DISABLE_IPV6=${DISABLE_IPV6})..."
    _remediate_ipv6_status || any_failure=true

    for entry in "${SECTION_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        if ! "$audit_func"; then
            log_info "[$cis_id] Remediating: $desc..."
            "$rem_func" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    local any_module_fail=false
    for entry in "${NET_MODULE_CHECKS[@]}"; do
        local cis_id module desc
        IFS='|' read -r cis_id module desc <<< "$entry"
        if ! _audit_module_disabled "$module"; then
            any_module_fail=true
            break
        fi
    done

    if [[ "$any_module_fail" == "true" ]]; then
        log_info "[3.2.1–3.2.6] Remediating: network kernel modules..."
        _remediate_net_modules || any_failure=true
    else
        log_ok "[3.2.1–3.2.6] All network kernel modules — already compliant."
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
    _run_audit_checks "Post-Remediation Verification  (CIS 3.1 – 3.2)" \
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
    echo "CIS Benchmark Debian 13 - Section 3.1 & 3.2: Network Configuration"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply network hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 3.1/3.2 Network — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply network hardening)" > /dev/tty
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
    print_section_header "CIS 3.1/3.2" "Network Devices and Kernel Modules"
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