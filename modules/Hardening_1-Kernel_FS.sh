#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.1.1: Configure Filesystem Kernel Modules
#
# Sub-sections covered:
#   1.1.1.1  - Ensure cramfs kernel module is not available
#   1.1.1.2  - Ensure freevxfs kernel module is not available
#   1.1.1.3  - Ensure hfs kernel module is not available
#   1.1.1.4  - Ensure hfsplus kernel module is not available
#   1.1.1.5  - Ensure jffs2 kernel module is not available
#   1.1.1.6  - Ensure overlay kernel module is not available
#   1.1.1.7  - Ensure squashfs kernel module is not available
#   1.1.1.8  - Ensure udf kernel module is not available
#   1.1.1.9  - Ensure firewire-core kernel module is not available
#   1.1.1.10 - Ensure usb-storage kernel module is not available
#   1.1.1.11 - Ensure unused filesystem kernel modules are not available (Manual)

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------

readonly MODPROBE_CONF_DIR="/etc/modprobe.d"
readonly MODPROBE_CONF_FILE="${MODPROBE_CONF_DIR}/zz_disabled_modules.conf"

CANONICAL_FALSE_PATH="$(readlink -f /bin/false)"
readonly CANONICAL_FALSE_PATH

readonly -a MODULES_TO_DISABLE=(
    "cramfs"
    "freevxfs"
    "hfs"
    "hfsplus"
    "jffs2"
    "overlay"
    "squashfs"
    "udf"
    "firewire-core"
    "usb-storage"
)

readonly -a MODULE_CIS_IDS=(
    "1.1.1.1"
    "1.1.1.2"
    "1.1.1.3"
    "1.1.1.4"
    "1.1.1.5"
    "1.1.1.6"
    "1.1.1.7"
    "1.1.1.8"
    "1.1.1.9"
    "1.1.1.10"
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
# Column inner widths: W_ID=9  W_DESC=32  W_ST=6
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=9 W_DESC=32 W_ST=6

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
# Module helpers
# ---------------------------------------------------------------------------

_is_module_loaded() {
    local module_name="$1"
    local module_mangled="${module_name//-/_}"
    log_debug "is_module_loaded: checking '$module_mangled' in /proc/modules"
    grep -q "^${module_mangled} " /proc/modules
}

_get_module_config() {
    local module_name="$1"
    local module_mangled="${module_name//-/_}"
    local raw

    raw=$(modprobe --showconfig 2>/dev/null \
        | grep -E -- "(^|\s)(install|blacklist)\s+${module_mangled}\b" \
        | tr -d '\r' || true)

    if [[ "$module_mangled" == "overlay" ]]; then
        local raw_alias
        raw_alias=$(modprobe --showconfig 2>/dev/null \
            | grep -E -- "(^|\s)(install|blacklist)\s+overlayfs\b" \
            | tr -d '\r' || true)
        [[ -n "$raw_alias" ]] && raw="${raw}"$'\n'"${raw_alias}"
    fi

    log_debug "_get_module_config '$module_name': <<<$raw>>>"
    echo "$raw"
}

_has_install_false() {
    local module_name="$1"
    local config="$2"
    local module_mangled="${module_name//-/_}"
    local regex="^\s*install\s+${module_mangled}\s+(/bin/false|/usr/bin/false|/bin/true|/usr/bin/true)(\s|#|$)"
    grep -qE "$regex" <<< "$config"
}

_has_blacklist() {
    local module_name="$1"
    local config="$2"
    local module_mangled="${module_name//-/_}"
    grep -qE "^\s*blacklist\s+${module_mangled}\b" <<< "$config"
}

_ensure_line_in_conf() {
    local line="$1"

    if [[ -f "$MODPROBE_CONF_FILE" ]] && grep -qFx -- "$line" "$MODPROBE_CONF_FILE"; then
        log_debug "Line already present: '$line'"
        return 0
    fi

    if [[ ! -d "$MODPROBE_CONF_DIR" ]]; then
        log_info "Creating directory '$MODPROBE_CONF_DIR'..."
        mkdir -p "$MODPROBE_CONF_DIR" || { log_error "Cannot create $MODPROBE_CONF_DIR"; return 1; }
    fi

    if [[ ! -f "$MODPROBE_CONF_FILE" ]]; then
        log_info "Creating '$MODPROBE_CONF_FILE'..."
        (
            umask 077
            printf '# Managed by CIS hardening script — do not edit manually.\n'   > "$MODPROBE_CONF_FILE"
            printf '# Generated: %s\n\n' "$(date)"                                >> "$MODPROBE_CONF_FILE"
        ) || { log_error "Failed to create '$MODPROBE_CONF_FILE'."; return 1; }
    fi

    log_info "Adding: '$line'"
    if ! echo "$line" >> "$MODPROBE_CONF_FILE"; then
        log_error "Failed to write to '$MODPROBE_CONF_FILE'."
        return 1
    fi
}

_unload_module() {
    local module_name="$1"
    local module_mangled="${module_name//-/_}"
    local output

    if ! _is_module_loaded "$module_name"; then
        log_info "Module '$module_name' is not currently loaded."
        return 0
    fi

    log_info "Unloading '$module_name'..."

    if output=$(modprobe -r "$module_mangled" 2>&1); then
        log_ok "Module '$module_name' unloaded via 'modprobe -r'."
        return 0
    fi

    log_debug "modprobe -r failed ($output), retrying with rmmod..."

    if output=$(rmmod "$module_mangled" 2>&1); then
        log_ok "Module '$module_name' unloaded via 'rmmod'."
        return 0
    fi

    log_error "Failed to unload '$module_name': $output"
    return 1
}

# ---------------------------------------------------------------------------
# CIS 1.1.1.1–1.1.1.10 — per-module audit & remediation
# ---------------------------------------------------------------------------

_audit_module() {
    local module_name="$1"
    local cis_id="$2"
    local is_last="${3:-0}"
    local module_mangled="${module_name//-/_}"
    local fail=0

    local effective_config
    effective_config=$(_get_module_config "$module_name")

    local loaded=false install_false=false blacklisted=false
    _is_module_loaded  "$module_name"                          && loaded=true
    _has_install_false "$module_name" "$effective_config"      && install_false=true
    _has_blacklist     "$module_name" "$effective_config"      && blacklisted=true

    if [[ "$loaded" == "true" ]]; then
        fail=1
    fi
    if [[ "$install_false" == "false" && "$blacklisted" == "false" ]]; then
        fail=1
    fi

    local loaded_tag install_tag bl_tag
    [[ "$loaded"       == "true"  ]] && loaded_tag="${C_BRIGHT_RED}loaded${C_RESET}"   \
                                     || loaded_tag="${C_GREEN}not loaded${C_RESET}"
    [[ "$install_false" == "true" ]] && install_tag="${C_GREEN}install=false${C_RESET}" \
                                     || install_tag="${C_DIM}no install${C_RESET}"
    [[ "$blacklisted"  == "true"  ]] && bl_tag="${C_GREEN}blacklisted${C_RESET}"        \
                                     || bl_tag="${C_DIM}no blacklist${C_RESET}"

    local status_color detail
    if [[ "$fail" -eq 0 ]]; then
        status_color="${C_GREEN}"
        detail=""
        record_result "$cis_id" "module: $module_name" "PASS"
    else
        status_color="${C_BRIGHT_RED}"
        local plain_details=()
        [[ "$loaded"        == "true"  ]] && plain_details+=("loaded")
        [[ "$install_false" == "false" ]] && plain_details+=("no install=false")
        [[ "$blacklisted"   == "false" ]] && plain_details+=("no blacklist")
        detail=$(IFS=', '; echo "${plain_details[*]}")
        record_result "$cis_id" "module: $module_name" "FAIL" "$detail"
    fi

    local branch; [[ "$is_last" -eq 1 ]] && branch="└─" || branch="├─"
    local status_str; [[ $fail -eq 0 ]] && status_str="PASS" || status_str="FAIL"
    echo -e "  ${branch} $(printf '%-16s' "$module_name")  ${status_color}[$(printf '%-4s' "$status_str")]${C_RESET}  ${loaded_tag}  ${install_tag}  ${bl_tag}"

    return "$fail"
}

_remediate_module() {
    local module_name="$1"
    local module_mangled="${module_name//-/_}"
    local failed=false

    log_info "Remediating '$module_name'..."

    if _is_module_loaded "$module_name"; then
        _unload_module "$module_name" || {
            log_warn "Could not unload '$module_name' — a reboot will be required."
        }
    fi

    _ensure_line_in_conf "install ${module_mangled} ${CANONICAL_FALSE_PATH}" || failed=true

    _ensure_line_in_conf "blacklist ${module_mangled}" || failed=true

    if [[ "$failed" == "false" ]]; then
        log_ok "Remediation for '$module_name' applied."
        return 0
    else
        log_error "Remediation for '$module_name' completed with errors."
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

    _tree_label "Filesystem Kernel Modules  (CIS 1.1.1.1 – 1.1.1.10)"

    local last_idx=$(( ${#MODULES_TO_DISABLE[@]} - 1 ))
    for i in "${!MODULES_TO_DISABLE[@]}"; do
        local module="${MODULES_TO_DISABLE[$i]}"
        local cis_id="${MODULE_CIS_IDS[$i]}"
        local is_last=0; [[ $i -eq $last_idx ]] && is_last=1
        _audit_module "$module" "$cis_id" "$is_last" || global_status=1
    done

    log_info "CIS 1.1.1.11 (Manual): Review any additional unused filesystem modules" \
             "not listed above and disable them as needed."

    print_summary_table

    if [[ "$global_status" -eq 0 ]]; then
        log_ok "Global Audit: ALL MODULES COMPLIANT."
    else
        log_warn "Global Audit: SOME MODULES ARE NON-COMPLIANT."
    fi

    return "$global_status"
}

# Phase 2: Remediation Only
run_phase_remediation() {
    print_section_header "MODE" "REMEDIATION ONLY"
    local any_failure=false

    for i in "${!MODULES_TO_DISABLE[@]}"; do
        local module="${MODULES_TO_DISABLE[$i]}"
        local cis_id="${MODULE_CIS_IDS[$i]}"

        local effective_config
        effective_config=$(_get_module_config "$module")

        local needs_remediation=false
        _is_module_loaded  "$module"                    && needs_remediation=true
        if ! _has_install_false "$module" "$effective_config" \
        || ! _has_blacklist     "$module" "$effective_config"; then
            needs_remediation=true
        fi

        if [[ "$needs_remediation" == "true" ]]; then
            _remediate_module "$module" || any_failure=true
        else
            log_ok "[$cis_id] '$module' is already disabled."
        fi
    done

    log_info "Updating kernel module database (depmod -a)..."
    depmod -a >/dev/null 2>&1 || {
        log_warn "depmod -a failed — reboot recommended."
        any_failure=true
    }

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
    log_info "Non-compliant modules found. Starting remediation..."

    local remediation_status=0
    run_phase_remediation || remediation_status=$?

    log_info "Updating kernel module database..."
    depmod -a >/dev/null 2>&1 || log_warn "depmod -a failed."

    echo ""
    log_info "Verifying post-remediation compliance..."

    reset_results
    local verify_status=0

    _tree_label "Post-Remediation Verification  (CIS 1.1.1.1 – 1.1.1.10)"

    local last_idx=$(( ${#MODULES_TO_DISABLE[@]} - 1 ))
    for i in "${!MODULES_TO_DISABLE[@]}"; do
        local module="${MODULES_TO_DISABLE[$i]}"
        local cis_id="${MODULE_CIS_IDS[$i]}"
        local is_last=0; [[ $i -eq $last_idx ]] && is_last=1
        _audit_module "$module" "$cis_id" "$is_last" || verify_status=1
    done

    print_summary_table

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. All modules are now compliant."
        return 0
    else
        log_warn "Auto-remediation finished with pending items."
        log_warn "A system reboot is strongly recommended to fully apply changes."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# User interface & main
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section 1.1.1: Configure Filesystem Kernel Modules"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply module disabling configurations."
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
    echo -e "\n${C_BOLD}--- CIS 1.1.1 Kernel Modules — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Disable modules, write config)" > /dev/tty
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
    print_section_header "CIS 1.1.1" "Configure Filesystem Kernel Modules"
    log_debug "SCRIPT_DEBUG: ${SCRIPT_DEBUG:-false}"

    if [[ ! -x "$CANONICAL_FALSE_PATH" ]]; then
        log_critical "Executable '$CANONICAL_FALSE_PATH' not found or not executable. Aborting."
    fi
    log_ok "Prerequisite check passed ($CANONICAL_FALSE_PATH exists)."

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