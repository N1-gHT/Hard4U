#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.1.1: Configure journald
#
# Sub-sections covered:
#   6.1.1.1.1 - Ensure journald service is active                        (Automated)
#   6.1.1.1.2 - Ensure journald log file access is configured            (Manual)
#   6.1.1.1.3 - Ensure journald log file rotation is configured          (Manual)
#   6.1.1.1.4 - Ensure journald ForwardToSyslog is disabled              (Automated)
#   6.1.1.1.5 - Ensure journald Storage is configured                    (Automated)
#   6.1.1.1.6 - Ensure journald Compress is configured                   (Automated)
#   6.1.1.2.1 - Ensure systemd-journal-remote is installed               (Automated)
#   6.1.1.2.2 - Ensure systemd-journal-upload authentication configured  (Manual)
#   6.1.1.2.3 - Ensure systemd-journal-upload is enabled and active      (Automated)
#   6.1.1.2.4 - Ensure systemd-journal-remote is not in use              (Automated)

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
readonly JOURNALD_SVC="systemd-journald.service"
readonly JOURNALD_CIS_CONF="/etc/systemd/journald.conf.d/60-cis-journald.conf"

readonly JOURNALD_ROTATION_PARAMS=(
    "SystemMaxUse=1G"
    "SystemKeepFree=500M"
    "RuntimeMaxUse=200M"
    "RuntimeKeepFree=50M"
    "MaxFileSec=1month"
)

readonly TMPFILES_SRC="/usr/lib/tmpfiles.d/systemd.conf"
readonly TMPFILES_OVERRIDE="/etc/tmpfiles.d/systemd.conf"

readonly JOURNAL_REMOTE_PKG="systemd-journal-remote"

readonly JOURNAL_UPLOAD_SVC="systemd-journal-upload.service"
readonly JOURNAL_UPLOAD_CIS_CONF="/etc/systemd/journal-upload.conf.d/60-cis-journal-upload.conf"

readonly -a JOURNAL_REMOTE_LISTENERS=(
    "systemd-journal-remote.socket"
    "systemd-journal-remote.service"
)

readonly JOURNAL_UPLOAD_URL="192.168.50.42"
readonly JOURNAL_UPLOAD_KEY="/etc/ssl/private/journal-upload.pem"
readonly JOURNAL_UPLOAD_CERT="/etc/ssl/certs/journal-upload.pem"
readonly JOURNAL_UPLOAD_CA="/etc/ssl/ca/trusted.pem"
readonly JOURNAL_UPLOAD_PARAMS=(
    "URL=${JOURNAL_UPLOAD_URL}"
    "ServerKeyFile=${JOURNAL_UPLOAD_KEY}"
    "ServerCertificateFile=${JOURNAL_UPLOAD_CERT}"
    "TrustedCertificateFile=${JOURNAL_UPLOAD_CA}"
)

readonly VAR_LOG_DIR="/var/log"

_JOURNALD_RESTART_NEEDED=false
_UPLOAD_RESTART_NEEDED=false

# ---------------------------------------------------------------------------
# DATA-DRIVEN array -- CIS 6.1.1.1.1 through 6.1.1.2.4 (10 checks, all automated)
# ---------------------------------------------------------------------------
readonly -a JOURNALD_CHECKS=(
    "6.1.1.1.1|_audit_journald_service      |_rem_journald_service      |journald service active"
    "6.1.1.1.2|_audit_log_file_access        |_rem_log_file_access       |journald log file access configured"
    "6.1.1.1.3|_audit_journald_rotation      |_rem_journald_rotation     |journald log file rotation configured"
    "6.1.1.1.4|_audit_jd_forward_to_syslog  |_rem_jd_forward_to_syslog  |journald ForwardToSyslog=no"
    "6.1.1.1.5|_audit_jd_storage            |_rem_jd_storage            |journald Storage=persistent"
    "6.1.1.1.6|_audit_jd_compress           |_rem_jd_compress           |journald Compress=yes"
    "6.1.1.2.1|_audit_journal_remote_pkg    |_rem_journal_remote_pkg    |systemd-journal-remote installed"
    "6.1.1.2.2|_audit_journal_upload_auth    |_rem_journal_upload_auth   |journal-upload authentication configured"
    "6.1.1.2.3|_audit_journal_upload_svc    |_rem_journal_upload_svc    |journal-upload enabled and active"
    "6.1.1.2.4|_audit_journal_remote_listener|_rem_journal_remote_listener|journal-remote not in use"
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
    local total=$(( pass_count + fail_count ))

    local W_ID=10 W_DESC=44 W_ST=6
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
        printf "  %s %-46s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-46s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# ---------------------------------------------------------------------------
# Generic helpers: journald.conf parameters
# ---------------------------------------------------------------------------
_audit_journald_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    local current_val
    current_val=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
        | grep -Psi "^\h*${key}\h*=" | tail -1 | cut -d= -f2 | xargs || true)

    if [[ "$current_val" == "$expected_val" ]]; then
        return 0
    fi
    log_debug "journald: '${key}' is '${current_val}' (expected '${expected_val}')"
    return 1
}

_remediate_journald_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    local conf_dir; conf_dir=$(dirname "$JOURNALD_CIS_CONF")
    [[ -d "$conf_dir" ]] || { mkdir -p "$conf_dir"; chmod 755 "$conf_dir"; }
    if [[ ! -f "$JOURNALD_CIS_CONF" ]]; then
        printf '[Journal]\n' > "$JOURNALD_CIS_CONF"
        chmod 644 "$JOURNALD_CIS_CONF"
    fi

    log_info "journald: ${key}=${expected_val}"
    if grep -Piq "^\h*#?\h*${key}\h*=" "$JOURNALD_CIS_CONF" 2>/dev/null; then
        sed -i -E "s/^\s*#?\s*${key}\s*=.*/${key}=${expected_val}/I" "$JOURNALD_CIS_CONF"
    else
        printf '%s\n' "${key}=${expected_val}" >> "$JOURNALD_CIS_CONF"
    fi
}

# ---------------------------------------------------------------------------
# Generic helpers: journal-upload.conf parameters
# ---------------------------------------------------------------------------
_audit_journal_upload_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    local current_val
    current_val=$(systemd-analyze cat-config systemd/journal-upload.conf 2>/dev/null \
        | grep -Psi "^\h*${key}\h*=" | tail -1 | cut -d= -f2 | xargs || true)

    if [[ "$current_val" == "$expected_val" ]]; then
        return 0
    fi
    log_debug "journal-upload: '${key}' is '${current_val}' (expected '${expected_val}')"
    return 1
}

_remediate_journal_upload_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val="${config#*=}"

    local conf_dir; conf_dir=$(dirname "$JOURNAL_UPLOAD_CIS_CONF")
    [[ -d "$conf_dir" ]] || { mkdir -p "$conf_dir"; chmod 755 "$conf_dir"; }
    if [[ ! -f "$JOURNAL_UPLOAD_CIS_CONF" ]]; then
        printf '[Upload]\n' > "$JOURNAL_UPLOAD_CIS_CONF"
        chmod 644 "$JOURNAL_UPLOAD_CIS_CONF"
    fi

    log_info "journal-upload: ${key}=${expected_val}"
    if grep -Piq "^\h*#?\h*${key}\h*=" "$JOURNAL_UPLOAD_CIS_CONF" 2>/dev/null; then
        sed -i -E "s|^\s*#?\s*${key}\s*=.*|${key}=${expected_val}|I" "$JOURNAL_UPLOAD_CIS_CONF"
    else
        printf '%s\n' "${key}=${expected_val}" >> "$JOURNAL_UPLOAD_CIS_CONF"
    fi
}

# ---------------------------------------------------------------------------
# Compound audit/remediation wrappers for CIS 6.1.1.1.2, 6.1.1.1.3, 6.1.1.2.2
# ---------------------------------------------------------------------------

_audit_log_file_access() {
    local fail=0
    _audit_journald_log_access || fail=1
    _audit_var_log_permissions  || fail=1
    return "$fail"
}
_rem_log_file_access() {
    local fail=0
    _rem_journald_log_access || fail=1
    _rem_var_log_permissions  || fail=1
    return "$fail"
}

_audit_journald_rotation() {
    local fail=0
    for config in "${JOURNALD_ROTATION_PARAMS[@]}"; do
        _audit_journald_param "$config" || fail=1
    done
    return "$fail"
}
_rem_journald_rotation() {
    for config in "${JOURNALD_ROTATION_PARAMS[@]}"; do
        _remediate_journald_param "$config"
    done
    _JOURNALD_RESTART_NEEDED=true
}

_audit_journal_upload_auth() {
    local fail=0
    for config in "${JOURNAL_UPLOAD_PARAMS[@]}"; do
        _audit_journal_upload_param "$config" || fail=1
    done
    return "$fail"
}
_rem_journal_upload_auth() {
    for config in "${JOURNAL_UPLOAD_PARAMS[@]}"; do
        _remediate_journal_upload_param "$config"
    done
    _UPLOAD_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.1.1 -- journald service active
# ---------------------------------------------------------------------------
_audit_journald_service() {
    if systemctl is-active --quiet "$JOURNALD_SVC" 2>/dev/null; then
        return 0
    fi
    log_debug "${JOURNALD_SVC} is NOT active"
    return 1
}

_rem_journald_service() {
    log_info "Unmasking and enabling ${JOURNALD_SVC}..."
    systemctl unmask "$JOURNALD_SVC" 2>/dev/null || true
    if systemctl --now enable "$JOURNALD_SVC"; then
        return 0
    fi
    log_error "Failed to enable/start ${JOURNALD_SVC}"
    return 1
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.1.2 -- journald log file access (Manual)
# ---------------------------------------------------------------------------
_audit_journald_log_access() {
    local fail=0
    local config_files=("$TMPFILES_OVERRIDE" "$TMPFILES_SRC")

    for file in "${config_files[@]}"; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            local type path perm _rest
            read -r type path perm _rest <<< "$line"
            if [[ "$type" == "f" && "$perm" =~ ^0?[0-7]{3,4}$ ]]; then
                if [[ -f "$path" ]]; then
                    local actual_perm
                    actual_perm=$(stat -c "%a" "$path" 2>/dev/null || true)
                    if [[ -n "$actual_perm" && "$actual_perm" -gt 640 ]]; then
                        log_debug "File ${path} has permissive permissions: ${actual_perm} (max 640)"
                        fail=1
                    fi
                fi
            fi
        done < <(grep -v '^\s*#' "$file" 2>/dev/null || true)
        break
    done
    return "$fail"
}

_rem_journald_log_access() {
    if [[ ! -f "$TMPFILES_OVERRIDE" ]]; then
        if [[ -f "$TMPFILES_SRC" ]]; then
            log_info "Creating override file ${TMPFILES_OVERRIDE}..."
            mkdir -p "$(dirname "$TMPFILES_OVERRIDE")"
            cp -a "$TMPFILES_SRC" "$TMPFILES_OVERRIDE"
        else
            log_error "Source ${TMPFILES_SRC} not found; cannot remediate automatically."
            return 1
        fi
    fi

    log_info "Securing file rules in ${TMPFILES_OVERRIDE} to 0640 max..."
    sed -i -E '/^f\s/ s/([[:space:]])0?6(4[1-7]|5[0-7]|6[0-7]|7[0-7])([[:space:]])/\10640\3/g' \
        "$TMPFILES_OVERRIDE"

    log_info "Applying permissions to existing log files..."
    while IFS= read -r line; do
        local type path perm _rest
        read -r type path perm _rest <<< "$line"
        if [[ "$type" == "f" && "$perm" =~ ^0?[0-7]{3,4}$ && -f "$path" ]]; then
            local actual_perm
            actual_perm=$(stat -c "%a" "$path" 2>/dev/null || true)
            if [[ -n "$actual_perm" && "$actual_perm" -gt 640 ]]; then
                chmod 0640 "$path"
            fi
        fi
    done < <(grep -v '^\s*#' "$TMPFILES_OVERRIDE" 2>/dev/null || true)

    systemd-tmpfiles --create >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.1.4-6 -- journald parameter thin wrappers
# ---------------------------------------------------------------------------
_audit_jd_forward_to_syslog() {
    if systemctl is-active --quiet rsyslog.service 2>/dev/null; then
        log_debug "rsyslog is active — ForwardToSyslog=yes is expected, skipping =no check"
        return 0
    fi
    _audit_journald_param "ForwardToSyslog=no"
}
_rem_jd_forward_to_syslog()   {
    _remediate_journald_param "ForwardToSyslog=no"
    _JOURNALD_RESTART_NEEDED=true
}

_audit_jd_storage()  { _audit_journald_param "Storage=persistent"; }
_rem_jd_storage()    {
    _remediate_journald_param "Storage=persistent"
    _JOURNALD_RESTART_NEEDED=true
}

_audit_jd_compress() { _audit_journald_param "Compress=yes"; }
_rem_jd_compress()   {
    _remediate_journald_param "Compress=yes"
    _JOURNALD_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.2.1 -- systemd-journal-remote installed
# ---------------------------------------------------------------------------
_audit_journal_remote_pkg() {
    if _is_installed "$JOURNAL_REMOTE_PKG"; then
        return 0
    fi
    log_debug "Package '${JOURNAL_REMOTE_PKG}' is NOT installed"
    return 1
}

_rem_journal_remote_pkg() {
    log_info "Installing ${JOURNAL_REMOTE_PKG}..."
    apt-get update -q 2>/dev/null || true
    apt-get install -y "$JOURNAL_REMOTE_PKG"
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.2.3 -- systemd-journal-upload enabled and active
# ---------------------------------------------------------------------------
_audit_journal_upload_svc() {
    if ! systemctl is-enabled "$JOURNAL_UPLOAD_SVC" 2>/dev/null | grep -q 'enabled'; then
        log_debug "${JOURNAL_UPLOAD_SVC} is NOT enabled"
        return 1
    fi
    if ! systemctl is-active "$JOURNAL_UPLOAD_SVC" 2>/dev/null | grep -q '^active'; then
        log_warn "${JOURNAL_UPLOAD_SVC} is enabled but NOT active — check URL/certificates configuration"
    fi
    return 0
}

_rem_journal_upload_svc() {
    log_info "Unmasking and enabling ${JOURNAL_UPLOAD_SVC}..."
    systemctl unmask "$JOURNAL_UPLOAD_SVC" 2>/dev/null || true
    if systemctl --now enable "$JOURNAL_UPLOAD_SVC"; then
        return 0
    fi
    log_error "Failed to enable ${JOURNAL_UPLOAD_SVC}"
    return 1
}

# ---------------------------------------------------------------------------
# CIS 6.1.1.2.4 -- systemd-journal-remote not in use
# ---------------------------------------------------------------------------
_audit_journal_remote_listener() {
    local fail=0
    for svc in "${JOURNAL_REMOTE_LISTENERS[@]}"; do
        if systemctl is-enabled "$svc" 2>/dev/null | grep -q 'enabled'; then
            log_debug "Listener service ${svc} is ENABLED"
            fail=1
        fi
        if systemctl is-active "$svc" 2>/dev/null | grep -q '^active'; then
            log_debug "Listener service ${svc} is ACTIVE"
            fail=1
        fi
    done
    return "$fail"
}

_rem_journal_remote_listener() {
    log_info "Stopping and masking journal-remote listener services..."
    local fail=0
    for svc in "${JOURNAL_REMOTE_LISTENERS[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl mask "$svc" 2>/dev/null || { log_error "Failed to mask ${svc}"; fail=1; }
    done
    return "$fail"
}

# ---------------------------------------------------------------------------
# /var/log/ file permissions
# ---------------------------------------------------------------------------
_manage_var_log_permissions() {
    local mode="$1"
    local global_fail=0

    while IFS= read -r -d $'\0' l_file; do
        local l_fname l_mode l_user l_group
        IFS=: read -r l_fname l_mode l_user l_group \
            <<< "$(stat -Lc '%n:%#a:%U:%G' "$l_file" 2>/dev/null || true)"
        [[ -z "$l_fname" ]] && continue

        local perm_mask l_auser l_agroup l_rperms
        local l_fix_account='root'
        local file_fail=0

        if grep -Pq -- '\/(apt)\h*$' <<< "$(dirname "$l_fname")"; then
            perm_mask='0133'; l_rperms="u-x,go-wx"; l_auser="root"; l_agroup="(root|adm)"
        else
            case "$(basename "$l_fname")" in
                lastlog* | wtmp* | btmp* | README)
                    perm_mask='0113'; l_rperms="ug-x,o-wx"; l_auser="root"; l_agroup="(root|utmp)" ;;
                cloud-init.log* | localmessages* | waagent.log*)
                    perm_mask='0133'; l_rperms="u-x,go-wx"; l_auser="(root|syslog)"; l_agroup="(root|adm)" ;;
                secure* | auth.log | syslog | messages)
                    perm_mask='0137'; l_rperms="u-x,g-wx,o-rwx"; l_auser="(root|syslog)"; l_agroup="(root|adm)" ;;
                *.journal | *.journal~)
                    perm_mask='0137'; l_rperms="u-x,g-wx,o-rwx"; l_auser="root"; l_agroup="(root|systemd-journal)" ;;
                *)
                    perm_mask='0137'; l_rperms="u-x,g-wx,o-rwx"; l_auser="(root|syslog)"; l_agroup="(root|adm)"
                    if [[ "$l_user" == "root" ]] || \
                       ! grep -Pq -- "^\h*$(awk -F: '$1=="'"$l_user"'" {print $7}' \
                            /etc/passwd 2>/dev/null)\b" /etc/shells 2>/dev/null; then
                        grep -Pq -- "$l_auser" <<< "$l_user" \
                            || l_auser="(root|syslog|${l_user})"
                        grep -Pq -- "$l_agroup" <<< "$l_group" \
                            || l_agroup="(root|adm|${l_group})"
                    fi ;;
            esac
        fi

        (( 8#${l_mode:-0} & 8#${perm_mask:-0} )) && file_fail=1
        [[ ! "$l_user"  =~ $l_auser  ]]           && file_fail=1
        [[ ! "$l_group" =~ $l_agroup ]]            && file_fail=1

        if [[ "$file_fail" -eq 1 ]]; then
            global_fail=1
            if [[ "$mode" == "remediate" ]]; then
                log_info "Fixing permissions/ownership: ${l_fname}"
                (( 8#${l_mode:-0} & 8#${perm_mask:-0} )) && chmod "$l_rperms" "$l_fname"
                [[ ! "$l_user"  =~ $l_auser  ]] && chown "$l_fix_account" "$l_fname"
                [[ ! "$l_group" =~ $l_agroup ]] && chgrp "$l_fix_account" "$l_fname"
            else
                log_debug "Insecure: ${l_fname} (${l_mode} ${l_user}:${l_group})"
            fi
        fi
    done < <(find -L "$VAR_LOG_DIR" -type f \
        \( -perm /0137 -o ! -user root -o ! -group root \) -print0 2>/dev/null)

    return "$global_fail"
}

_audit_var_log_permissions()    { _manage_var_log_permissions "audit"; }
_rem_var_log_permissions()      { _manage_var_log_permissions "remediate"; }

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#JOURNALD_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${JOURNALD_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        (( ++current_row ))
        if [[ $current_row -eq $total_rows ]]; then branch="└─"; else branch="├─"; fi

        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func"             || global_status=1
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

    _run_audit_checks "journald  (CIS 6.1.1.1.1 - 6.1.1.2.4)" || global_status=1

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
    _JOURNALD_RESTART_NEEDED=false
    _UPLOAD_RESTART_NEEDED=false

    for entry in "${JOURNALD_CHECKS[@]}"; do
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

    if [[ "$_JOURNALD_RESTART_NEEDED" == "true" ]]; then
        log_info "Restarting ${JOURNALD_SVC} to apply configuration..."
        systemctl restart systemd-journald 2>/dev/null || any_failure=true
    fi
    if [[ "$_UPLOAD_RESTART_NEEDED" == "true" ]]; then
        log_info "Restarting ${JOURNAL_UPLOAD_SVC} to apply configuration..."
        systemctl restart systemd-journal-upload 2>/dev/null || true
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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.1.1.1.1 - 6.1.1.2.4)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.1.1: Configure journald"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply journald hardening."
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
    echo -e "\n${C_BOLD}--- CIS 6.1.1 journald -- Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply journald hardening)" > /dev/tty
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
    print_section_header "CIS 6.1.1" "Configure journald"
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