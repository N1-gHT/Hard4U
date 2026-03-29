#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.7: Configure GNOME Display Manager
#
# Sub-sections covered:
#   1.7.1  - Ensure GDM is removed
#   1.7.2  - Ensure GDM login banner is configured
#   1.7.3  - Ensure GDM disable-user-list option is enabled
#   1.7.4  - Ensure GDM screen locks when the user is idle
#   1.7.5  - Ensure GDM screen locks cannot be overridden
#   1.7.6  - Ensure GDM automatic mounting of removable media is disabled
#   1.7.7  - Ensure GDM disabling automatic mounting is not overridden
#   1.7.8  - Ensure GDM autorun-never is enabled
#   1.7.9  - Ensure GDM autorun-never is not overridden
#   1.7.10 - Ensure XDMCP is not enabled
#   1.7.11 - Ensure Xwayland is configured (WaylandEnable=false)

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
readonly GDM_PACKAGE="gdm3"

readonly DCONF_PROFILE_DIR="/etc/dconf/profile"
readonly DCONF_DB_DIR="/etc/dconf/db"

readonly GDM_PROFILE="${DCONF_PROFILE_DIR}/gdm"
readonly GDM_DB_GDM_DIR="${DCONF_DB_DIR}/gdm.d"
readonly GDM_KEYFILE_BANNER="${GDM_DB_GDM_DIR}/01-banner-message"
readonly GDM_KEYFILE_LOGIN="${GDM_DB_GDM_DIR}/00-login-screen"

readonly USER_PROFILE="${DCONF_PROFILE_DIR}/user"
readonly LOCAL_DB_DIR="${DCONF_DB_DIR}/local.d"
readonly SCREENSAVER_KEYFILE="${LOCAL_DB_DIR}/00-screensaver"
readonly LOCKS_DIR="${LOCAL_DB_DIR}/locks"
readonly SCREENSAVER_LOCKS_FILE="${LOCKS_DIR}/00-screensaver"
readonly MEDIA_AUTOMOUNT_FILE="${LOCAL_DB_DIR}/00-media-automount"
readonly MEDIA_LOCKS_FILE="${LOCKS_DIR}/00-media-automount"
readonly MEDIA_AUTORUN_FILE="${LOCAL_DB_DIR}/00-media-autorun"
readonly AUTORUN_LOCKS_FILE="${LOCKS_DIR}/00-media-autorun"

readonly -a GDM_CONF_FILES=(
    "/etc/gdm3/custom.conf"
    "/etc/gdm3/daemon.conf"
    "/etc/gdm/custom.conf"
    "/etc/gdm/daemon.conf"
)

readonly BANNER_TEXT="'Authorized uses only. All activity may be monitored and reported'"
readonly MAX_IDLE_DELAY=900
readonly MAX_LOCK_DELAY=5

readonly -a LOCK_CHECKS=(
    "1.7.5|Screensaver locks cannot be overridden|${SCREENSAVER_LOCKS_FILE}|/org/gnome/desktop/session/idle-delay /org/gnome/desktop/screensaver/lock-delay"
    "1.7.7|Automount settings locked|${MEDIA_LOCKS_FILE}|/org/gnome/desktop/media-handling/automount /org/gnome/desktop/media-handling/automount-open"
    "1.7.9|Autorun-never locked|${AUTORUN_LOCKS_FILE}|/org/gnome/desktop/media-handling/autorun-never"
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

    local W_ID=8 W_DESC=46 W_ST=6
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

_is_gdm_installed() {
    dpkg-query -s "$GDM_PACKAGE" &>/dev/null
}

_update_dconf() {
    if dconf update; then
        log_ok "dconf database updated."
    else
        log_error "Failed to update dconf database."
        return 1
    fi
}

_write_keyfile() {
    local file_path="$1"
    local content="$2"
    mkdir -p "$(dirname "$file_path")"
    printf '%s\n' "$content" > "$file_path"
    log_debug "Wrote keyfile: $file_path"
}

_ensure_gdm_profile() {
    _write_keyfile "$GDM_PROFILE" \
"user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults"
}

_ensure_user_profile_local() {
    if ! grep -q "system-db:local" "$USER_PROFILE" 2>/dev/null; then
        [[ -f "$USER_PROFILE" ]] && cp "$USER_PROFILE" "${USER_PROFILE}.bak"
        _write_keyfile "$USER_PROFILE" $'user-db:user\nsystem-db:local'
        log_info "User dconf profile updated with system-db:local."
    fi
}

# ---------------------------------------------------------------------------
# Generic lock key helpers (DRY — replaces 3 identical audit/remediate pairs)
# ---------------------------------------------------------------------------

_audit_lock_keys() {
    _is_gdm_installed || return 0

    if [[ ! -d "$LOCKS_DIR" ]]; then
        log_debug "Lock directory missing: $LOCKS_DIR"
        return 1
    fi
    local fail=0
    for key in "$@"; do
        if ! grep -qrF "$key" "$LOCKS_DIR"; then
            log_debug "Key not locked: $key"
            fail=1
        fi
    done
    return "$fail"
}

_remediate_lock_file() {
    local lock_file="$1"
    shift
    mkdir -p "$(dirname "$lock_file")"
    printf '%s\n' "$@" > "$lock_file"
    log_ok "Lock file written: $lock_file"
    _update_dconf
}

_audit_tree_row_lock() {
    local idx="$1" branch="$2"
    local cis_id desc lock_file keys_str
    IFS='|' read -r cis_id desc lock_file keys_str <<< "${LOCK_CHECKS[$idx]}"
    local -a keys
    read -ra keys <<< "$keys_str"
    _audit_tree_row "$cis_id" "$desc" "$branch" _audit_lock_keys "${keys[@]}"
}

_apply_lock_remediation() {
    local idx="$1"
    local cis_id desc lock_file keys_str
    IFS='|' read -r cis_id desc lock_file keys_str <<< "${LOCK_CHECKS[$idx]}"
    local -a keys
    read -ra keys <<< "$keys_str"

    if _audit_lock_keys "${keys[@]}"; then
        log_ok "[$cis_id] $desc — already compliant."
    else
        log_info "[$cis_id] Remediating: $desc..."
        _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
        _remediate_lock_file "$lock_file" "${keys[@]}" || return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.7.1 — GDM removed
# ---------------------------------------------------------------------------

_audit_gdm_removed() {
    if _is_gdm_installed; then
        log_debug "$GDM_PACKAGE is installed"
        return 1
    fi
    return 0
}

_remediate_gdm_removal() {
    log_warn "Removing GDM will disable the Graphical User Interface."
    if apt-get purge -y "$GDM_PACKAGE" >/dev/null 2>&1; then
        log_ok "$GDM_PACKAGE purged."
        apt-get autoremove -y >/dev/null 2>&1 && log_ok "Unused dependencies removed."
    else
        log_error "Failed to purge $GDM_PACKAGE."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.7.2 — Login banner
# ---------------------------------------------------------------------------

_audit_gdm_banner() {
    _is_gdm_installed || return 0

    if [[ ! -f "$GDM_PROFILE" ]] || ! grep -q "system-db:gdm" "$GDM_PROFILE"; then
        log_debug "GDM profile missing or invalid"
        return 1
    fi
    if [[ ! -f "$GDM_KEYFILE_BANNER" ]]; then
        log_debug "Banner keyfile missing: $GDM_KEYFILE_BANNER"
        return 1
    fi
    grep -q "^banner-message-enable=true" "$GDM_KEYFILE_BANNER" \
        && grep -q "banner-message-text=${BANNER_TEXT}" "$GDM_KEYFILE_BANNER"
}

_remediate_gdm_banner() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
    _ensure_gdm_profile
    _write_keyfile "$GDM_KEYFILE_BANNER" \
"[org/gnome/login-screen]
banner-message-enable=true
banner-message-text=${BANNER_TEXT}"
    _update_dconf
}

# ---------------------------------------------------------------------------
# CIS 1.7.3 — Disable user list
# ---------------------------------------------------------------------------

_audit_gdm_user_list() {
    _is_gdm_installed || return 0

    if [[ ! -f "$GDM_PROFILE" ]]; then
        log_debug "GDM profile missing"
        return 1
    fi
    if [[ ! -f "$GDM_KEYFILE_LOGIN" ]]; then
        log_debug "Login keyfile missing: $GDM_KEYFILE_LOGIN"
        return 1
    fi
    grep -q "disable-user-list=true" "$GDM_KEYFILE_LOGIN"
}

_remediate_gdm_user_list() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
    _ensure_gdm_profile
    _write_keyfile "$GDM_KEYFILE_LOGIN" \
"[org/gnome/login-screen]
disable-user-list=true"
    _update_dconf
}

# ---------------------------------------------------------------------------
# CIS 1.7.4 — Screen locks when idle (idle-delay + lock-delay)
# ---------------------------------------------------------------------------

_audit_gdm_screensaver() {
    _is_gdm_installed || return 0

    if ! grep -q "system-db:local" "$USER_PROFILE" 2>/dev/null; then
        log_debug "User profile missing system-db:local"
        return 1
    fi
    if [[ ! -f "$SCREENSAVER_KEYFILE" ]]; then
        log_debug "Screensaver keyfile missing: $SCREENSAVER_KEYFILE"
        return 1
    fi

    local idle_val lock_val fail=0
    idle_val=$(grep -Po '^\s*idle-delay=uint32\s+\K\d+' "$SCREENSAVER_KEYFILE" || true)
    lock_val=$(grep -Po '^\s*lock-delay=uint32\s+\K\d+' "$SCREENSAVER_KEYFILE" || true)

    if [[ -z "$idle_val" || "$idle_val" -eq 0 || "$idle_val" -gt "$MAX_IDLE_DELAY" ]]; then
        log_debug "idle-delay non-compliant: '$idle_val' (max $MAX_IDLE_DELAY, min 1)"
        fail=1
    fi
    if [[ -z "$lock_val" || "$lock_val" -gt "$MAX_LOCK_DELAY" ]]; then
        log_debug "lock-delay non-compliant: '$lock_val' (max $MAX_LOCK_DELAY)"
        fail=1
    fi
    return "$fail"
}

_remediate_gdm_screensaver() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
    _ensure_user_profile_local
    _write_keyfile "$SCREENSAVER_KEYFILE" \
"[org/gnome/desktop/session]
idle-delay=uint32 ${MAX_IDLE_DELAY}
[org/gnome/desktop/screensaver]
lock-delay=uint32 ${MAX_LOCK_DELAY}"
    _update_dconf
}

# ---------------------------------------------------------------------------
# CIS 1.7.6 — Automount disabled
# ---------------------------------------------------------------------------

_audit_gdm_automount() {
    _is_gdm_installed || return 0

    if ! grep -q "system-db:local" "$USER_PROFILE" 2>/dev/null; then
        log_debug "User profile missing system-db:local"
        return 1
    fi
    if [[ ! -f "$MEDIA_AUTOMOUNT_FILE" ]]; then
        log_debug "Automount keyfile missing: $MEDIA_AUTOMOUNT_FILE"
        return 1
    fi
    grep -q "automount=false" "$MEDIA_AUTOMOUNT_FILE" \
        && grep -q "automount-open=false" "$MEDIA_AUTOMOUNT_FILE"
}

_remediate_gdm_automount() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
    _ensure_user_profile_local
    _write_keyfile "$MEDIA_AUTOMOUNT_FILE" \
"[org/gnome/desktop/media-handling]
automount=false
automount-open=false"
    _update_dconf
}

# ---------------------------------------------------------------------------
# CIS 1.7.8 — Autorun-never enabled
# ---------------------------------------------------------------------------

_audit_gdm_autorun() {
    _is_gdm_installed || return 0

    if ! grep -q "system-db:local" "$USER_PROFILE" 2>/dev/null; then
        log_debug "User profile missing system-db:local"
        return 1
    fi
    if [[ ! -f "$MEDIA_AUTORUN_FILE" ]]; then
        log_debug "Autorun keyfile missing: $MEDIA_AUTORUN_FILE"
        return 1
    fi
    grep -q "autorun-never=true" "$MEDIA_AUTORUN_FILE"
}

_remediate_gdm_autorun() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }
    _ensure_user_profile_local
    _write_keyfile "$MEDIA_AUTORUN_FILE" \
"[org/gnome/desktop/media-handling]
autorun-never=true"
    _update_dconf
}

# ---------------------------------------------------------------------------
# CIS 1.7.10 — XDMCP not enabled
# ---------------------------------------------------------------------------

_audit_gdm_xdmcp() {
    _is_gdm_installed || return 0

    local found_file=false
    for l_file in "${GDM_CONF_FILES[@]}"; do
        [[ -f "$l_file" ]] || continue
        found_file=true
        if awk '/\[xdmcp\]/{f=1;next}/\[/{f=0} f && /^\s*Enable\s*=\s*true/' "$l_file" \
                | grep -q .; then
            log_debug "XDMCP enabled in $l_file"
            return 1
        fi
    done

    log_debug "XDMCP: found_file=$found_file — compliant"
    return 0
}

_remediate_gdm_xdmcp() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }

    local modified=false
    for l_file in "${GDM_CONF_FILES[@]}"; do
        [[ -f "$l_file" ]] || continue
        if awk '/\[xdmcp\]/{f=1;next}/\[/{f=0} f && /^\s*Enable\s*=\s*true/' "$l_file" \
                | grep -q .; then
            sed -ri '/^\[xdmcp\]/,/^\[/ s/^\s*Enable\s*=\s*true/#Enable=true/' "$l_file"
            log_ok "XDMCP disabled in $l_file."
            modified=true
        fi
    done

    if [[ "$modified" == "false" ]]; then
        log_info "No XDMCP changes required."
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.7.11 — Xwayland configured (WaylandEnable=false in [daemon])
# ---------------------------------------------------------------------------

_audit_gdm_xwayland() {
    _is_gdm_installed || return 0

    local checked=false
    for l_file in "${GDM_CONF_FILES[@]}"; do
        [[ -f "$l_file" ]] || continue
        checked=true
        if sed -n '/^\[daemon\]/,/^\[/p' "$l_file" \
                | grep -Pq '^\h*WaylandEnable\h*=\h*false\b'; then
            return 0
        fi
    done

    if [[ "$checked" == "false" ]]; then
        log_debug "No GDM conf files found"
        return 1
    fi
    log_debug "WaylandEnable=false not found in any [daemon] block"
    return 1
}

_remediate_gdm_xwayland() {
    _is_gdm_installed || { log_info "GDM not installed, skipping."; return 0; }

    local file_to_edit=""
    for l_file in "${GDM_CONF_FILES[@]}"; do
        [[ -f "$l_file" ]] && { file_to_edit="$l_file"; break; }
    done

    if [[ -z "$file_to_edit" ]]; then
        log_error "No GDM configuration file found."
        return 1
    fi

    if ! grep -q "^\[daemon\]" "$file_to_edit"; then
        printf '\n[daemon]\n' >> "$file_to_edit"
    fi

    if sed -n '/^\[daemon\]/,/^\[/p' "$file_to_edit" | grep -q "WaylandEnable"; then
        sed -ri '/^\[daemon\]/,/^\[/ s/^\s*#?WaylandEnable\s*=.*/WaylandEnable=false/' \
            "$file_to_edit"
    else
        sed -i '/^\[daemon\]/a WaylandEnable=false' "$file_to_edit"
    fi

    if grep -q "WaylandEnable=false" "$file_to_edit"; then
        log_ok "Wayland disabled in $file_to_edit."
    else
        log_error "Failed to set WaylandEnable=false in $file_to_edit."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_check_compliance() {
    local audit_func="$1" msg_ok="$2" msg_fail="$3"
    local prefix="${4:-Audit}"
    if "$audit_func"; then log_ok "${prefix}: ${msg_ok}"; return 0
    else log_warn "${prefix}: ${msg_fail}"; return 1; fi
}

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

    _tree_label "GDM Installation  (CIS 1.7.1)"
    _audit_tree_row "1.7.1" "GDM (gdm3) not installed" "└─" \
        _audit_gdm_removed || global_status=1

    _tree_label "Login Screen  (CIS 1.7.2 – 1.7.3)"
    _audit_tree_row "1.7.2" "Login banner configured" "├─" \
        _audit_gdm_banner || global_status=1
    _audit_tree_row "1.7.3" "User list disabled" "└─" \
        _audit_gdm_user_list || global_status=1

    _tree_label "Screensaver  (CIS 1.7.4 – 1.7.5)"
    _audit_tree_row "1.7.4" "Screen locks when idle" "├─" \
        _audit_gdm_screensaver || global_status=1
    _audit_tree_row_lock 0 "└─" || global_status=1

    _tree_label "Removable Media  (CIS 1.7.6 – 1.7.9)"
    _audit_tree_row "1.7.6" "Automount disabled" "├─" \
        _audit_gdm_automount || global_status=1
    _audit_tree_row_lock 1 "├─" || global_status=1
    _audit_tree_row "1.7.8" "Autorun-never enabled" "├─" \
        _audit_gdm_autorun || global_status=1
    _audit_tree_row_lock 2 "└─" || global_status=1

    _tree_label "Display Protocol  (CIS 1.7.10 – 1.7.11)"
    _audit_tree_row "1.7.10" "XDMCP not enabled" "├─" \
        _audit_gdm_xdmcp || global_status=1
    _audit_tree_row "1.7.11" "Xwayland configured (WaylandEnable=false)" "└─" \
        _audit_gdm_xwayland || global_status=1

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

    _apply_remediation _audit_gdm_removed _remediate_gdm_removal \
        "Checking GDM installation..." \
        "GDM is already absent." || any_failure=true

    _apply_remediation _audit_gdm_banner _remediate_gdm_banner \
        "Checking GDM login banner..." \
        "GDM banner already configured." || any_failure=true

    _apply_remediation _audit_gdm_user_list _remediate_gdm_user_list \
        "Checking GDM user list..." \
        "GDM user list already disabled." || any_failure=true

    _apply_remediation _audit_gdm_screensaver _remediate_gdm_screensaver \
        "Checking GNOME screensaver idle/lock delay..." \
        "Screensaver settings already compliant." || any_failure=true

    _apply_lock_remediation 0 || any_failure=true

    _apply_remediation _audit_gdm_automount _remediate_gdm_automount \
        "Checking GDM automount..." \
        "Automount already disabled." || any_failure=true

    _apply_lock_remediation 1 || any_failure=true

    _apply_remediation _audit_gdm_autorun _remediate_gdm_autorun \
        "Checking GDM autorun-never..." \
        "Autorun-never already enabled." || any_failure=true

    _apply_lock_remediation 2 || any_failure=true

    _apply_remediation _audit_gdm_xdmcp _remediate_gdm_xdmcp \
        "Checking XDMCP configuration..." \
        "XDMCP already disabled." || any_failure=true

    _apply_remediation _audit_gdm_xwayland _remediate_gdm_xwayland \
        "Checking Xwayland configuration..." \
        "Xwayland already configured." || any_failure=true

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

    _tree_label "Verification — GDM Installation  (CIS 1.7.1)"
    _audit_tree_row "1.7.1" "GDM (gdm3) not installed" "└─" \
        _audit_gdm_removed || verify_status=1

    _tree_label "Verification — Login Screen  (CIS 1.7.2 – 1.7.3)"
    _audit_tree_row "1.7.2" "Login banner configured" "├─" \
        _audit_gdm_banner || verify_status=1
    _audit_tree_row "1.7.3" "User list disabled" "└─" \
        _audit_gdm_user_list || verify_status=1

    _tree_label "Verification — Screensaver  (CIS 1.7.4 – 1.7.5)"
    _audit_tree_row "1.7.4" "Screen locks when idle" "├─" \
        _audit_gdm_screensaver || verify_status=1
    _audit_tree_row_lock 0 "└─" || verify_status=1

    _tree_label "Verification — Removable Media  (CIS 1.7.6 – 1.7.9)"
    _audit_tree_row "1.7.6" "Automount disabled" "├─" \
        _audit_gdm_automount || verify_status=1
    _audit_tree_row_lock 1 "├─" || verify_status=1
    _audit_tree_row "1.7.8" "Autorun-never enabled" "├─" \
        _audit_gdm_autorun || verify_status=1
    _audit_tree_row_lock 2 "└─" || verify_status=1

    _tree_label "Verification — Display Protocol  (CIS 1.7.10 – 1.7.11)"
    _audit_tree_row "1.7.10" "XDMCP not enabled" "├─" \
        _audit_gdm_xdmcp || verify_status=1
    _audit_tree_row "1.7.11" "Xwayland configured (WaylandEnable=false)" "└─" \
        _audit_gdm_xwayland || verify_status=1

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
    echo "CIS Benchmark Debian 13 - Section 1.7: Configure GNOME Display Manager"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply GDM hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 1.7 GNOME Display Manager — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply GDM hardening)" > /dev/tty
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
    print_section_header "CIS 1.7" "Configure GNOME Display Manager"
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