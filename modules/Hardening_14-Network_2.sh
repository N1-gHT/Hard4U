#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 3.3: Configure Network Kernel Parameters
#
# Sub-sections covered:
#   3.3.1.1  – 3.3.1.18  IPv4 sysctl parameters (18 checks)
#   3.3.2.1  – 3.3.2.8   IPv6 sysctl parameters (8 checks, skipped if IPv6 disabled)
#   3.3.0.1              systemd-sysctl runs after network interfaces (boot ordering)

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
readonly CIS_SYSCTL_CONF="/etc/sysctl.d/60-cis-sysctl.conf"
readonly SYSCTL_OVERRIDE_DIR="/etc/systemd/system/systemd-sysctl.service.d"
readonly SYSCTL_OVERRIDE_FILE="${SYSCTL_OVERRIDE_DIR}/60-cis-after-network.conf"

# ---------------------------------------------------------------------------
# DATA-DRIVEN arrays
# ---------------------------------------------------------------------------
readonly -a SYSCTL_IPV4_CHECKS=(
    "3.3.1.1|net.ipv4.ip_forward|0|net.ipv4.ip_forward configured"
    "3.3.1.2|net.ipv4.conf.all.forwarding|0|net.ipv4.conf.all.forwarding configured"
    "3.3.1.3|net.ipv4.conf.default.forwarding|0|net.ipv4.conf.default.forwarding configured"
    "3.3.1.4|net.ipv4.conf.all.send_redirects|0|net.ipv4.conf.all.send_redirects configured"
    "3.3.1.5|net.ipv4.conf.default.send_redirects|0|net.ipv4.conf.default.send_redirects configured"
    "3.3.1.6|net.ipv4.icmp_ignore_bogus_error_responses|1|net.ipv4.icmp_ignore_bogus_error_responses configured"
    "3.3.1.7|net.ipv4.icmp_echo_ignore_broadcasts|1|net.ipv4.icmp_echo_ignore_broadcasts configured"
    "3.3.1.8|net.ipv4.conf.all.accept_redirects|0|net.ipv4.conf.all.accept_redirects configured"
    "3.3.1.9|net.ipv4.conf.default.accept_redirects|0|net.ipv4.conf.default.accept_redirects configured"
    "3.3.1.10|net.ipv4.conf.all.secure_redirects|0|net.ipv4.conf.all.secure_redirects configured"
    "3.3.1.11|net.ipv4.conf.default.secure_redirects|0|net.ipv4.conf.default.secure_redirects configured"
    "3.3.1.12|net.ipv4.conf.all.rp_filter|1|net.ipv4.conf.all.rp_filter configured"
    "3.3.1.13|net.ipv4.conf.default.rp_filter|1|net.ipv4.conf.default.rp_filter configured"
    "3.3.1.14|net.ipv4.conf.all.accept_source_route|0|net.ipv4.conf.all.accept_source_route configured"
    "3.3.1.15|net.ipv4.conf.default.accept_source_route|0|net.ipv4.conf.default.accept_source_route configured"
    "3.3.1.16|net.ipv4.conf.all.log_martians|1|net.ipv4.conf.all.log_martians configured"
    "3.3.1.17|net.ipv4.conf.default.log_martians|1|net.ipv4.conf.default.log_martians configured"
    "3.3.1.18|net.ipv4.tcp_syncookies|1|net.ipv4.tcp_syncookies configured"
    "3.3.0.1|sysctl_after_network|1|systemd-sysctl runs after network"
)

readonly -a SYSCTL_IPV6_CHECKS=(
    "3.3.2.1|net.ipv6.conf.all.forwarding|0|net.ipv6.conf.all.forwarding configured"
    "3.3.2.2|net.ipv6.conf.default.forwarding|0|net.ipv6.conf.default.forwarding configured"
    "3.3.2.3|net.ipv6.conf.all.accept_redirects|0|net.ipv6.conf.all.accept_redirects configured"
    "3.3.2.4|net.ipv6.conf.default.accept_redirects|0|net.ipv6.conf.default.accept_redirects configured"
    "3.3.2.5|net.ipv6.conf.all.accept_source_route|0|net.ipv6.conf.all.accept_source_route configured"
    "3.3.2.6|net.ipv6.conf.default.accept_source_route|0|net.ipv6.conf.default.accept_source_route configured"
    "3.3.2.7|net.ipv6.conf.all.accept_ra|0|net.ipv6.conf.all.accept_ra configured"
    "3.3.2.8|net.ipv6.conf.default.accept_ra|0|net.ipv6.conf.default.accept_ra configured"
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
# Summary table — statuses: PASS / FAIL / SKIP
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0 skip_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        case "$status" in
            PASS) (( ++pass_count )) ;;
            FAIL) (( ++fail_count )) ;;
            SKIP|INFO) (( ++skip_count )) ;;
        esac
    done
    local total="${#_RESULT_IDS[@]}"
    local counted=$(( total - skip_count ))

    local W_ID=10 W_DESC=52 W_ST=6
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
        case "$st" in
            FAIL)      row_color="${C_BRIGHT_RED}" ;;
            SKIP|INFO) row_color="${C_DIM}" ;;
        esac
        printf "  ${row_color}│ %-*s │ %-*s │ %-*s │${C_RESET}\n" \
            "$W_ID" "${_RESULT_IDS[$i]}" \
            "$W_DESC" "${_RESULT_DESCS[$i]}" \
            "$W_ST" "$st"
    done

    local summary_color="${C_GREEN}"
    [[ $fail_count -gt 0 ]] && summary_color="${C_YELLOW}"
    local skip_suffix=""
    [[ $skip_count -gt 0 ]] && skip_suffix="  SKIP: ${skip_count}"
    echo -e "  ├${S_FULL}┤"
    printf "  ${summary_color}│ %-*s│${C_RESET}\n" "$W_SUMMARY" \
        " ${pass_count}/${counted} checks -- PASS: ${pass_count}  FAIL: ${fail_count}${skip_suffix}"
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
        printf "  %s %-52s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-52s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

_audit_tree_row_skip() {
    local cis_id="$1" desc="$2" branch="$3"
    printf "  %s %-52s  " "$branch" "$desc"
    echo -e "${C_DIM}[SKIP]${C_RESET}"
    record_result "$cis_id" "$desc" "SKIP"
}

# ---------------------------------------------------------------------------
# IPv6 detection
# ---------------------------------------------------------------------------
_is_ipv6_enabled() {
    [[ -d "/proc/sys/net/ipv6" ]] \
        || { log_debug "IPv6: /proc/sys/net/ipv6 missing → disabled"; return 1; }

    if [[ -f "/sys/module/ipv6/parameters/disable" ]] \
        && grep -Pqs -- '^\h*1\b' /sys/module/ipv6/parameters/disable 2>/dev/null; then
        log_debug "IPv6: kernel param disable=1 → disabled"
        return 1
    fi

    local all_dis default_dis
    all_dis=$(sysctl    -n net.ipv6.conf.all.disable_ipv6     2>/dev/null || echo 0)
    default_dis=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo 0)
    if [[ "$all_dis" -eq 1 && "$default_dis" -eq 1 ]]; then
        log_debug "IPv6: sysctl disable=1 → disabled"
        return 1
    fi

    log_debug "IPv6: enabled"
    return 0
}
# ---------------------------------------------------------------------------
# Sysctl audit / remediation
# ---------------------------------------------------------------------------

_audit_sysctl_after_network() {
    [[ -f "$SYSCTL_OVERRIDE_FILE" ]]
}

_ensure_sysctl_after_network() {
    log_info "Creating systemd-sysctl drop-in to run after network interfaces..."
    mkdir -p "$SYSCTL_OVERRIDE_DIR"
    printf '[Unit]\nAfter=network.target\n' > "$SYSCTL_OVERRIDE_FILE"
    chmod 644 "$SYSCTL_OVERRIDE_FILE"
    systemctl daemon-reload
    log_ok "systemd-sysctl will now run after network interfaces are up."
    log_warn "A REBOOT IS REQUIRED to apply this ordering change."
}

_audit_sysctl_param() {
    local param="$1" expected="$2"
    local escaped_param="${param//./\\.}"
    local current_value
    current_value=$(sysctl -n "$param" 2>/dev/null | tr -d '[:space:]')

    local runtime_ok=false persistence_ok=false
    [[ "$current_value" == "$expected" ]] && runtime_ok=true
    grep -qE "^${escaped_param}\s*=\s*${expected}\b" "$CIS_SYSCTL_CONF" 2>/dev/null \
        && persistence_ok=true

    log_debug "sysctl '$param': current='$current_value' expected='$expected'" \
        "persisted=${persistence_ok}"

    [[ "$runtime_ok" == "true" && "$persistence_ok" == "true" ]]
}

_remediate_sysctl_param() {
    local param="$1" expected="$2"
    local escaped_param="${param//./\\.}"
    _audit_sysctl_param "$param" "$expected" && return 0

    local conf_dir
    conf_dir=$(dirname "$CIS_SYSCTL_CONF")
    [[ -d "$conf_dir" ]] || mkdir -p "$conf_dir"

    if grep -q "^${escaped_param}" "$CIS_SYSCTL_CONF" 2>/dev/null; then
        sed -i "s|^${escaped_param}.*|${param} = ${expected}|" "$CIS_SYSCTL_CONF"
    else
        printf '%s = %s\n' "$param" "$expected" >> "$CIS_SYSCTL_CONF"
    fi

    local conflicting_file
    conflicting_file=$(grep -rlE "^${escaped_param}\s*=" \
        /etc/sysctl.conf /etc/sysctl.d/ /usr/lib/sysctl.d/ /run/sysctl.d/ 2>/dev/null \
        | grep -v "$(basename "$CIS_SYSCTL_CONF")" | sort | tail -1 || true)
    if [[ -n "$conflicting_file" ]]; then
        log_warn "${param}: also defined in '${conflicting_file}' — may override ${CIS_SYSCTL_CONF} at boot."
    fi

    if sysctl -w "${param}=${expected}" >/dev/null; then
        log_debug "Runtime: $param = $expected applied"
        return 0
    else
        log_error "Failed to set runtime parameter: $param"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer — called in audit and in verify step.
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local ipv6_enabled=false
    _is_ipv6_enabled 2>/dev/null && ipv6_enabled=true
    if [[ "$ipv6_enabled" == "false" ]]; then
        log_info "IPv6 is disabled — 3.3.2.x checks will be marked [SKIP]."
    fi

    local total_rows=$(( ${#SYSCTL_IPV4_CHECKS[@]} + ${#SYSCTL_IPV6_CHECKS[@]} ))
    local current_row=0
    local branch

    for entry in "${SYSCTL_IPV4_CHECKS[@]}"; do
        local cis_id param expected desc
        IFS='|' read -r cis_id param expected desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        if [[ "$param" == "sysctl_after_network" ]]; then
            _audit_tree_row "$cis_id" "$desc" "$branch" \
                _audit_sysctl_after_network || global_status=1
        else
            _audit_tree_row "$cis_id" "$desc" "$branch" \
                _audit_sysctl_param "$param" "$expected" || global_status=1
        fi
    done

    for entry in "${SYSCTL_IPV6_CHECKS[@]}"; do
        local cis_id param expected desc
        IFS='|' read -r cis_id param expected desc <<< "$entry"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        if [[ "$ipv6_enabled" == "true" ]]; then
            _audit_tree_row "$cis_id" "$desc" "$branch" \
                _audit_sysctl_param "$param" "$expected" || global_status=1
        else
            _audit_tree_row_skip "$cis_id" "$desc" "$branch"
        fi
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

    _run_audit_checks "Network Kernel Parameters  (CIS 3.3.1 – 3.3.2)" \
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

    for entry in "${SYSCTL_IPV4_CHECKS[@]}"; do
        local cis_id param expected desc
        IFS='|' read -r cis_id param expected desc <<< "$entry"
        if [[ "$param" == "sysctl_after_network" ]]; then
            if ! _audit_sysctl_after_network; then
                log_info "[$cis_id] Remediating: $desc..."
                _ensure_sysctl_after_network || any_failure=true
            else
                log_ok "[$cis_id] $desc — already compliant."
            fi
        elif ! _audit_sysctl_param "$param" "$expected"; then
            log_info "[$cis_id] Remediating: $desc..."
            _remediate_sysctl_param "$param" "$expected" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    if _is_ipv6_enabled 2>/dev/null; then
        for entry in "${SYSCTL_IPV6_CHECKS[@]}"; do
            local cis_id param expected desc
            IFS='|' read -r cis_id param expected desc <<< "$entry"
            if ! _audit_sysctl_param "$param" "$expected"; then
                log_info "[$cis_id] Remediating: $desc..."
                _remediate_sysctl_param "$param" "$expected" || any_failure=true
            else
                log_ok "[$cis_id] $desc — already compliant."
            fi
        done
    else
        log_info "IPv6 disabled — skipping IPv6 parameter remediation."
    fi

    log_info "Reloading sysctl settings..."
    sysctl --system >/dev/null 2>&1 || true

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
    _run_audit_checks "Post-Remediation Verification  (CIS 3.3.1 – 3.3.2)" \
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
    echo "CIS Benchmark Debian 13 - Section 3.3: Network Kernel Parameters"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply sysctl network hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 3.3 Network Kernel Parameters — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply sysctl hardening)" > /dev/tty
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
    print_section_header "CIS 3.3" "Configure Network Kernel Parameters"
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