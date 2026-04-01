#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.1: Configure SSH Server (parameters)
#
# Sub-sections covered:
#   5.1.6  - Ensure sshd Ciphers are configured
#   5.1.7  - Ensure sshd ClientAliveInterval and ClientAliveCountMax are configured
#   5.1.8  - Ensure sshd DisableForwarding is enabled
#   5.1.9  - Ensure sshd GSSAPIAuthentication is disabled
#   5.1.10 - Ensure sshd HostbasedAuthentication is disabled
#   5.1.11 - Ensure sshd IgnoreRhosts is enabled
#   5.1.12 - Ensure sshd KexAlgorithms is configured
#   5.1.13 - Ensure sshd post-quantum cryptography key exchange algorithms are configured
#   5.1.14 - Ensure sshd LoginGraceTime is configured
#   5.1.15 - Ensure sshd LogLevel is configured
#   5.1.16 - Ensure sshd MACs are configured
#   5.1.17 - Ensure sshd MaxAuthTries is configured
#   5.1.18 - Ensure sshd MaxSessions is configured
#   5.1.19 - Ensure sshd MaxStartups is configured
#   5.1.20 - Ensure sshd PermitEmptyPasswords is disabled
#   5.1.21 - Ensure sshd PermitRootLogin is disabled
#   5.1.22 - Ensure sshd PermitUserEnvironment is disabled
#   5.1.23 - Ensure sshd UsePAM is enabled

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
# shellcheck disable=SC2034  # Unused variables left for readability
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
readonly SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
readonly SSH_CONF="${SSHD_CONFIG_DIR}/50-cis.conf"

readonly SSH_WEAK_CIPHERS_REGEX='(3des|blowfish|cast128|aes(128|192|256))-cbc|arcfour(128|256)?|rijndael-cbc@lysator\.liu\.se|chacha20-poly1305@openssh\.com'
readonly SSH_APPROVED_CIPHERS="aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr"
readonly SSH_WEAK_KEX_REGEX='diffie-hellman-group1-sha1|diffie-hellman-group14-sha1|diffie-hellman-group-exchange-sha1'
readonly SSH_APPROVED_KEX="sntrup761x25519-sha512@openssh.com,sntrup761x25519-sha512,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256"
readonly SSH_WEAK_MACS_REGEX='(hmac-md5|hmac-md5-96|hmac-ripemd160|hmac-sha1-96|umac-64@openssh\.com|hmac-md5-etm@openssh\.com|hmac-md5-96-etm@openssh\.com|hmac-ripemd160-etm@openssh\.com|hmac-sha1-96-etm@openssh\.com|umac-64-etm@openssh\.com)'
readonly SSH_APPROVED_MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com"
readonly SSH_PQC_ALGO="sntrup761x25519-sha512"

readonly SSH_ALIVE_INTERVAL="15"
readonly SSH_ALIVE_COUNT="3"
readonly SSH_DISABLE_FORWARDING="yes"
readonly SSH_GSSAPI_AUTH="no"
readonly SSH_HOSTBASED_AUTH="no"
readonly SSH_IGNORE_RHOSTS="yes"
readonly SSH_LOGIN_GRACE_TIME="60"
readonly SSH_LOG_LEVEL="VERBOSE"
readonly SSH_MAX_AUTH_TRIES="4"
readonly SSH_MAX_SESSIONS="5"
readonly SSH_MAX_STARTUPS="10:30:60"
readonly SSH_PERMIT_EMPTY_PASSWORDS="no"
readonly SSH_PERMIT_ROOT_LOGIN="no"
readonly SSH_PERMIT_USER_ENV="no"
readonly SSH_USE_PAM="yes"

# ---------------------------------------------------------------------------
# DATA-DRIVEN array
#
# SSH_CONF_CHECKS — CIS 5.1.6 – 5.1.23 (18 checks)
# ---------------------------------------------------------------------------
readonly -a SSH_CONF_CHECKS=(
    "5.1.6 |_audit_sshd_ciphers            |_rem_sshd_ciphers            |sshd Ciphers configured"
    "5.1.7 |_audit_sshd_timeouts           |_rem_sshd_timeouts           |sshd ClientAlive timeouts configured"
    "5.1.8 |_audit_sshd_disable_forwarding |_rem_sshd_disable_forwarding |sshd DisableForwarding enabled"
    "5.1.9 |_audit_sshd_gssapi_auth        |_rem_sshd_gssapi_auth        |sshd GSSAPIAuthentication disabled"
    "5.1.10|_audit_sshd_hostbased_auth     |_rem_sshd_hostbased_auth     |sshd HostbasedAuthentication disabled"
    "5.1.11|_audit_sshd_ignore_rhosts      |_rem_sshd_ignore_rhosts      |sshd IgnoreRhosts enabled"
    "5.1.12|_audit_sshd_kex               |_rem_sshd_kex                |sshd KexAlgorithms configured"
    "5.1.13|_audit_sshd_pqc_kex           |_rem_sshd_pqc_kex            |sshd post-quantum KexAlgorithms configured"
    "5.1.14|_audit_sshd_login_grace_time   |_rem_sshd_login_grace_time   |sshd LoginGraceTime configured"
    "5.1.15|_audit_sshd_log_level          |_rem_sshd_log_level          |sshd LogLevel configured"
    "5.1.16|_audit_sshd_macs              |_rem_sshd_macs               |sshd MACs configured"
    "5.1.17|_audit_sshd_max_auth_tries     |_rem_sshd_max_auth_tries     |sshd MaxAuthTries configured"
    "5.1.18|_audit_sshd_max_sessions       |_rem_sshd_max_sessions       |sshd MaxSessions configured"
    "5.1.19|_audit_sshd_max_startups       |_rem_sshd_max_startups       |sshd MaxStartups configured"
    "5.1.20|_audit_sshd_permit_empty_pw    |_rem_sshd_permit_empty_pw    |sshd PermitEmptyPasswords disabled"
    "5.1.21|_audit_sshd_permit_root_login  |_rem_sshd_permit_root_login  |sshd PermitRootLogin disabled"
    "5.1.22|_audit_sshd_permit_user_env    |_rem_sshd_permit_user_env    |sshd PermitUserEnvironment disabled"
    "5.1.23|_audit_sshd_use_pam           |_rem_sshd_use_pam            |sshd UsePAM enabled"
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

    local W_ID=9 W_DESC=50 W_ST=6
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

# ---------------------------------------------------------------------------
# Generic utility helpers
# ---------------------------------------------------------------------------
_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

_sshd_get_config() {
    local param="$1"
    sshd -T 2>/dev/null | grep -Pi "^${param}\s+" | awk '{print $2}' | xargs || true
}

_update_cis_ssh_conf() {
    local param="$1" value="$2"
    [[ -d "$SSHD_CONFIG_DIR" ]] || mkdir -p "$SSHD_CONFIG_DIR"
    [[ -f "$SSH_CONF" ]]        || touch "$SSH_CONF"

    if grep -qPi "^[[:space:]]*${param}[[:space:]]" "$SSH_CONF" 2>/dev/null; then
        sed -i "s|^[[:space:]]*${param}[[:space:]].*|${param} ${value}|I" "$SSH_CONF"
    else
        printf '%s %s\n' "$param" "$value" >> "$SSH_CONF"
    fi

    chmod 600 "$SSH_CONF"
    chown root:root "$SSH_CONF"
}

# ---------------------------------------------------------------------------
# Generic audit helpers (DRY — used by the thin wrappers below)
# ---------------------------------------------------------------------------

_audit_sshd_eq() {
    local sshd_param="$1" expected="$2"
    local val; val=$(_sshd_get_config "$sshd_param")
    if [[ "$val" == "$expected" ]]; then
        return 0
    fi
    log_debug "${sshd_param}='${val}' (expected '${expected}')"
    return 1
}

_audit_sshd_no_weak() {
    local sshd_param="$1" weak_regex="$2"
    local val; val=$(_sshd_get_config "$sshd_param")
    if [[ -z "$val" ]]; then
        log_debug "${sshd_param} is absent from sshd -T output"
        return 1
    fi
    if echo "$val" | grep -Piq "$weak_regex"; then
        log_debug "Weak ${sshd_param} detected: ${val}"
        return 1
    fi
    return 0
}
_remediate_sshd_param() {
    _is_installed "$SSH_PACKAGE" || return 0
    local conf_key="$1" value="$2"
    log_info "Setting ${conf_key} → ${value}"
    _update_cis_ssh_conf "$conf_key" "$value"
    systemctl reload sshd 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# CIS 5.1.6 — Ciphers (no weak algorithms)
# ---------------------------------------------------------------------------
_audit_sshd_ciphers() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_no_weak "ciphers" "$SSH_WEAK_CIPHERS_REGEX"
}
_rem_sshd_ciphers() { _remediate_sshd_param "Ciphers" "$SSH_APPROVED_CIPHERS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.7 — ClientAliveInterval and ClientAliveCountMax (both > 0)
# ---------------------------------------------------------------------------
_audit_sshd_timeouts() {
    _is_installed "$SSH_PACKAGE" || return 0
    local interval count
    interval=$(_sshd_get_config "clientaliveinterval")
    count=$(_sshd_get_config "clientalivecountmax")
    if [[ ! "$interval" =~ ^[0-9]+$ || ! "$count" =~ ^[0-9]+$ ]]; then
        log_debug "ClientAliveInterval='${interval}' or ClientAliveCountMax='${count}' not numeric"
        return 1
    fi
    if [[ "$interval" -gt 0 && "$count" -gt 0 ]]; then
        return 0
    fi
    log_debug "ClientAliveInterval=${interval} ClientAliveCountMax=${count} (both must be >0)"
    return 1
}
_rem_sshd_timeouts() {
    _is_installed "$SSH_PACKAGE" || return 0
    log_info "Setting ClientAliveInterval → ${SSH_ALIVE_INTERVAL}"
    _update_cis_ssh_conf "ClientAliveInterval" "$SSH_ALIVE_INTERVAL"
    log_info "Setting ClientAliveCountMax → ${SSH_ALIVE_COUNT}"
    _update_cis_ssh_conf "ClientAliveCountMax" "$SSH_ALIVE_COUNT"
    systemctl reload sshd 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# CIS 5.1.8 — DisableForwarding yes
# ---------------------------------------------------------------------------
_audit_sshd_disable_forwarding() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "disableforwarding" "yes"
}
_rem_sshd_disable_forwarding() { _remediate_sshd_param "DisableForwarding" "$SSH_DISABLE_FORWARDING"; }

# ---------------------------------------------------------------------------
# CIS 5.1.9 — GSSAPIAuthentication no
# ---------------------------------------------------------------------------
_audit_sshd_gssapi_auth() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "gssapiauthentication" "no"
}
_rem_sshd_gssapi_auth() { _remediate_sshd_param "GSSAPIAuthentication" "$SSH_GSSAPI_AUTH"; }

# ---------------------------------------------------------------------------
# CIS 5.1.10 — HostbasedAuthentication no
# ---------------------------------------------------------------------------
_audit_sshd_hostbased_auth() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "hostbasedauthentication" "no"
}
_rem_sshd_hostbased_auth() { _remediate_sshd_param "HostbasedAuthentication" "$SSH_HOSTBASED_AUTH"; }

# ---------------------------------------------------------------------------
# CIS 5.1.11 — IgnoreRhosts yes
# ---------------------------------------------------------------------------
_audit_sshd_ignore_rhosts() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "ignorerhosts" "yes"
}
_rem_sshd_ignore_rhosts() { _remediate_sshd_param "IgnoreRhosts" "$SSH_IGNORE_RHOSTS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.12 — KexAlgorithms (no weak algorithms)
# ---------------------------------------------------------------------------
_audit_sshd_kex() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_no_weak "kexalgorithms" "$SSH_WEAK_KEX_REGEX"
}
_rem_sshd_kex() { _remediate_sshd_param "KexAlgorithms" "$SSH_APPROVED_KEX"; }

# ---------------------------------------------------------------------------
# CIS 5.1.13 — Post-quantum KexAlgorithms (sntrup761x25519-sha512 present)
# ---------------------------------------------------------------------------
_audit_sshd_pqc_kex() {
    _is_installed "$SSH_PACKAGE" || return 0
    local kex; kex=$(_sshd_get_config "kexalgorithms")
    if echo "$kex" | grep -q "$SSH_PQC_ALGO"; then
        return 0
    fi
    log_debug "PQC algorithm '${SSH_PQC_ALGO}' absent from KexAlgorithms: ${kex}"
    return 1
}
_rem_sshd_pqc_kex() { _remediate_sshd_param "KexAlgorithms" "$SSH_APPROVED_KEX"; }

# ---------------------------------------------------------------------------
# CIS 5.1.14 — LoginGraceTime between 1 and 60 seconds
# ---------------------------------------------------------------------------
_audit_sshd_login_grace_time() {
    _is_installed "$SSH_PACKAGE" || return 0
    local val; val=$(_sshd_get_config "logingracetime")
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        log_debug "LoginGraceTime='${val}' not numeric"
        return 1
    fi
    if [[ "$val" -ge 1 && "$val" -le 60 ]]; then
        return 0
    fi
    log_debug "LoginGraceTime=${val} (expected 1–60)"
    return 1
}
_rem_sshd_login_grace_time() { _remediate_sshd_param "LoginGraceTime" "$SSH_LOGIN_GRACE_TIME"; }

# ---------------------------------------------------------------------------
# CIS 5.1.15 — LogLevel INFO or VERBOSE
# ---------------------------------------------------------------------------
_audit_sshd_log_level() {
    _is_installed "$SSH_PACKAGE" || return 0
    local val; val=$(_sshd_get_config "loglevel")
    val="${val^^}"
    if [[ "$val" == "INFO" || "$val" == "VERBOSE" ]]; then
        return 0
    fi
    log_debug "LogLevel='${val}' (expected INFO or VERBOSE)"
    return 1
}
_rem_sshd_log_level() { _remediate_sshd_param "LogLevel" "$SSH_LOG_LEVEL"; }

# ---------------------------------------------------------------------------
# CIS 5.1.16 — MACs (no weak algorithms)
# ---------------------------------------------------------------------------
_audit_sshd_macs() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_no_weak "macs" "$SSH_WEAK_MACS_REGEX"
}
_rem_sshd_macs() { _remediate_sshd_param "MACs" "$SSH_APPROVED_MACS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.17 — MaxAuthTries <= 4
# ---------------------------------------------------------------------------
_audit_sshd_max_auth_tries() {
    _is_installed "$SSH_PACKAGE" || return 0
    local val; val=$(_sshd_get_config "maxauthtries")
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        log_debug "MaxAuthTries='${val}' not numeric"
        return 1
    fi
    if [[ "$val" -le 4 ]]; then
        return 0
    fi
    log_debug "MaxAuthTries=${val} (expected ≤4)"
    return 1
}
_rem_sshd_max_auth_tries() { _remediate_sshd_param "MaxAuthTries" "$SSH_MAX_AUTH_TRIES"; }

# ---------------------------------------------------------------------------
# CIS 5.1.18 — MaxSessions <= 5
# ---------------------------------------------------------------------------
_audit_sshd_max_sessions() {
    _is_installed "$SSH_PACKAGE" || return 0
    local val; val=$(_sshd_get_config "maxsessions")
    if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        log_debug "MaxSessions='${val}' not numeric"
        return 1
    fi
    if [[ "$val" -le 5 ]]; then
        return 0
    fi
    log_debug "MaxSessions=${val} (expected ≤5)"
    return 1
}
_rem_sshd_max_sessions() { _remediate_sshd_param "MaxSessions" "$SSH_MAX_SESSIONS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.19 — MaxStartups <= 10:30:60
# ---------------------------------------------------------------------------
_audit_sshd_max_startups() {
    _is_installed "$SSH_PACKAGE" || return 0
    local val; val=$(_sshd_get_config "maxstartups")
    if [[ -z "$val" ]]; then
        log_debug "maxstartups absent from sshd -T output"
        return 1
    fi
    local a b c
    IFS=':' read -r a b c <<< "$val"
    if [[ ! "$a" =~ ^[0-9]+$ || ! "$b" =~ ^[0-9]+$ || ! "$c" =~ ^[0-9]+$ ]]; then
        log_debug "MaxStartups='${val}' malformed (expected N:N:N)"
        return 1
    fi
    if [[ "$a" -le 10 && "$b" -le 30 && "$c" -le 60 ]]; then
        return 0
    fi
    log_debug "MaxStartups=${val} (expected ≤10:30:60)"
    return 1
}
_rem_sshd_max_startups() { _remediate_sshd_param "MaxStartups" "$SSH_MAX_STARTUPS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.20 — PermitEmptyPasswords no
# ---------------------------------------------------------------------------
_audit_sshd_permit_empty_pw() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "permitemptypasswords" "no"
}
_rem_sshd_permit_empty_pw() { _remediate_sshd_param "PermitEmptyPasswords" "$SSH_PERMIT_EMPTY_PASSWORDS"; }

# ---------------------------------------------------------------------------
# CIS 5.1.21 — PermitRootLogin no
# ---------------------------------------------------------------------------
_audit_sshd_permit_root_login() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "permitrootlogin" "no"
}
_rem_sshd_permit_root_login() { _remediate_sshd_param "PermitRootLogin" "$SSH_PERMIT_ROOT_LOGIN"; }

# ---------------------------------------------------------------------------
# CIS 5.1.22 — PermitUserEnvironment no
# ---------------------------------------------------------------------------
_audit_sshd_permit_user_env() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "permituserenvironment" "no"
}
_rem_sshd_permit_user_env() { _remediate_sshd_param "PermitUserEnvironment" "$SSH_PERMIT_USER_ENV"; }

# ---------------------------------------------------------------------------
# CIS 5.1.23 — UsePAM yes
# ---------------------------------------------------------------------------
_audit_sshd_use_pam() {
    _is_installed "$SSH_PACKAGE" || return 0
    _audit_sshd_eq "usepam" "yes"
}
_rem_sshd_use_pam() { _remediate_sshd_param "UsePAM" "$SSH_USE_PAM"; }


_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#SSH_CONF_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${SSH_CONF_CHECKS[@]}"; do
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

    _run_audit_checks "SSH Server Parameters  (CIS 5.1.6 – 5.1.23)" || global_status=1

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

    for entry in "${SSH_CONF_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.1.6 – 5.1.23)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.1: Configure SSH Server (parameters)"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply SSH server parameter hardening."
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
    echo -e "\n${C_BOLD}--- CIS 5.1 SSH Parameters — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply SSH parameter hardening)" > /dev/tty
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
    print_section_header "CIS 5.1" "Configure SSH Server Parameters"
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