#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 5.4: User Accounts and Environment
#
# Sub-sections covered:
#   5.4.1.1 - Ensure password expiration is configured           (PASS_MAX_DAYS)
#   5.4.1.2 - Ensure minimum password days is configured         (Manual)
#   5.4.1.3 - Ensure password expiration warning days            (PASS_WARN_AGE)
#   5.4.1.4 - Ensure strong password hashing algorithm           (ENCRYPT_METHOD)
#   5.4.1.5 - Ensure inactive password lock is configured        (INACTIVE)
#   5.4.1.6 - Ensure all users last password change is in past
#   5.4.2.1 - Ensure root is the only UID 0 account
#   5.4.2.2 - Ensure root is the only GID 0 account
#   5.4.2.3 - Ensure group root is the only GID 0 group
#   5.4.2.4 - Ensure root account access is controlled
#   5.4.2.5 - Ensure root path integrity
#   5.4.2.6 - Ensure root user umask is configured
#   5.4.2.7 - Ensure system accounts do not have a valid login shell
#   5.4.2.8 - Ensure accounts without a valid login shell are locked
#   5.4.3.1 - Ensure nologin is not listed in /etc/shells
#   5.4.3.2 - Ensure default user shell timeout is configured
#   5.4.3.3 - Ensure default user umask is configured

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
readonly LOGIN_DEFS_ENCRYPT_METHOD="YESCRYPT"

readonly ROOT_UMASK_FILES=("/root/.profile" "/root/.bashrc")
readonly ROOT_BAD_UMASK_REGEX='^\h*umask\h+((\d{1,2}(\d[^7]|[^2-7]\d)\b)|(u=[rwx]{1,3},)?(((g=[rx]?[rx]?w[rx]?[rx]?\b)(,o=[rwx]{1,3})?)|((g=[wrx]{1,3},)?o=[rwx]{1,3}\b)))'

readonly SYSTEM_ACCOUNTS_EXEMPT='^(root|sync|shutdown|halt|nologin|nobody)$'
UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs 2>/dev/null || echo 1000)
readonly UID_MIN
VALID_SHELLS_REGEX="^($(awk -F/ '$NF != "nologin" && $NF != "false" {print}' \
    /etc/shells 2>/dev/null | paste -sd '|' -))$"
readonly VALID_SHELLS_REGEX

readonly ETC_SHELLS="/etc/shells"
readonly TMOUT_VALUE="900"
readonly TMOUT_FILE="/etc/profile.d/50-cis-tmout.sh"
readonly SHELL_CONFIG_FILES=("/etc/profile" "/etc/bash.bashrc")

readonly SYS_UMASK="027"
readonly UMASK_PROFILE_FILE="/etc/profile.d/55-cis-umask.sh"
readonly PERMISSIVE_UMASK_REGEX='^\s*umask\s+0?(0[01][0-7]|0[0-7][^7]|[^0][0-7][0-7])(\s*|\s+.*)$'

# ---------------------------------------------------------------------------
# DATA-DRIVEN array -- CIS 5.4.1.1 through 5.4.3.3 (17 checks)
# ---------------------------------------------------------------------------
readonly -a ACCOUNTS_CHECKS=(
    "5.4.1.1|_audit_shadow_pass_max   |_rem_shadow_pass_max   |shadow PASS_MAX_DAYS<=365"
    "5.4.1.2|MANUAL                   |MANUAL                 |shadow PASS_MIN_DAYS (Manual)"
    "5.4.1.3|_audit_shadow_warn_age   |_rem_shadow_warn_age   |shadow PASS_WARN_AGE>=7"
    "5.4.1.4|_audit_encrypt_method    |_rem_encrypt_method    |ENCRYPT_METHOD strong hash"
    "5.4.1.5|_audit_shadow_inactive   |_rem_shadow_inactive   |shadow INACTIVE<=45"
    "5.4.1.6|_audit_last_pw_past      |_rem_last_pw_past      |last password change in past"
    "5.4.2.1|_audit_root_uid_zero     |_rem_root_uid_zero     |root is only UID 0 account"
    "5.4.2.2|_audit_root_gid_zero     |_rem_root_gid_zero     |root is only GID 0 account"
    "5.4.2.3|_audit_root_grp_zero     |_rem_root_grp_zero     |root is only GID 0 group"
    "5.4.2.4|_audit_root_pw_status    |_rem_root_pw_status    |root access controlled"
    "5.4.2.5|_audit_root_path         |_rem_root_path         |root PATH integrity"
    "5.4.2.6|_audit_root_umask        |_rem_root_umask        |root user umask secure"
    "5.4.2.7|_audit_sys_acct_shell    |_rem_sys_acct_shell    |system accounts no valid shell"
    "5.4.2.8|_audit_unlocked_no_shell |_rem_unlocked_no_shell |no-shell accounts locked"
    "5.4.3.1|_audit_shells_nologin    |_rem_shells_nologin    |nologin not in /etc/shells"
    "5.4.3.2|_audit_shell_timeout     |_rem_shell_timeout     |shell timeout TMOUT configured"
    "5.4.3.3|_audit_default_umask     |_rem_default_umask     |default user umask 027"
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
# Summary table -- INFO/SKIP excluded from denominator
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

    local W_ID=8 W_DESC=44 W_ST=6
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

_audit_tree_row_manual() {
    local cis_id="$1" desc="$2" branch="$3"
    printf "  %s %-46s  " "$branch" "$desc"
    echo -e "${C_BLUE}[INFO]${C_RESET}"
    record_result "$cis_id" "$desc" "INFO"
}

# ---------------------------------------------------------------------------
# Generic helpers: shadow password parameters
# ---------------------------------------------------------------------------
_audit_shadow_param() {
    local param="$1" target="$2" chage_flag="$3" check_type="$4" source="$5"
    local fail=0
    local current_val=""

    if [[ "$source" == "logindefs" ]]; then
        current_val=$(grep -Pi "^\h*${param}\h+" /etc/login.defs 2>/dev/null \
            | awk '{print $2}' | head -1 || true)
    elif [[ "$source" == "useradd" ]]; then
        current_val=$(useradd -D 2>/dev/null | grep -Pi "^${param}=" \
            | cut -d= -f2 || true)
    fi

    if [[ -z "$current_val" ]]; then
        log_debug "${param}: not found in ${source}"
        fail=1
    elif [[ "$check_type" == "max" ]]; then
        if [[ "$current_val" -lt 0 || "$current_val" -gt "$target" ]]; then
            log_debug "${param}=${current_val} (expected 0-${target})"
            fail=1
        fi
    elif [[ "$check_type" == "min" ]]; then
        if [[ "$current_val" -lt "$target" ]]; then
            log_debug "${param}=${current_val} (expected >=${target})"
            fail=1
        fi
    fi

    local shadow_idx
    case "$param" in
        PASS_MAX_DAYS) shadow_idx=5 ;;
        PASS_MIN_DAYS) shadow_idx=4 ;;
        PASS_WARN_AGE) shadow_idx=6 ;;
        INACTIVE)      shadow_idx=7 ;;
        *) return "$fail" ;;
    esac

    local violating_users=""
    if [[ "$check_type" == "max" ]]; then
        violating_users=$(awk -F: -v idx="$shadow_idx" -v tgt="$target" \
            '($2~/^\$.+\$/) { if($idx > tgt || $idx < 0) print $1 }' \
            /etc/shadow 2>/dev/null || true)
    elif [[ "$check_type" == "min" ]]; then
        violating_users=$(awk -F: -v idx="$shadow_idx" -v tgt="$target" \
            '($2~/^\$.+\$/) { if($idx < tgt) print $1 }' \
            /etc/shadow 2>/dev/null || true)
    fi

    [[ -n "$violating_users" ]] && fail=1
    return "$fail"
}

_remediate_shadow_param() {
    local param="$1" target="$2" chage_flag="$3" check_type="$4" source="$5"

    if [[ "$source" == "logindefs" ]]; then
        if grep -Piq "^\h*#?\h*${param}\b" /etc/login.defs 2>/dev/null; then
            sed -i -E "s/^\s*#?\s*${param}\s+.*/${param} ${target}/I" /etc/login.defs
        else
            printf '%s\n' "${param} ${target}" >> /etc/login.defs
        fi
    elif [[ "$source" == "useradd" ]]; then
        log_info "Setting default ${param} to ${target} via useradd -D..."
        useradd -D -f "$target"
    fi

    local shadow_idx
    case "$param" in
        PASS_MAX_DAYS) shadow_idx=5 ;;
        PASS_MIN_DAYS) shadow_idx=4 ;;
        PASS_WARN_AGE) shadow_idx=6 ;;
        INACTIVE)      shadow_idx=7 ;;
        *) return 0 ;;
    esac

    local users_to_fix=""
    if [[ "$check_type" == "max" ]]; then
        users_to_fix=$(awk -F: -v idx="$shadow_idx" -v tgt="$target" \
            '($2~/^\$.+\$/) { if($idx > tgt || $idx < 0) print $1 }' \
            /etc/shadow 2>/dev/null || true)
    elif [[ "$check_type" == "min" ]]; then
        users_to_fix=$(awk -F: -v idx="$shadow_idx" -v tgt="$target" \
            '($2~/^\$.+\$/) { if($idx < tgt) print $1 }' \
            /etc/shadow 2>/dev/null || true)
    fi

    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        log_info "Applying chage ${chage_flag} ${target} to user '${user}'..."
        chage "$chage_flag" "$target" "$user"
    done <<< "$users_to_fix"
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.1 -- shadow parameter thin wrappers
# ---------------------------------------------------------------------------
_audit_shadow_pass_max()  { _audit_shadow_param "PASS_MAX_DAYS" "365"  "--maxdays"  "max" "logindefs"; }
_rem_shadow_pass_max()    { _remediate_shadow_param "PASS_MAX_DAYS" "365"  "--maxdays"  "max" "logindefs"; }

_audit_shadow_warn_age()  { _audit_shadow_param "PASS_WARN_AGE" "7"    "--warndays" "min" "logindefs"; }
_rem_shadow_warn_age()    { _remediate_shadow_param "PASS_WARN_AGE" "7"    "--warndays" "min" "logindefs"; }

_audit_shadow_inactive()  { _audit_shadow_param "INACTIVE"      "45"   "--inactive" "max" "useradd"; }
_rem_shadow_inactive()    { _remediate_shadow_param "INACTIVE"      "45"   "--inactive" "max" "useradd"; }

# ---------------------------------------------------------------------------
# CIS 5.4.1.4 -- encryption method
# ---------------------------------------------------------------------------
_audit_encrypt_method() {
    if grep -Piq "^\h*ENCRYPT_METHOD\h+(SHA512|YESCRYPT)\b" /etc/login.defs 2>/dev/null; then
        return 0
    fi
    log_debug "ENCRYPT_METHOD is not SHA512 or YESCRYPT in /etc/login.defs"
    return 1
}

_rem_encrypt_method() {
    log_info "Setting ENCRYPT_METHOD to ${LOGIN_DEFS_ENCRYPT_METHOD} in /etc/login.defs..."
    if grep -Piq "^\h*#?\h*ENCRYPT_METHOD\b" /etc/login.defs 2>/dev/null; then
        sed -i -E \
            "s/^\s*#?\s*ENCRYPT_METHOD\s+.*/ENCRYPT_METHOD ${LOGIN_DEFS_ENCRYPT_METHOD}/I" \
            /etc/login.defs
    else
        printf '%s\n' "ENCRYPT_METHOD ${LOGIN_DEFS_ENCRYPT_METHOD}" >> /etc/login.defs
    fi
}

# ---------------------------------------------------------------------------
# CIS 5.4.1.6 -- last password change date in the past
# ---------------------------------------------------------------------------
_get_users_with_future_pw() {
    local now; now=$(date +%s)
    local users_found=""
# shellcheck disable=SC2034 # Used but externally
    while IFS=: read -r l_user l_pass; do
        local l_change_date
        l_change_date=$(chage --list "$l_user" 2>/dev/null \
            | grep '^Last password change' | cut -d: -f2 \
            | grep -v 'never$' || true)
        if [[ -n "$l_change_date" ]]; then
            local l_change_epoch
            l_change_epoch=$(date -d "$l_change_date" +%s 2>/dev/null || echo 0)
            if [[ "$l_change_epoch" -gt "$now" ]]; then
                users_found+="$l_user "
            fi
        fi
    done < <(grep -E '^[^:]+:\$.+' /etc/shadow 2>/dev/null || true)
    echo "$users_found"
}

_audit_last_pw_past() {
    local violators; violators=$(_get_users_with_future_pw)
    if [[ -n "$violators" ]]; then
        log_debug "Users with future password change date: ${violators}"
        return 1
    fi
    return 0
}

_rem_last_pw_past() {
    local violators; violators=$(_get_users_with_future_pw)
    for l_user in $violators; do
        log_info "Resetting last password change date to today for: ${l_user}"
        if ! chage -d "$(date +%Y-%m-%d)" "$l_user"; then
            log_error "Failed to correct date for '${l_user}'."
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.2.1/2/3 -- root is only UID/GID 0 account/group
# ---------------------------------------------------------------------------
_manage_zero_id() {
    local mode="$1" type="$2"
    local violators="" root_ok=true

    case "$type" in
        uid)
            [[ "$(id -u root 2>/dev/null)" -eq 0 ]] || root_ok=false
            violators=$(awk -F: '($3==0 && $1!="root") {print $1}' /etc/passwd 2>/dev/null || true)
            ;;
        gid)
            [[ "$(id -g root 2>/dev/null)" -eq 0 ]] || root_ok=false
            violators=$(awk -F: \
                '($1!~/^(root|sync|shutdown|halt|operator)$/ && $4=="0") {print $1}' \
                /etc/passwd 2>/dev/null || true)
            ;;
        group)
            getent group root 2>/dev/null | grep -q ':0:' || root_ok=false
            violators=$(awk -F: '($3=="0" && $1!="root") {print $1}' \
                /etc/group 2>/dev/null || true)
            ;;
    esac

    if [[ "$mode" == "audit" ]]; then
        if [[ "$root_ok" == "false" || -n "$violators" ]]; then
            [[ -n "$violators" ]] && \
                log_debug "Violators for ${type} 0: $(tr '\n' ' ' <<< "$violators")"
            return 1
        fi
        return 0
    fi

    if [[ "$mode" == "remediate" ]]; then
        local fail=false
        if [[ "$root_ok" == "false" ]]; then
            log_info "Fixing root ${type} to 0..."
            case "$type" in
                uid)   usermod -u 0 root || fail=true ;;
                gid)   groupmod -g 0 root && usermod -g 0 root || fail=true ;;
                group) groupmod -g 0 root || fail=true ;;
            esac
        fi
        if [[ -n "$violators" ]]; then
            while IFS= read -r v; do
                [[ -z "$v" ]] && continue
                log_warn "Fixing violator '${v}' with ${type} 0..."
                case "$type" in
                    uid)
                        local n_uid
                        n_uid=$(awk -F: '{print $3}' /etc/passwd | sort -n | tail -1)
                        (( n_uid++ ))
                        usermod -u "$n_uid" "$v" || fail=true
                        ;;
                    gid)
                        getent group "$v" >/dev/null 2>&1 || groupadd "$v"
                        usermod -g "$v" "$v" || fail=true
                        ;;
                    group)
                        local n_gid
                        n_gid=$(awk -F: '{print $3}' /etc/group | sort -n | tail -1)
                        (( n_gid++ ))
                        groupmod -g "$n_gid" "$v" || fail=true
                        ;;
                esac
            done <<< "$violators"
        fi
        [[ "$fail" == "true" ]] && return 1
        return 0
    fi
}

_audit_root_uid_zero() { _manage_zero_id "audit"     "uid"; }
_rem_root_uid_zero()   { _manage_zero_id "remediate" "uid"; }
_audit_root_gid_zero() { _manage_zero_id "audit"     "gid"; }
_rem_root_gid_zero()   { _manage_zero_id "remediate" "gid"; }
_audit_root_grp_zero() { _manage_zero_id "audit"     "group"; }
_rem_root_grp_zero()   { _manage_zero_id "remediate" "group"; }

# ---------------------------------------------------------------------------
# CIS 5.4.2.4 -- root account access controlled (P or L)
# ---------------------------------------------------------------------------
_audit_root_pw_status() {
    local status
    status=$(passwd -S root 2>/dev/null | awk '{print $2}')
    if [[ "$status" =~ ^(P|L) ]]; then
        return 0
    fi
    log_debug "Root password status is '${status}' (expected P or L)"
    return 1
}

_rem_root_pw_status() {
    log_info "Locking the root account..."
    usermod -L root
}

# ---------------------------------------------------------------------------
# CIS 5.4.2.5 -- root PATH integrity
# ---------------------------------------------------------------------------
_audit_root_path() {
    local fail=0
    local root_path
    root_path=$(su - root -c "echo $PATH" 2>/dev/null || true)

    if grep -q "::" <<< "$root_path"; then
        log_debug "Root PATH contains an empty directory (::)"
        fail=1
    fi
    if grep -Pq ":\h*$" <<< "$root_path"; then
        log_debug "Root PATH contains a trailing colon"
        fail=1
    fi
    if grep -Pq '(^\h*|:)\.(:|\h*$)' <<< "$root_path"; then
        log_debug "Root PATH contains current working directory (.)"
        fail=1
    fi

    IFS=":" read -ra path_dirs <<< "$root_path"
    for p in "${path_dirs[@]}"; do
        [[ -z "$p" ]] && continue
        if [[ -d "$p" ]]; then
            local stat_out owner mode
            stat_out=$(stat -Lc '%U %a' "$p" 2>/dev/null || true)
            owner="${stat_out% *}"
            mode="${stat_out#* }"
            if [[ "$owner" != "root" ]]; then
                log_debug "Directory '${p}' in root PATH not owned by root (${owner})"
                fail=1
            fi
            if (( 8#${mode:-0} & 8#0022 )); then
                log_debug "Directory '${p}' in root PATH is group/world writable (${mode})"
                fail=1
            fi
        else
            log_debug "'${p}' in root PATH is not a valid directory"
            fail=1
        fi
    done
    return "$fail"
}

_rem_root_path() {
    local fail=0
    local root_path
    root_path=$(su - root -c "echo $PATH" 2>/dev/null || true)

    IFS=":" read -ra path_dirs <<< "$root_path"
    for p in "${path_dirs[@]}"; do
        [[ -z "$p" ]] && continue
        if [[ -d "$p" ]]; then
            local stat_out owner mode
            stat_out=$(stat -Lc '%U %a' "$p" 2>/dev/null || true)
            owner="${stat_out% *}"
            mode="${stat_out#* }"
            if [[ "$owner" != "root" ]]; then
                log_info "Changing ownership of '${p}' to root..."
                chown root "$p" || fail=1
            fi
            if (( 8#${mode:-0} & 8#0022 )); then
                log_info "Removing group/world write permissions from '${p}'..."
                chmod go-w "$p" || fail=1
            fi
        fi
    done

    if grep -q "::" <<< "$root_path" \
            || grep -Pq ":\h*$" <<< "$root_path" \
            || grep -Pq '(^\h*|:)\.(:|\h*$)' <<< "$root_path"; then
        log_warn "Root PATH contains '::' / trailing ':' / '.'"
        log_warn "MANUAL FIX REQUIRED: review root's init files (e.g. ~/.bashrc, ~/.profile)"
        fail=1
    fi
    return "$fail"
}

# ---------------------------------------------------------------------------
# CIS 5.4.2.6 -- root user umask
# ---------------------------------------------------------------------------
_audit_root_umask() {
    local fail=0
    for f in "${ROOT_UMASK_FILES[@]}"; do
        if [[ -f "$f" ]] && grep -Psiq -- "$ROOT_BAD_UMASK_REGEX" "$f" 2>/dev/null; then
            log_debug "Overly permissive umask found in ${f}"
            fail=1
        fi
    done
    return "$fail"
}

_rem_root_umask() {
    local any_fail=false
    for f in "${ROOT_UMASK_FILES[@]}"; do
        if [[ -f "$f" ]] && grep -Psiq -- "$ROOT_BAD_UMASK_REGEX" "$f" 2>/dev/null; then
            log_info "Updating permissive umask in ${f} to 027..."
            if ! sed -i -E 's/^\s*umask\s+.*/umask 027/I' "$f"; then
                log_error "Failed to update umask in ${f}"
                any_fail=true
            fi
        fi
    done
    [[ "$any_fail" == "true" ]] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.2.7 -- system accounts have no valid login shell
# ---------------------------------------------------------------------------
_get_system_users_with_valid_shell() {
    awk -F: -v umin="$UID_MIN" -v shell_rx="$VALID_SHELLS_REGEX" \
        -v exempt="$SYSTEM_ACCOUNTS_EXEMPT" '
        ($1 !~ exempt && ($3 < umin || $3 == 65534)) {
            if ($7 ~ shell_rx) print $1
        }' /etc/passwd 2>/dev/null || true
}

_audit_sys_acct_shell() {
    local violators
    violators=$(_get_system_users_with_valid_shell)
    if [[ -n "$violators" ]]; then
        log_debug "System accounts with valid shell: $(tr '\n' ' ' <<< "$violators")"
        return 1
    fi
    return 0
}

_rem_sys_acct_shell() {
    local any_fail=false
    local nologin_path
    nologin_path=$(command -v nologin 2>/dev/null || echo "/usr/sbin/nologin")
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        log_info "Setting shell to nologin for system account: ${user}"
        if ! usermod -s "$nologin_path" "$user"; then
            log_error "Failed to disable shell for ${user}"
            any_fail=true
        fi
    done < <(_get_system_users_with_valid_shell)
    [[ "$any_fail" == "true" ]] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.2.8 -- accounts without valid shell are locked
# ---------------------------------------------------------------------------
_get_unlocked_users_with_invalid_shell() {
    awk -F: -v shell_rx="$VALID_SHELLS_REGEX" -v exempt="$SYSTEM_ACCOUNTS_EXEMPT" '
        FNR==NR {
            if ($1 !~ exempt && $7 !~ shell_rx) invalid_shell_users[$1] = 1
            next
        }
        ($1 in invalid_shell_users) {
            if ($2 !~ /^(\!|\*)/) print $1
        }
    ' /etc/passwd /etc/shadow 2>/dev/null || true
}

_audit_unlocked_no_shell() {
    local violators
    violators=$(_get_unlocked_users_with_invalid_shell)
    if [[ -n "$violators" ]]; then
        log_debug "Unlocked accounts with invalid shell: $(tr '\n' ' ' <<< "$violators")"
        return 1
    fi
    return 0
}

_rem_unlocked_no_shell() {
    local any_fail=false
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        log_info "Locking account (invalid shell): ${user}"
        if ! usermod -L "$user"; then
            log_error "Failed to lock ${user}"
            any_fail=true
        fi
    done < <(_get_unlocked_users_with_invalid_shell)
    [[ "$any_fail" == "true" ]] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.3.1 -- nologin not in /etc/shells
# ---------------------------------------------------------------------------
_audit_shells_nologin() {
    if grep -Pq '^\h*([^#\n\r]+)?\/nologin\b' "$ETC_SHELLS" 2>/dev/null; then
        log_debug "nologin found in ${ETC_SHELLS}"
        return 1
    fi
    return 0
}

_rem_shells_nologin() {
    if grep -Pq '^\h*([^#\n\r]+)?\/nologin\b' "$ETC_SHELLS" 2>/dev/null; then
        log_info "Removing nologin entries from ${ETC_SHELLS}..."
        cp "$ETC_SHELLS" "${ETC_SHELLS}.bak"
        if sed -i -E '/\/nologin\b/d' "$ETC_SHELLS"; then
            rm -f "${ETC_SHELLS}.bak"
            return 0
        else
            log_error "Failed to modify ${ETC_SHELLS}; restoring backup"
            mv "${ETC_SHELLS}.bak" "$ETC_SHELLS"
            return 1
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CIS 5.4.3.2 -- shell timeout TMOUT
# ---------------------------------------------------------------------------
_audit_shell_timeout() {
    local fail=0
    if [[ -f "$TMOUT_FILE" ]]; then
        if ! grep -q "typeset -xr TMOUT=${TMOUT_VALUE}" "$TMOUT_FILE" 2>/dev/null; then
            log_debug "TMOUT file exists but content is incorrect"
            fail=1
        fi
    else
        log_debug "TMOUT configuration file ${TMOUT_FILE} missing"
        fail=1
    fi

    local conflict_files
    conflict_files=$(grep -lP "^\s*([^#\n\r]+)?\bTMOUT=" \
        "${SHELL_CONFIG_FILES[@]}" /etc/profile.d/*.sh 2>/dev/null \
        | grep -v "$TMOUT_FILE" || true)
    if [[ -n "$conflict_files" ]]; then
        log_debug "Conflicting TMOUT configurations: ${conflict_files}"
        fail=1
    fi
    return "$fail"
}

_rem_shell_timeout() {
    local files_to_clean=("${SHELL_CONFIG_FILES[@]}")
    while IFS= read -r file; do
        [[ "$file" != "$TMOUT_FILE" ]] && files_to_clean+=("$file")
    done < <(find /etc/profile.d -name "*.sh" 2>/dev/null)

    for f in "${files_to_clean[@]}"; do
        if [[ -f "$f" ]] && grep -Pq "^\s*([^#\n\r]+)?\bTMOUT=" "$f" 2>/dev/null; then
            log_info "Commenting out TMOUT in ${f} to avoid conflicts..."
            sed -i -E 's/^\s*(TMOUT|export TMOUT|readonly TMOUT)/# &/' "$f"
        fi
    done

    log_info "Creating ${TMOUT_FILE} with timeout ${TMOUT_VALUE}s..."
    {
        echo "# CIS Recommendation 5.4.3.2"
        echo "# Set TMOUT to ${TMOUT_VALUE} seconds, readonly and exported"
        echo "typeset -xr TMOUT=${TMOUT_VALUE}"
    } > "$TMOUT_FILE"
    chmod 644 "$TMOUT_FILE"
}

# ---------------------------------------------------------------------------
# CIS 5.4.3.3 -- default user umask 027
# ---------------------------------------------------------------------------
_audit_default_umask() {
    local fail=0

    if ! grep -Piq "^\h*UMASK\h+${SYS_UMASK}\b" /etc/login.defs 2>/dev/null; then
        log_debug "UMASK in /etc/login.defs is not ${SYS_UMASK}"
        fail=1
    fi

    if [[ ! -f "$UMASK_PROFILE_FILE" ]] || \
            ! grep -q "umask ${SYS_UMASK}" "$UMASK_PROFILE_FILE" 2>/dev/null; then
        log_debug "Profile file ${UMASK_PROFILE_FILE} missing or incorrect"
        fail=1
    fi

    if find /etc/profile.d/ -name '*.sh' \
            ! -name "$(basename "$UMASK_PROFILE_FILE")" \
            -exec grep -Pq "$PERMISSIVE_UMASK_REGEX" {} + 2>/dev/null; then
        log_debug "Permissive umask found in /etc/profile.d/ scripts"
        fail=1
    fi

    return "$fail"
}

_rem_default_umask() {
    log_info "Setting UMASK to ${SYS_UMASK} in /etc/login.defs..."
    if grep -Piq "^\h*UMASK\b" /etc/login.defs 2>/dev/null; then
        sed -i -E "s/^\s*UMASK\s+.*/UMASK ${SYS_UMASK}/" /etc/login.defs
    else
        printf '%s\n' "UMASK ${SYS_UMASK}" >> /etc/login.defs
    fi

    log_info "Sanitizing permissive umasks in /etc/profile.d/..."
    find /etc/profile.d/ -name '*.sh' \
            ! -name "$(basename "$UMASK_PROFILE_FILE")" -print0 \
        | while IFS= read -r -d '' f; do
            if grep -Pq "$PERMISSIVE_UMASK_REGEX" "$f" 2>/dev/null; then
                log_info "Commenting out permissive umask in ${f}..."
                sed -ri "s/$PERMISSIVE_UMASK_REGEX/# CIS-REMOVED: &/" "$f"
            fi
        done

    log_info "Creating ${UMASK_PROFILE_FILE}..."
    printf '%s\n' "umask ${SYS_UMASK}" > "$UMASK_PROFILE_FILE"
    chmod 644 "$UMASK_PROFILE_FILE"
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#ACCOUNTS_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${ACCOUNTS_CHECKS[@]}"; do
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
            _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" \
                || global_status=1
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

    _run_audit_checks "User Accounts & Environment  (CIS 5.4.1.1 - 5.4.3.3)" \
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

    for entry in "${ACCOUNTS_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 5.4.1.1 - 5.4.3.3)" \
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
    echo "CIS Benchmark Debian 13 - Section 5.4: User Accounts and Environment"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply user accounts and environment hardening."
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
    echo -e "\n${C_BOLD}--- CIS 5.4 User Accounts -- Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply user accounts and environment hardening)" > /dev/tty
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
    print_section_header "CIS 5.4" "User Accounts and Environment"
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