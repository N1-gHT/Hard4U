#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.1.2 / 6.1.3: Configure rsyslog & Logfiles
#
# Sub-sections covered:
#   6.1.2.1  - Ensure rsyslog is installed                                       (Automated)
#   6.1.2.2  - Ensure rsyslog service is enabled and active                      (Automated)
#   6.1.2.3  - Ensure journald is configured to send logs to rsyslog             (Automated)
#   6.1.2.4  - Ensure rsyslog log file creation mode is configured               (Automated)
#   6.1.2.5  - Ensure rsyslog logging is configured                              (Manual)
#   6.1.2.6  - Ensure rsyslog is configured to send logs to a remote log host    (Manual)
#   6.1.2.7  - Ensure rsyslog is not configured to receive logs from a remote client (Automated)
#   6.1.2.8  - Ensure logrotate is configured                                    (Manual)
#   6.1.2.9  - Ensure rsyslog-gnutls is installed                                (Automated)
#   6.1.2.10 - Ensure rsyslog forwarding uses gtls                               (Automated)
#   6.1.2.11 - Ensure rsyslog CA certificates are configured                     (Manual)
#   6.1.3.1  - Ensure access to all logfiles has been configured                 (Automated)

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------
readonly RSYSLOG_PKG="rsyslog"
readonly RSYSLOG_GNUTLS_PKG="rsyslog-gnutls"
readonly RSYSLOG_SVC="rsyslog.service"

readonly JOURNALD_CIS_CONF="/etc/systemd/journald.conf.d/60-cis-journald.conf"

readonly RSYSLOG_CIS_CONF="/etc/rsyslog.d/60-cis-rsyslog.conf"
readonly RSYSLOG_FILE_CREATE_MODE="0640"
readonly RSYSLOG_FILE_CREATE_MODE_REGEX='0[0-6][0-4]0'
readonly RSYSLOG_FCM_DIRECTIVE='$FileCreateMode'
readonly RSYSLOG_FCM_PATTERN='\$FileCreateMode'

readonly RSYSLOG_REMOTE_HOST="loghost.example.com"
readonly RSYSLOG_CA_FILE="/etc/ssl/certs/ca.pem"

readonly LOGROTATE_CONF="/etc/logrotate.conf"
readonly -a LOGROTATE_PARAMS=(
    "rotate 4"
    "compress"
    "maxage 365"
)

readonly VAR_LOG_DIR="/var/log"

readonly -a RSYSLOG_LOGGING_RULES=(
    'auth,authpriv.*|/var/log/auth.log|^\s*auth,authpriv\.\*\s+[-]?\/var\/log\/auth\.log\b'
    'cron.*|/var/log/cron.log|^\s*cron\.\*\s+[-]?\/var\/log\/cron\.log\b'
    'mail.*|-/var/log/mail.log|^\s*mail\.\*\s+[-]?\/var\/log\/mail\.log\b'
    '*.*;auth,authpriv.none|-/var/log/syslog|^\s*\*\.\*;auth,authpriv\.none\s+[-]?\/var\/log\/syslog\b'
)

readonly RSYSLOG_REMOTE_FWD_DEST="action(type=\"omfwd\" target=\"${RSYSLOG_REMOTE_HOST}\" port=\"514\" protocol=\"tcp\" action.resumeRetryCount=\"100\" queue.type=\"LinkedList\" queue.size=\"1000\")"
readonly RSYSLOG_REMOTE_FWD_REGEX='^\s*\*\.\*\s+action\(type="omfwd"\s+target="[^"]+"'

readonly RSYSLOG_LISTENER_REGEX='^\h*(module\(load="?imtcp"?\)|input\(type="?imtcp"?|\$ModLoad\h+imtcp|\$InputTCPServerRun)'

readonly RSYSLOG_GTLS_GLOBAL='global(DefaultNetstreamDriver="gtls")'
readonly RSYSLOG_GTLS_GLOBAL_REGEX='^\s*global\(DefaultNetstreamDriver="gtls"\)'
readonly RSYSLOG_GTLS_FWD_DEST="action(type=\"omfwd\" target=\"${RSYSLOG_REMOTE_HOST}\" port=\"6514\" protocol=\"tcp\" StreamDriver=\"gtls\" StreamDriverMode=\"1\" StreamDriverAuthMode=\"anon\")"
readonly RSYSLOG_GTLS_FWD_REGEX='^\s*\*\.\*\s+action\(type="omfwd"'

readonly RSYSLOG_CA_GLOBAL="global(DefaultNetstreamDriverCAFile=\"${RSYSLOG_CA_FILE}\")"
readonly RSYSLOG_CA_GLOBAL_REGEX="^\s*global\(DefaultNetstreamDriverCAFile=\"${RSYSLOG_CA_FILE}\"\)"

_JOURNALD_RESTART_NEEDED=false
_RSYSLOG_RESTART_NEEDED=false

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 6.1.2.1 – 6.1.3.1 (12 checks)
# ---------------------------------------------------------------------------
readonly -a RSYSLOG_CHECKS=(
    "6.1.2.1 |_audit_rsyslog_pkg          |_rem_rsyslog_pkg          |rsyslog installed"
    "6.1.2.2 |_audit_rsyslog_svc          |_rem_rsyslog_svc          |rsyslog service enabled and active"
    "6.1.2.3 |_audit_journald_fwd         |_rem_journald_fwd         |journald forwards logs to rsyslog"
    "6.1.2.4 |_audit_rsyslog_file_mode    |_rem_rsyslog_file_mode    |rsyslog FileCreateMode configured"
    "6.1.2.5 |_audit_rsyslog_logging      |_rem_rsyslog_logging      |rsyslog logging rules configured"
    "6.1.2.6 |_audit_rsyslog_remote_fwd   |_rem_rsyslog_remote_fwd   |rsyslog remote forwarding configured"
    "6.1.2.7 |_audit_rsyslog_no_listener  |_rem_rsyslog_no_listener  |rsyslog not receiving remote logs"
    "6.1.2.8 |_audit_logrotate            |_rem_logrotate            |logrotate configured"
    "6.1.2.9 |_audit_rsyslog_gnutls_pkg   |_rem_rsyslog_gnutls_pkg   |rsyslog-gnutls installed"
    "6.1.2.10|_audit_rsyslog_gtls_fwd     |_rem_rsyslog_gtls_fwd     |rsyslog forwarding uses gtls"
    "6.1.2.11|_audit_rsyslog_ca_cert      |_rem_rsyslog_ca_cert      |rsyslog CA certificates configured"
    "6.1.3.1 |_audit_logfile_permissions   |_rem_logfile_permissions   |logfile access configured"
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
# Generic utility helpers
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

_ensure_conf_dir() {
    local conf_file="$1"
    local conf_dir
    conf_dir=$(dirname "$conf_file")
    [[ -d "$conf_dir" ]] || { mkdir -p "$conf_dir"; chmod 755 "$conf_dir"; }
}

_ensure_rsyslog_cis_conf() {
    _ensure_conf_dir "$RSYSLOG_CIS_CONF"
    [[ -f "$RSYSLOG_CIS_CONF" ]] || { touch "$RSYSLOG_CIS_CONF"; chmod 644 "$RSYSLOG_CIS_CONF"; }
}

_ensure_journald_cis_conf() {
    _ensure_conf_dir "$JOURNALD_CIS_CONF"
    if [[ ! -f "$JOURNALD_CIS_CONF" ]]; then
        printf '[Journal]\n' > "$JOURNALD_CIS_CONF"
        chmod 644 "$JOURNALD_CIS_CONF"
    fi
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.1 — rsyslog installed
# ---------------------------------------------------------------------------
_audit_rsyslog_pkg() {
    _is_installed "$RSYSLOG_PKG"
}

_rem_rsyslog_pkg() {
    log_info "Installing ${RSYSLOG_PKG}..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y "$RSYSLOG_PKG" >/dev/null
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.2 — rsyslog service enabled and active
# ---------------------------------------------------------------------------
_audit_rsyslog_svc() {
    local fail=0
    systemctl is-enabled "$RSYSLOG_SVC" 2>/dev/null | grep -q 'enabled' || {
        log_debug "${RSYSLOG_SVC} is NOT enabled"; fail=1
    }
    systemctl is-active "$RSYSLOG_SVC" 2>/dev/null | grep -q '^active' || {
        log_debug "${RSYSLOG_SVC} is NOT active"; fail=1
    }
    return "$fail"
}

_rem_rsyslog_svc() {
    log_info "Unmasking, enabling and starting ${RSYSLOG_SVC}..."
    systemctl unmask "$RSYSLOG_SVC" 2>/dev/null || true
    systemctl --now enable "$RSYSLOG_SVC" >/dev/null
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.3 — journald forwards to rsyslog (ForwardToSyslog=yes)
# ---------------------------------------------------------------------------
_audit_journald_fwd() {
    local current_val
    current_val=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
        | grep -Psi '^\h*ForwardToSyslog\h*=' | tail -1 | cut -d= -f2 | xargs || true)
    if [[ "$current_val" == "yes" ]]; then
        return 0
    fi
    log_debug "journald: ForwardToSyslog='${current_val}' (expected 'yes')"
    return 1
}

_rem_journald_fwd() {
    _ensure_journald_cis_conf
    log_info "journald: ForwardToSyslog=yes"
    if grep -Piq '^\h*#?\h*ForwardToSyslog\h*=' "$JOURNALD_CIS_CONF" 2>/dev/null; then
        sed -i -E 's/^\s*#?\s*ForwardToSyslog\s*=.*/ForwardToSyslog=yes/I' "$JOURNALD_CIS_CONF"
    else
        printf '%s\n' "ForwardToSyslog=yes" >> "$JOURNALD_CIS_CONF"
    fi
    _JOURNALD_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.4 — rsyslog FileCreateMode
# ---------------------------------------------------------------------------
_audit_rsyslog_file_mode() {
    _is_installed "$RSYSLOG_PKG" || return 0

    if grep -Psiq "^\h*${RSYSLOG_FCM_PATTERN}\h+${RSYSLOG_FILE_CREATE_MODE_REGEX}\b" \
            /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        if grep -Psih "^\h*${RSYSLOG_FCM_PATTERN}\b" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null \
                | grep -Psiqv "^\h*${RSYSLOG_FCM_PATTERN}\h+${RSYSLOG_FILE_CREATE_MODE_REGEX}\b"; then
            log_debug "rsyslog: ${RSYSLOG_FCM_DIRECTIVE} has conflicting permissive configurations"
            return 1
        fi
        return 0
    fi
    log_debug "rsyslog: ${RSYSLOG_FCM_DIRECTIVE} not set to match '${RSYSLOG_FILE_CREATE_MODE_REGEX}'"
    return 1
}

_rem_rsyslog_file_mode() {
    _is_installed "$RSYSLOG_PKG" || return 0

    log_info "Setting rsyslog ${RSYSLOG_FCM_DIRECTIVE} → ${RSYSLOG_FILE_CREATE_MODE}"

    local f
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$RSYSLOG_CIS_CONF" ]] && continue
        if grep -Psiq "^\h*${RSYSLOG_FCM_PATTERN}\b" "$f"; then
            sed -i "s/^\([[:space:]]*\\\$FileCreateMode[[:space:]].*\)/# CIS-REMOVED: \1/I" "$f"
        fi
    done < <(find /etc/rsyslog.conf /etc/rsyslog.d/ -type f -name '*.conf' 2>/dev/null)

    _ensure_rsyslog_cis_conf
    if grep -Psiq "^\h*${RSYSLOG_FCM_PATTERN}\b" "$RSYSLOG_CIS_CONF" 2>/dev/null; then
        sed -i "s/^[[:space:]]*\\\$FileCreateMode[[:space:]].*/\$FileCreateMode ${RSYSLOG_FILE_CREATE_MODE}/I" \
            "$RSYSLOG_CIS_CONF"
    else
        printf '%s %s\n' "$RSYSLOG_FCM_DIRECTIVE" "$RSYSLOG_FILE_CREATE_MODE" >> "$RSYSLOG_CIS_CONF"
    fi
    _RSYSLOG_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.5 — rsyslog logging rules (auth, cron, mail, syslog)
# ---------------------------------------------------------------------------
_audit_rsyslog_logging() {
    _is_installed "$RSYSLOG_PKG" || return 0

    local fail=0
    for entry in "${RSYSLOG_LOGGING_RULES[@]}"; do
        local regex="${entry##*|}"
        if ! grep -Psiq "$regex" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
            log_debug "rsyslog logging rule not found: ${regex}"
            fail=1
        fi
    done
    return "$fail"
}

_rem_rsyslog_logging() {
    _is_installed "$RSYSLOG_PKG" || return 0

    _ensure_rsyslog_cis_conf
    for entry in "${RSYSLOG_LOGGING_RULES[@]}"; do
        local selector="${entry%%|*}"
        local rest="${entry#*|}"
        local dest="${rest%%|*}"
        local regex="${rest##*|}"

        if ! grep -Psiq "$regex" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
            log_info "Adding rsyslog rule: ${selector} → ${dest}"
            printf '%s\t%s\n' "$selector" "$dest" >> "$RSYSLOG_CIS_CONF"
        fi
    done
    _RSYSLOG_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.6 — rsyslog remote forwarding
# ---------------------------------------------------------------------------
_audit_rsyslog_remote_fwd() {
    _is_installed "$RSYSLOG_PKG" || return 0

    if grep -Psiq "$RSYSLOG_REMOTE_FWD_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        return 0
    fi
    log_debug "rsyslog remote forwarding rule not found"
    return 1
}

_rem_rsyslog_remote_fwd() {
    _is_installed "$RSYSLOG_PKG" || return 0

    _ensure_rsyslog_cis_conf
    log_info "Adding rsyslog remote forwarding rule → ${RSYSLOG_REMOTE_HOST}:514"
    printf '%s\t%s\n' '*.*' "$RSYSLOG_REMOTE_FWD_DEST" >> "$RSYSLOG_CIS_CONF"
    _RSYSLOG_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.7 — rsyslog not receiving remote logs (no imtcp listener)
# ---------------------------------------------------------------------------
_audit_rsyslog_no_listener() {
    _is_installed "$RSYSLOG_PKG" || return 0

    if grep -Psiq -- "$RSYSLOG_LISTENER_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_debug "rsyslog is configured to LISTEN (imtcp detected)"
        return 1
    fi
    return 0
}

_rem_rsyslog_no_listener() {
    _is_installed "$RSYSLOG_PKG" || return 0

    log_info "Disabling rsyslog listener configuration..."
    local files_to_fix
    files_to_fix=$(grep -Pl -- "$RSYSLOG_LISTENER_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null || true)

    local f
    for f in $files_to_fix; do
        [[ -n "$f" ]] || continue
        log_info "Commenting out listener directives in ${f}..."
        sed -i -E "s/(${RSYSLOG_LISTENER_REGEX})/# CIS-REMOVED: \1/I" "$f" || {
            log_error "Failed to edit ${f}"
            return 1
        }
    done
    _RSYSLOG_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.8 — logrotate configured
# ---------------------------------------------------------------------------
_audit_logrotate() {
    _is_installed "logrotate" || return 0

    local fail=0
    for param in "${LOGROTATE_PARAMS[@]}"; do
        local key="${param%% *}"
        if ! grep -Piq "^\h*${key}\b" "$LOGROTATE_CONF" 2>/dev/null; then
            log_debug "Logrotate parameter '${key}' missing from ${LOGROTATE_CONF}"
            fail=1
        fi
    done
    return "$fail"
}

_rem_logrotate() {
    log_info "Configuring logrotate parameters in ${LOGROTATE_CONF}..."
    for param in "${LOGROTATE_PARAMS[@]}"; do
        local key="${param%% *}"
        if grep -Piq "^\h*#?\h*${key}\b" "$LOGROTATE_CONF" 2>/dev/null; then
            sed -i -E "s/^\s*#?\s*${key}.*/${param}/I" "$LOGROTATE_CONF"
        else
            printf '%s\n' "$param" >> "$LOGROTATE_CONF"
        fi
    done
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.9 — rsyslog-gnutls installed
# ---------------------------------------------------------------------------
_audit_rsyslog_gnutls_pkg() {
    _is_installed "$RSYSLOG_GNUTLS_PKG"
}

_rem_rsyslog_gnutls_pkg() {
    log_info "Installing ${RSYSLOG_GNUTLS_PKG}..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y "$RSYSLOG_GNUTLS_PKG" >/dev/null
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.10 — rsyslog forwarding uses gtls (global + action)
# ---------------------------------------------------------------------------
_audit_rsyslog_gtls_fwd() {
    _is_installed "$RSYSLOG_PKG" || return 0

    local fail=0
    if ! grep -Psiq "$RSYSLOG_GTLS_GLOBAL_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_debug "rsyslog gtls global directive not found"
        fail=1
    fi
    if ! grep -Psiq "$RSYSLOG_GTLS_FWD_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_debug "rsyslog gtls forwarding action not found"
        fail=1
    fi
    return "$fail"
}

_rem_rsyslog_gtls_fwd() {
    _is_installed "$RSYSLOG_PKG" || return 0

    _ensure_rsyslog_cis_conf
    if ! grep -Psiq "$RSYSLOG_GTLS_GLOBAL_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_info "Adding rsyslog gtls global directive"
        printf '%s\n' "$RSYSLOG_GTLS_GLOBAL" >> "$RSYSLOG_CIS_CONF"
    fi
    if ! grep -Psiq "$RSYSLOG_GTLS_FWD_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_info "Adding rsyslog gtls forwarding action → ${RSYSLOG_REMOTE_HOST}:6514"
        printf '%s\t%s\n' '*.*' "$RSYSLOG_GTLS_FWD_DEST" >> "$RSYSLOG_CIS_CONF"
    fi
    _RSYSLOG_RESTART_NEEDED=true
}

# ---------------------------------------------------------------------------
# CIS 6.1.2.11 — rsyslog CA certificates configured
# ---------------------------------------------------------------------------
_audit_rsyslog_ca_cert() {
    _is_installed "$RSYSLOG_PKG" || return 0

    local fail=0
    if ! grep -Psiq "$RSYSLOG_CA_GLOBAL_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_debug "rsyslog CA certificate global directive not found"
        fail=1
    fi
    if [[ ! -f "$RSYSLOG_CA_FILE" ]]; then
        log_debug "CA certificate file missing: ${RSYSLOG_CA_FILE}"
        fail=1
    fi
    return "$fail"
}

_rem_rsyslog_ca_cert() {
    _is_installed "$RSYSLOG_PKG" || return 0

    _ensure_rsyslog_cis_conf
    if ! grep -Psiq "$RSYSLOG_CA_GLOBAL_REGEX" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_info "Adding rsyslog CA certificate global directive"
        printf '%s\n' "$RSYSLOG_CA_GLOBAL" >> "$RSYSLOG_CIS_CONF"
        _RSYSLOG_RESTART_NEEDED=true
    fi
    if [[ ! -f "$RSYSLOG_CA_FILE" ]]; then
        log_warn "CA certificate file '${RSYSLOG_CA_FILE}' does not exist — manual action required."
    fi
}

# ---------------------------------------------------------------------------
# CIS 6.1.3.1 — logfile access (/var/log permissions)
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

_audit_logfile_permissions() { _manage_var_log_permissions "audit"; }
_rem_logfile_permissions()   { _manage_var_log_permissions "remediate"; }

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#RSYSLOG_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${RSYSLOG_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        (( ++current_row ))
        if [[ $current_row -eq $total_rows ]]; then branch="└─"; else branch="├─"; fi
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

    _run_audit_checks "rsyslog & Logfiles  (CIS 6.1.2.1 – 6.1.3.1)" || global_status=1

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
    _RSYSLOG_RESTART_NEEDED=false

    for entry in "${RSYSLOG_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        if ! "$audit_func"; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            "$rem_func" || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} — already compliant."
        fi
    done

    if [[ "$_RSYSLOG_RESTART_NEEDED" == "true" ]]; then
        log_info "Restarting rsyslog to apply configuration..."
        systemctl restart rsyslog 2>/dev/null || any_failure=true
    fi
    if [[ "$_JOURNALD_RESTART_NEEDED" == "true" ]]; then
        log_info "Restarting systemd-journald to apply configuration..."
        systemctl reload-or-restart systemd-journald 2>/dev/null || any_failure=true
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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.1.2.1 – 6.1.3.1)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.1.2 / 6.1.3: Configure rsyslog & Logfiles"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply rsyslog & logfile hardening."
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
    echo -e "\n${C_BOLD}--- CIS 6.1.2/6.1.3 rsyslog & Logfiles — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply rsyslog hardening)" > /dev/tty
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
    print_section_header "CIS 6.1.2/6.1.3" "Configure rsyslog & Logfiles"
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