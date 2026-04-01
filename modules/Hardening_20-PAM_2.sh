#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.3.3: Configure PAM Arguments
#
# Sub-sections covered:
#   5.3.3.1 Configure pam_faillock module
#     5.3.3.1.1 - Ensure password failed attempts lockout is configured  (deny)
#     5.3.3.1.2 - Ensure password unlock time is configured              (unlock_time)
#     5.3.3.1.3 - Ensure failed attempts lockout includes root           (even_deny_root)
#   5.3.3.2 Configure pam_pwquality module
#     5.3.3.2.1 - Ensure number of changed characters is configured      (difok)
#     5.3.3.2.2 - Ensure password length is configured                   (minlen)
#     5.3.3.2.3 - Ensure password complexity is configured               (Manual)
#     5.3.3.2.4 - Ensure same consecutive characters is configured       (maxrepeat)
#     5.3.3.2.5 - Ensure maximum sequential characters is configured     (maxsequence)
#     5.3.3.2.6 - Ensure password dictionary check is enabled            (dictcheck)
#     5.3.3.2.7 - Ensure password quality checking is enforced           (enforcing)
#     5.3.3.2.8 - Ensure password quality is enforced for root           (enforce_for_root)
#   5.3.3.3 Configure pam_pwhistory module
#     5.3.3.3.1 - Ensure password history remember is configured         (remember)
#     5.3.3.3.2 - Ensure password history is enforced for root           (enforce_for_root)
#     5.3.3.3.3 - Ensure pam_pwhistory includes use_authtok              (use_authtok)
#   5.3.3.4 Configure pam_unix module
#     5.3.3.4.1 - Ensure pam_unix does not include nullok
#     5.3.3.4.2 - Ensure pam_unix does not include remember
#     5.3.3.4.3 - Ensure pam_unix includes a strong hashing algorithm

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
readonly FAILLOCK_CONF="/etc/security/faillock.conf"

readonly PWQUALITY_CONF_MAIN="/etc/security/pwquality.conf"
readonly PWQUALITY_CONF_DIR="/etc/security/pwquality.conf.d"
readonly PWQUALITY_CIS_FILE="${PWQUALITY_CONF_DIR}/50-cis-pwquality.conf"

readonly PWHISTORY_CONF="/etc/security/pwhistory.conf"

readonly PAM_COMMON_FILE=(
    "/etc/pam.d/common-account"
    "/etc/pam.d/common-auth"
    "/etc/pam.d/common-password"
    "/etc/pam.d/common-session"
    "/etc/pam.d/common-session-noninteractive"
)

# ---------------------------------------------------------------------------
# DATA-DRIVEN array -- CIS 5.3.3.1.1 through 5.3.3.4.3 (17 checks)
# ---------------------------------------------------------------------------
readonly -a PAM2_CHECKS=(
    "5.3.3.1.1|_audit_fl_deny          |_rem_fl_deny          |faillock deny=5 configured"
    "5.3.3.1.2|_audit_fl_unlock_time   |_rem_fl_unlock_time   |faillock unlock_time=900 configured"
    "5.3.3.1.3|_audit_fl_even_deny_root|_rem_fl_even_deny_root|faillock even_deny_root configured"
    "5.3.3.2.1|_audit_pwq_difok        |_rem_pwq_difok        |pwquality difok=2 configured"
    "5.3.3.2.2|_audit_pwq_minlen       |_rem_pwq_minlen       |pwquality minlen=14 configured"
    "5.3.3.2.3|MANUAL                  |MANUAL                |pwquality complexity (Manual review)"
    "5.3.3.2.4|_audit_pwq_maxrepeat    |_rem_pwq_maxrepeat    |pwquality maxrepeat=3 configured"
    "5.3.3.2.5|_audit_pwq_maxsequence  |_rem_pwq_maxsequence  |pwquality maxsequence=3 configured"
    "5.3.3.2.6|_audit_pwq_dictcheck    |_rem_pwq_dictcheck    |pwquality dictcheck=1 configured"
    "5.3.3.2.7|_audit_pwq_enforcing    |_rem_pwq_enforcing    |pwquality enforcing=1 configured"
    "5.3.3.2.8|_audit_pwq_enforce_root |_rem_pwq_enforce_root |pwquality enforce_for_root configured"
    "5.3.3.3.1|_audit_pwh_remember     |_rem_pwh_remember     |pwhistory remember=24 configured"
    "5.3.3.3.2|_audit_pwh_enforce_root |_rem_pwh_enforce_root |pwhistory enforce_for_root configured"
    "5.3.3.3.3|_audit_pwh_use_authtok  |_rem_pwh_use_authtok  |pwhistory use_authtok configured"
    "5.3.3.4.1|_audit_unix_no_nullok   |_rem_unix_no_nullok   |pam_unix nullok absent"
    "5.3.3.4.2|_audit_unix_no_remember |_rem_unix_no_remember |pam_unix remember= absent"
    "5.3.3.4.3|_audit_unix_strong_hash |_rem_unix_strong_hash |pam_unix strong hash (sha512/yescrypt)"
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
# INFO / SKIP entries are excluded from the pass/fail denominator.
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
        [[ "$st" == "INFO" ]] && row_color="${C_DIM}"
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
    local cis_id="$1" desc="$2" branch="$3"
    printf "  %s %-48s  " "$branch" "$desc"
    echo -e "${C_BLUE}[INFO]${C_RESET}"
    record_result "$cis_id" "$desc" "INFO"
}

# ---------------------------------------------------------------------------
# Generic helpers: faillock.conf
# ---------------------------------------------------------------------------
_audit_faillock_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val=""
    [[ "$config" == *"="* ]] && expected_val="${config#*=}"

    if [[ -n "$expected_val" ]]; then
        if ! grep -Piq "^\h*${key}\h*=\h*${expected_val}\b" "$FAILLOCK_CONF" 2>/dev/null; then
            log_debug "faillock.conf: '${key}' not set to '${expected_val}'"
            return 1
        fi
    else
        if ! grep -Piq "^\h*${key}\b" "$FAILLOCK_CONF" 2>/dev/null; then
            log_debug "faillock.conf: flag '${key}' missing or commented"
            return 1
        fi
    fi

    if grep -Plq "\bpam_faillock\.so\b.*\b${key}\b" /usr/share/pam-configs/* 2>/dev/null; then
        log_debug "faillock: '${key}' overridden in /usr/share/pam-configs/"
        return 1
    fi
    return 0
}

_remediate_faillock_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val=""
    [[ "$config" == *"="* ]] && expected_val="${config#*=}"
    local pam_changed=false

    if [[ ! -f "$FAILLOCK_CONF" ]]; then
        touch "$FAILLOCK_CONF"
        chmod 644 "$FAILLOCK_CONF"
        chown root:root "$FAILLOCK_CONF"
    fi

    if [[ -n "$expected_val" ]]; then
        if grep -Piq "^\h*#?\h*${key}\b" "$FAILLOCK_CONF" 2>/dev/null; then
            sed -i -E "s/^\s*#?\s*${key}\s*(.*)/${key} = ${expected_val}/I" "$FAILLOCK_CONF"
        else
            printf '%s\n' "${key} = ${expected_val}" >> "$FAILLOCK_CONF"
        fi
    else
        if grep -Piq "^\h*#\h*${key}\b" "$FAILLOCK_CONF" 2>/dev/null; then
            sed -i -E "s/^\s*#\s*${key}\b/${key}/I" "$FAILLOCK_CONF"
        elif ! grep -Piq "^\h*${key}\b" "$FAILLOCK_CONF" 2>/dev/null; then
            printf '%s\n' "${key}" >> "$FAILLOCK_CONF"
        fi
    fi

    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        log_info "Removing override '${key}' from PAM profile: ${f}"
        sed -i -E "/pam_faillock\.so/ s/\b${key}(=[^[:space:]]+)?//Ig" "$f"
        pam_changed=true
    done < <(grep -Pl "\bpam_faillock\.so\b.*\b${key}\b" \
                /usr/share/pam-configs/* 2>/dev/null || true)

    if [[ "$pam_changed" == "true" ]]; then
        log_info "Updating PAM configuration..."
        env DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Generic helpers: pwquality conf files
# ---------------------------------------------------------------------------
_pwquality_conf_files() {
    local -n _out="$1"
    _out=()
    [[ -f "$PWQUALITY_CONF_MAIN" ]] && _out+=("$PWQUALITY_CONF_MAIN")
    if [[ -d "$PWQUALITY_CONF_DIR" ]]; then
        while IFS= read -r -d '' f; do
            _out+=("$f")
        done < <(find "$PWQUALITY_CONF_DIR" -name "*.conf" -print0 2>/dev/null)
    fi
}

_audit_pwquality_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val=""
    [[ "$config" == *"="* ]] && expected_val="${config#*=}"

    local -a conf_files=()
    _pwquality_conf_files conf_files
    if [[ "${#conf_files[@]}" -eq 0 ]]; then
        log_debug "pwquality: no conf files found"
        return 1
    fi

    if [[ -n "$expected_val" ]]; then
        if ! grep -Piq "^\h*${key}\h*=\h*${expected_val}\b" \
                "${conf_files[@]}" 2>/dev/null; then
            log_debug "pwquality: '${key}' not set to '${expected_val}'"
            return 1
        fi
    else
        if ! grep -Piq "^\h*${key}\b" "${conf_files[@]}" 2>/dev/null; then
            log_debug "pwquality: flag '${key}' missing"
            return 1
        fi
    fi

    if grep -Plq "\bpam_pwquality\.so\b.*\b${key}\b" \
            /usr/share/pam-configs/* 2>/dev/null; then
        log_debug "pwquality: '${key}' overridden in /usr/share/pam-configs/"
        return 1
    fi
    return 0
}

_remediate_pwquality_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val=""
    [[ "$config" == *"="* ]] && expected_val="${config#*=}"
    local pam_changed=false

    if [[ ! -d "$PWQUALITY_CONF_DIR" ]]; then
        mkdir -p "$PWQUALITY_CONF_DIR"
        chmod 755 "$PWQUALITY_CONF_DIR"
    fi
    if [[ ! -f "$PWQUALITY_CIS_FILE" ]]; then
        touch "$PWQUALITY_CIS_FILE"
        chmod 644 "$PWQUALITY_CIS_FILE"
    fi

    if [[ -f "$PWQUALITY_CONF_MAIN" ]]; then
        sed -i -E "s/^\s*${key}\b/# \0/I" "$PWQUALITY_CONF_MAIN" 2>/dev/null || true
    fi

    if [[ -n "$expected_val" ]]; then
        if grep -Piq "^\h*#?\h*${key}\b" "$PWQUALITY_CIS_FILE" 2>/dev/null; then
            sed -i -E "s/^\s*#?\s*${key}\s*(.*)/${key} = ${expected_val}/I" "$PWQUALITY_CIS_FILE"
        else
            printf '%s\n' "${key} = ${expected_val}" >> "$PWQUALITY_CIS_FILE"
        fi
    else
        if grep -Piq "^\h*#\h*${key}\b" "$PWQUALITY_CIS_FILE" 2>/dev/null; then
            sed -i -E "s/^\s*#\s*${key}\b/${key}/I" "$PWQUALITY_CIS_FILE"
        elif ! grep -Piq "^\h*${key}\b" "$PWQUALITY_CIS_FILE" 2>/dev/null; then
            printf '%s\n' "${key}" >> "$PWQUALITY_CIS_FILE"
        fi
    fi

    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        log_info "Removing override '${key}' from PAM profile: ${f}"
        sed -i -E "/pam_pwquality\.so/ s/\b${key}(=[^[:space:]]+)?//Ig" "$f"
        pam_changed=true
    done < <(grep -Pl "\bpam_pwquality\.so\b.*\b${key}\b" \
                /usr/share/pam-configs/* 2>/dev/null || true)

    if [[ "$pam_changed" == "true" ]]; then
        log_info "Updating PAM configuration..."
        env DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Generic helpers: pwhistory.conf
# ---------------------------------------------------------------------------
_audit_pwhistory_param() {
    local config="$1"
    local key="${config%%=*}"
    local expected_val=""
    [[ "$config" == *"="* ]] && expected_val="${config#*=}"

    if [[ -n "$expected_val" ]]; then
        if ! grep -Piq "^\h*${key}\h*=\h*${expected_val}\b" \
                "$PWHISTORY_CONF" 2>/dev/null; then
            log_debug "pwhistory: '${key}' not set to '${expected_val}'"
            return 1
        fi
    else
        if ! grep -Piq "^\h*${key}\b" "$PWHISTORY_CONF" 2>/dev/null; then
            log_debug "pwhistory: flag '${key}' missing"
            return 1
        fi
    fi

    if grep -Plq "\bpam_pwhistory\.so\b.*\b${key}\b" \
            /usr/share/pam-configs/* 2>/dev/null; then
        log_debug "pwhistory: '${key}' overridden in /usr/share/pam-configs/"
        return 1
    fi
    return 0
}

_remediate_pwhistory_param() {
    local config="$1"
    local key="${config%%=*}"
    local val=""
    [[ "$config" == *"="* ]] && val="${config#*=}"
    local pam_changed=false

    if [[ ! -f "$PWHISTORY_CONF" ]]; then
        touch "$PWHISTORY_CONF"
        chmod 644 "$PWHISTORY_CONF"
        chown root:root "$PWHISTORY_CONF"
    fi

    if [[ -n "$val" ]]; then
        if grep -Piq "^\h*#?\h*${key}\b" "$PWHISTORY_CONF" 2>/dev/null; then
            sed -i -E "s/^\s*#?\s*${key}\s*(.*)/${key} = ${val}/I" "$PWHISTORY_CONF"
        else
            printf '%s\n' "${key} = ${val}" >> "$PWHISTORY_CONF"
        fi
    else
        if grep -Piq "^\h*#\h*${key}\b" "$PWHISTORY_CONF" 2>/dev/null; then
            sed -i -E "s/^\s*#\s*${key}\b/${key}/I" "$PWHISTORY_CONF"
        elif ! grep -Piq "^\h*${key}\b" "$PWHISTORY_CONF" 2>/dev/null; then
            printf '%s\n' "${key}" >> "$PWHISTORY_CONF"
        fi
    fi

    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        log_info "Removing override '${key}' from PAM profile: ${f}"
        sed -i -E "/pam_pwhistory\.so/ s/\b${key}(=[^[:space:]]+)?//Ig" "$f"
        sed -i -E 's/[[:space:]]+/ /g' "$f"
        pam_changed=true
    done < <(grep -Pl "\bpam_pwhistory\.so\b.*\b${key}\b" \
                /usr/share/pam-configs/* 2>/dev/null || true)

    if [[ "$pam_changed" == "true" ]]; then
        log_info "Updating PAM configuration..."
        env DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Generic helpers: pam_unix forbidden / required args
# ---------------------------------------------------------------------------
_audit_pam_forbidden_arg() {
    local module="$1" arg_regex="$2"; shift 2
    local files=("$@")
    if grep -PHsq -- "^\h*[^#\n\r]+\h+${module}\h+([^#\n\r]+\h+)?${arg_regex}\b" \
            "${files[@]}" 2>/dev/null; then
        log_debug "Forbidden arg '${arg_regex}' found for ${module}"
        return 1
    fi
    return 0
}

_remediate_pam_remove_arg() {
    local module="$1" arg_regex="$2"
    local pam_configs_dir="/usr/share/pam-configs"
    local changed=false

    while IFS= read -r prof; do
        [[ -f "$prof" ]] || continue
        log_info "Sanitizing PAM profile '${prof}' (removing '${arg_regex}')..."
        sed -i -E "/${module}/ s/[[:space:]]*\b${arg_regex}\b//g" "$prof"
        sed -i -E 's/[[:space:]]+/ /g' "$prof"
        changed=true
    done < <(grep -lP "^\h*([^#\n\r]+\h+)?${module}\h+([^#\n\r]+\h+)?${arg_regex}\b" \
                "$pam_configs_dir"/* 2>/dev/null || true)

    if [[ "$changed" == "true" ]]; then
        log_info "Updating system PAM configuration..."
        env DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi
    return 0
}

_audit_pam_unix_required_arg() {
    local arg_regex="$1"
    if grep -Pq \
            "^\h*password\h+([^#\n\r]+)\h+pam_unix\.so\h+([^#\n\r]+\h+)?${arg_regex}\b" \
            /etc/pam.d/common-password 2>/dev/null; then
        return 0
    fi
    log_debug "Required arg '${arg_regex}' missing for pam_unix.so"
    return 1
}

_remediate_pam_unix_password_args() {
    local pam_configs_dir="/usr/share/pam-configs"
    local changed=false

    while IFS= read -r prof; do
        [[ -f "$prof" ]] || continue
        log_info "Enforcing strong hash and use_authtok in ${prof}..."

        sed -i -E '/pam_unix\.so/ s/\b(md5|bigcrypt|sha256|blowfish|gost_yescrypt)\b//g' \
            "$prof"

        awk '
            /^Password:/         { in_pwd=1; in_pwd_init=0; print; next }
            /^Password-Initial:/ { in_pwd_init=1; in_pwd=0; print; next }
            /^[a-zA-Z]/          { in_pwd=0; in_pwd_init=0 }
            {
                if ((in_pwd || in_pwd_init) && /pam_unix\.so/) {
                    if ($0 !~ /(sha512|yescrypt)/) { $0 = $0 "\tyescrypt" }
                    if (in_pwd && $0 !~ /use_authtok/) { $0 = $0 "\tuse_authtok" }
                }
                print
            }
        ' "$prof" > "${prof}.tmp" && mv "${prof}.tmp" "$prof"

        sed -i -E 's/[[:space:]]+/ /g; s/ $//' "$prof"
        changed=true
    done < <(awk '
        /Password-Type:/{ f=1; next }
        /^[a-zA-Z]/{ if($1!~/^Password/){f=0} }
        f { if (/pam_unix\.so/) print FILENAME }
        ' "$pam_configs_dir"/* 2>/dev/null | sort -u || true)

    if [[ "$changed" == "true" ]]; then
        log_info "Updating system PAM configuration..."
        env DEBIAN_FRONTEND=noninteractive pam-auth-update --package
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.3.3.1 -- faillock thin wrappers
# ---------------------------------------------------------------------------
_audit_fl_deny()           { _audit_faillock_param    "deny=5"; }
_rem_fl_deny()             { _remediate_faillock_param "deny=5"; }

_audit_fl_unlock_time()    { _audit_faillock_param    "unlock_time=900"; }
_rem_fl_unlock_time()      { _remediate_faillock_param "unlock_time=900"; }

_audit_fl_even_deny_root() { _audit_faillock_param    "even_deny_root"; }
_rem_fl_even_deny_root()   { _remediate_faillock_param "even_deny_root"; }

# ---------------------------------------------------------------------------
# CIS 5.3.3.2 -- pwquality thin wrappers
# FIX: original "dickcheck=1" -- corrected to "dictcheck=1"
# ---------------------------------------------------------------------------
_audit_pwq_difok()        { _audit_pwquality_param    "difok=2"; }
_rem_pwq_difok()          { _remediate_pwquality_param "difok=2"; }

_audit_pwq_minlen()       { _audit_pwquality_param    "minlen=14"; }
_rem_pwq_minlen()         { _remediate_pwquality_param "minlen=14"; }

# 5.3.3.2.3 is Manual -- no audit/rem wrappers needed (MANUAL sentinel in array)

_audit_pwq_maxrepeat()    { _audit_pwquality_param    "maxrepeat=3"; }
_rem_pwq_maxrepeat()      { _remediate_pwquality_param "maxrepeat=3"; }

_audit_pwq_maxsequence()  { _audit_pwquality_param    "maxsequence=3"; }
_rem_pwq_maxsequence()    { _remediate_pwquality_param "maxsequence=3"; }

_audit_pwq_dictcheck()    { _audit_pwquality_param    "dictcheck=1"; }
_rem_pwq_dictcheck()      { _remediate_pwquality_param "dictcheck=1"; }

_audit_pwq_enforcing()    { _audit_pwquality_param    "enforcing=1"; }
_rem_pwq_enforcing()      { _remediate_pwquality_param "enforcing=1"; }

_audit_pwq_enforce_root() { _audit_pwquality_param    "enforce_for_root"; }
_rem_pwq_enforce_root()   { _remediate_pwquality_param "enforce_for_root"; }

# ---------------------------------------------------------------------------
# CIS 5.3.3.3 -- pwhistory thin wrappers
# ---------------------------------------------------------------------------
_audit_pwh_remember()     { _audit_pwhistory_param    "remember=24"; }
_rem_pwh_remember()       { _remediate_pwhistory_param "remember=24"; }

_audit_pwh_enforce_root() { _audit_pwhistory_param    "enforce_for_root"; }
_rem_pwh_enforce_root()   { _remediate_pwhistory_param "enforce_for_root"; }

_audit_pwh_use_authtok()  { _audit_pwhistory_param    "use_authtok"; }
_rem_pwh_use_authtok()    { _remediate_pwhistory_param "use_authtok"; }

# ---------------------------------------------------------------------------
# CIS 5.3.3.4 -- pam_unix thin wrappers
# ---------------------------------------------------------------------------
_audit_unix_no_nullok()   { _audit_pam_forbidden_arg "pam_unix.so" "nullok"        "${PAM_COMMON_FILE[@]}"; }
_rem_unix_no_nullok()     { _remediate_pam_remove_arg "pam_unix.so" "nullok"; }

_audit_unix_no_remember() { _audit_pam_forbidden_arg "pam_unix.so" "remember=[0-9]+" "${PAM_COMMON_FILE[@]}"; }
_rem_unix_no_remember()   { _remediate_pam_remove_arg "pam_unix.so" "remember=[0-9]+"; }

_audit_unix_strong_hash() { _audit_pam_unix_required_arg "(sha512|yescrypt)"; }
_rem_unix_strong_hash()   { _remediate_pam_unix_password_args; }

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# Handles the MANUAL sentinel: renders [INFO] without PASS/FAIL.
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#PAM2_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${PAM2_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"
        (( ++current_row ))
        if [[ $current_row -eq $total_rows ]]; then branch="└─"; else branch="├─"; fi

        if [[ "$audit_func" == "MANUAL" ]]; then
            _audit_tree_row_manual "$cis_id" "$desc" "$branch"
        else
            _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
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

    _run_audit_checks "PAM Arguments  (CIS 5.3.3.1.1 - 5.3.3.4.3)" || global_status=1

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

    for entry in "${PAM2_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
        rem_func="${rem_func// /}"

        if [[ "$audit_func" == "MANUAL" ]]; then
            log_info "[${cis_id}] Manual check -- organizational review required."
            continue
        fi

        if ! "$audit_func"; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            "$rem_func" || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} -- already compliant."
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.3.3.1.1 - 5.3.3.4.3)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.3.3: Configure PAM Arguments"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply PAM argument hardening."
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
    echo -e "\n${C_BOLD}--- CIS 5.3.3 PAM Arguments -- Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply PAM argument hardening)" > /dev/tty
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
    print_section_header "CIS 5.3.3" "Configure PAM Arguments"
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