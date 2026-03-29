#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 2.3: Configure Time Synchronization
#
# Sub-sections covered:
#   2.3.1.1 - Ensure a single time synchronization daemon is in use
#   2.3.3.1 - Ensure chrony is configured with authorized timeserver
#   2.3.3.2 - Ensure chrony is running as user _chrony
#   2.3.3.3 - Ensure chrony is enabled and running

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
readonly CHRONY_PKG="chrony"
readonly CHRONY_SVC="chrony.service"
readonly CHRONY_CONF="/etc/chrony/chrony.conf"
readonly CHRONY_SOURCES_DIR="/etc/chrony/sources.d"
readonly CHRONY_SOURCES_FILE="${CHRONY_SOURCES_DIR}/cis-compliant.sources"
readonly CHRONY_USER="_chrony"
readonly TIMESYNCD_SVC="systemd-timesyncd.service"
readonly -a NTP_SERVERS=(
    "server 0.fr.pool.ntp.org iburst"
    "server 1.fr.pool.ntp.org iburst"
    "server 2.fr.pool.ntp.org iburst"
    "pool fr.pool.ntp.org iburst maxsources 4"
)

readonly -a TIME_CHECKS=(
    "2.3.1.1|_audit_single_time_daemon|_remediate_single_time_daemon|Single time synchronization daemon in use"
    "2.3.3.1|_audit_chrony_configuration|_remediate_chrony_configuration|Chrony authorized timeserver configured"
    "2.3.3.2|_audit_chrony_user|_remediate_chrony_user|Chrony running as user ${CHRONY_USER}"
    "2.3.3.3|_audit_chrony_enabled_running|_remediate_chrony_enabled_running|Chrony enabled and running"
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
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
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
# Tree row renderer + record_result
# ---------------------------------------------------------------------------
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
# Runtime daemon detection helpers
# ---------------------------------------------------------------------------

_detect_active_daemon() {
    local chrony_active=false timesyncd_active=false
    _is_service_active "$CHRONY_SVC"   && chrony_active=true
    _is_service_active "$TIMESYNCD_SVC" && timesyncd_active=true

    if [[ "$chrony_active" == "true" && "$timesyncd_active" == "true" ]]; then
        echo "both"
    elif [[ "$chrony_active" == "true" ]]; then
        echo "chrony"
    elif [[ "$timesyncd_active" == "true" ]]; then
        echo "systemd-timesyncd"
    else
        echo "none"
    fi
}

_is_chrony_context() {
    if [[ -n "${TIME_DAEMON:-}" ]]; then
        [[ "$TIME_DAEMON" == "chrony" ]]
    else
        _is_service_active "$CHRONY_SVC"
    fi
}

# ---------------------------------------------------------------------------
# CIS 2.3.1.1 — Single time synchronization daemon
# ---------------------------------------------------------------------------

_audit_single_time_daemon() {
    local detected
    detected=$(_detect_active_daemon)

    case "$detected" in
        chrony|systemd-timesyncd)
            log_info "Detected: ${detected} (active)"
            return 0
            ;;
        both)
            log_debug "Conflict: both chrony and systemd-timesyncd are active"
            log_warn  "Detected: both chrony and systemd-timesyncd are active simultaneously"
            return 1
            ;;
        none)
            log_debug "No time synchronization daemon is active"
            log_warn  "Detected: no time synchronization daemon is active"
            return 1
            ;;
    esac
}

_remediate_single_time_daemon() {
    local detected
    detected=$(_detect_active_daemon)

    case "$detected" in
        chrony|systemd-timesyncd)
            log_ok "Single daemon already active: ${detected}. Nothing to do."
            return 0
            ;;
        both)
            local keep="${TIME_DAEMON:-chrony}"
            local stop_svc
            if [[ "$keep" == "chrony" ]]; then
                stop_svc="$TIMESYNCD_SVC"
            else
                stop_svc="$CHRONY_SVC"
            fi
            log_info "Both daemons active. Stopping and masking ${stop_svc} (keeping ${keep})..."
            systemctl stop "$stop_svc" 2>/dev/null || true
            systemctl mask "$stop_svc" 2>/dev/null || true
            log_ok "${stop_svc} stopped and masked."
            ;;
        none)
            log_info "No time daemon active. Installing and enabling chrony by default..."
            if ! _is_installed "$CHRONY_PKG"; then
                apt-get install -y "$CHRONY_PKG"
            fi
            systemctl unmask "$CHRONY_SVC" 2>/dev/null || true
            systemctl enable --now "$CHRONY_SVC"
            log_ok "chrony installed and started."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# CIS 2.3.3.1 — Chrony authorized timeserver configured
# ---------------------------------------------------------------------------

_audit_chrony_configuration() {
    _is_chrony_context || return 0
    _is_installed "$CHRONY_PKG" || { log_debug "Chrony not installed"; return 1; }

    if ! grep -qE "^\s*sourcedir\s+${CHRONY_SOURCES_DIR}" "$CHRONY_CONF"; then
        log_debug "Missing 'sourcedir ${CHRONY_SOURCES_DIR}' in $CHRONY_CONF"
        return 1
    fi
    if [[ ! -s "$CHRONY_SOURCES_FILE" ]]; then
        log_debug "CIS sources file missing or empty: $CHRONY_SOURCES_FILE"
        return 1
    fi
    if command -v chronyc &>/dev/null && _is_service_active "$CHRONY_SVC"; then
        if ! chronyc sources 2>/dev/null | grep -qE "^[#\^\*\+\-\?]"; then
            log_debug "Chrony running but no sources active"
            return 1
        fi
    fi
    return 0
}

_remediate_chrony_configuration() {
    _is_chrony_context || return 0

    if ! _is_installed "$CHRONY_PKG"; then
        log_info "Installing $CHRONY_PKG..."
        apt-get install -y "$CHRONY_PKG"
    fi

    if ! grep -qE "^\s*sourcedir\s+${CHRONY_SOURCES_DIR}" "$CHRONY_CONF"; then
        log_info "Adding 'sourcedir ${CHRONY_SOURCES_DIR}' to $CHRONY_CONF..."
        printf '\n# Directive added by CIS Security Script\nsourcedir %s\n' \
            "$CHRONY_SOURCES_DIR" >> "$CHRONY_CONF"
    else
        log_ok "'sourcedir' directive already present in $CHRONY_CONF."
    fi

    if [[ ! -d "$CHRONY_SOURCES_DIR" ]]; then
        log_info "Creating $CHRONY_SOURCES_DIR..."
        mkdir -p "$CHRONY_SOURCES_DIR"
        chmod 0755 "$CHRONY_SOURCES_DIR"
    fi

    log_info "Writing authorized NTP servers to $CHRONY_SOURCES_FILE..."
    {
        printf '# CIS Compliant Sources — generated by CIS hardening script\n'
        printf '# Loaded via sourcedir directive in %s\n' "$CHRONY_CONF"
        printf '%s\n' "${NTP_SERVERS[@]}"
    } > "$CHRONY_SOURCES_FILE"
    chmod 644 "$CHRONY_SOURCES_FILE"

    log_info "Restarting $CHRONY_SVC..."
    systemctl restart "$CHRONY_SVC"
    sleep 2

    if _is_service_active "$CHRONY_SVC"; then
        log_ok "$CHRONY_SVC restarted successfully."
    else
        log_error "$CHRONY_SVC failed to restart. Check: journalctl -xeu chrony"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 2.3.3.2 — Chrony running as user _chrony
# ---------------------------------------------------------------------------

_audit_chrony_user() {
    _is_chrony_context || return 0
    _is_installed "$CHRONY_PKG" || return 0

    local running_user
    running_user=$(ps -C chronyd -o user= 2>/dev/null | head -n 1 || true)

    if [[ -n "$running_user" ]]; then
        if [[ "$running_user" == "$CHRONY_USER" ]]; then
            return 0
        else
            log_debug "Chrony running as '$running_user' (expected '$CHRONY_USER')"
            return 1
        fi
    else
        if grep -q "^\s*user ${CHRONY_USER}" "$CHRONY_CONF" 2>/dev/null; then
            return 0
        fi
        log_debug "No running chronyd and no 'user ${CHRONY_USER}' in $CHRONY_CONF"
        return 1
    fi
}

_remediate_chrony_user() {
    _is_chrony_context || return 0
    _is_installed "$CHRONY_PKG" || return 0

    log_info "Setting chrony user to $CHRONY_USER in $CHRONY_CONF..."
    if grep -q "^\s*user" "$CHRONY_CONF" 2>/dev/null; then
        sed -ri "s/^\s*user\s+.*/user ${CHRONY_USER}/" "$CHRONY_CONF"
    else
        printf 'user %s\n' "$CHRONY_USER" >> "$CHRONY_CONF"
    fi
    systemctl restart "$CHRONY_SVC"
    log_ok "Chrony restarted with user $CHRONY_USER."
}

# ---------------------------------------------------------------------------
# CIS 2.3.3.3 — Chrony enabled and running
# ---------------------------------------------------------------------------

_audit_chrony_enabled_running() {
    _is_chrony_context || return 0

    if _is_service_active "$CHRONY_SVC" && _is_service_enabled "$CHRONY_SVC"; then
        return 0
    fi
    log_debug "Chrony: active=$(systemctl is-active "$CHRONY_SVC" 2>/dev/null) enabled=$(systemctl is-enabled "$CHRONY_SVC" 2>/dev/null)"
    return 1
}

_remediate_chrony_enabled_running() {
    _is_chrony_context || return 0

    log_info "Enabling and starting $CHRONY_SVC..."
    systemctl unmask "$CHRONY_SVC" 2>/dev/null || true
    systemctl enable --now "$CHRONY_SVC"
    log_ok "$CHRONY_SVC enabled and started."
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_apply_remediation() {
    local audit_func="$1" rem_func="$2" check_msg="$3" already_ok_msg="$4"
    log_info "$check_msg"
    if ! "$audit_func"; then
        "$rem_func" || return 1
    else
        log_ok "$already_ok_msg"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Phase 1: Audit Only
# ---------------------------------------------------------------------------
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0

    _tree_label "Time Synchronization  (CIS 2.3.1.1 / 2.3.3.1 – 2.3.3.3)"

    local last_idx=$(( ${#TIME_CHECKS[@]} - 1 ))
    for i in "${!TIME_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "${TIME_CHECKS[$i]}"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
    done

    print_summary_table

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

    for entry in "${TIME_CHECKS[@]}"; do
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

    _tree_label "Post-Remediation Verification  (CIS 2.3.1.1 / 2.3.3.1 – 2.3.3.3)"

    local last_idx=$(( ${#TIME_CHECKS[@]} - 1 ))
    for i in "${!TIME_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "${TIME_CHECKS[$i]}"
        local branch; [[ $i -eq $last_idx ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || verify_status=1
    done

    print_summary_table

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
    echo "  --remediation  Apply time synchronization configurations."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "If no option is provided, an interactive menu will be displayed."
    echo ""
    echo "Environment variables:"
    echo "  TIME_DAEMON=chrony              Orient chrony-specific checks (2.3.3.x)."
    echo "                                  Accepted: chrony, systemd-timesyncd"
    echo "                                  If not set, the active daemon is auto-detected."
    echo "  SCRIPT_DEBUG=true               Enable debug output on stderr."
    echo "  NO_COLOR=true                   Disable ANSI color output."
    echo ""
    echo "Controller usage examples:"
    echo "  TIME_DAEMON=chrony $0 --auto"
    echo "  TIME_DAEMON=systemd-timesyncd $0 --audit"
    echo ""
    echo "Note: 2.3.1.1 always detects the active daemon at runtime."
    echo "      TIME_DAEMON only governs whether 2.3.3.x (chrony config) checks run."
}

show_interactive_menu() {
        echo -e "\n${C_BOLD}--- CIS 2.3 Time Synchronization — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply time synchronization settings)" > /dev/tty
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

    if [[ -n "${TIME_DAEMON:-}" ]]; then
        case "$TIME_DAEMON" in
            chrony|systemd-timesyncd) ;;
            *)
                log_error "Invalid TIME_DAEMON value: '${TIME_DAEMON}'."
                log_error "Accepted values: chrony, systemd-timesyncd"
                exit 1
                ;;
        esac
        log_info  "TIME_DAEMON hint from controller: ${TIME_DAEMON} (orients 2.3.3.x checks)"
        log_debug "TIME_DAEMON='${TIME_DAEMON}' → 2.3.3.x checks apply to: ${TIME_DAEMON}"
    else
        log_debug "TIME_DAEMON not set — 2.3.3.x checks will follow runtime-detected daemon"
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

    log_info  "Operation mode: ${mode}"
    if [[ -n "${1:-}" ]]; then
        log_debug "Mode source: CLI arg '$1'"
    else
        log_debug "Mode source: interactive menu"
    fi

    case "$mode" in
        audit)       run_phase_audit ;;
        remediation) run_phase_remediation ;;
        auto)        run_phase_auto ;;
    esac
}

main "$@"