#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.2.3: Configure auditd Rules
#
# Sub-sections covered:
#   6.2.3.1  - Ensure /etc/sudoers modification is collected                    (Automated)
#   6.2.3.2  - Ensure actions as another user are always logged                 (Automated)
#   6.2.3.3  - Ensure events that modify the sudo log file are collected        (Automated)
#   6.2.3.4  - Ensure events that modify date/time information are collected    (Automated)
#   6.2.3.5  - Ensure events that modify hostname/domainname are collected      (Automated)
#   6.2.3.6  - Ensure events that modify /etc/issue are collected              (Automated)
#   6.2.3.7  - Ensure events that modify /etc/hosts are collected              (Automated)
#   6.2.3.8  - Ensure events that modify network environment are collected     (Automated)
#   6.2.3.9  - Ensure events that modify NetworkManager are collected          (Automated)
#   6.2.3.10 - Ensure use of privileged commands are collected                 (Automated)
#   6.2.3.11 - Ensure unsuccessful file access attempts are collected          (Automated)
#   6.2.3.12 - Ensure events that modify /etc/group are collected             (Automated)
#   6.2.3.13 - Ensure events that modify /etc/passwd are collected            (Automated)
#   6.2.3.14 - Ensure events that modify /etc/shadow,gshadow are collected    (Automated)
#   6.2.3.15 - Ensure events that modify /etc/security/opasswd are collected  (Automated)
#   6.2.3.16 - Ensure events that modify /etc/nsswitch.conf are collected     (Automated)
#   6.2.3.17 - Ensure events that modify /etc/pam.conf,pam.d are collected    (Automated)
#   6.2.3.18 - Ensure chmod,fchmod,fchmodat,fchmodat2 events are collected    (Automated)
#   6.2.3.19 - Ensure chown,fchown,lchown,fchownat events are collected       (Automated)
#   6.2.3.20 - Ensure xattr modification events are collected                  (Automated)
#   6.2.3.21 - Ensure successful file system mounts are collected             (Automated)
#   6.2.3.22 - Ensure session initiation information is collected             (Automated)
#   6.2.3.23 - Ensure login and logout events are collected                   (Automated)
#   6.2.3.24 - Ensure unlink file deletion events are collected               (Automated)
#   6.2.3.25 - Ensure rename file deletion events are collected               (Automated)
#   6.2.3.26 - Ensure MAC changes are collected                               (Automated)
#   6.2.3.27 - Ensure chcon use is collected                                  (Automated)
#   6.2.3.28 - Ensure setfacl use is collected                                (Automated)
#   6.2.3.29 - Ensure chacl use is collected                                  (Automated)
#   6.2.3.30 - Ensure usermod use is collected                                (Automated)
#   6.2.3.31 - Ensure kernel module loading via kmod is collected             (Automated)
#   6.2.3.32 - Ensure init_module,finit_module are collected                  (Automated)
#   6.2.3.33 - Ensure delete_module is collected                              (Automated)
#   6.2.3.34 - Ensure query_module is collected                               (Automated)
#   6.2.3.35 - Ensure audit configuration is loaded regardless of errors      (Automated)
#   6.2.3.36 - Ensure the audit configuration is immutable                    (Automated)
#   6.2.3.37 - Ensure running and on-disk configuration is the same           (Manual)

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
SYS_ARCH=$(uname -m)
readonly SYS_ARCH
if [[ "$SYS_ARCH" == "x86_64" || "$SYS_ARCH" == "aarch64" ]]; then
    readonly AUDIT_ARCH="b64"
else
    readonly AUDIT_ARCH="b32"
fi

readonly AUDIT_RULES_DIR="/etc/audit/rules.d"
readonly CIS_RULES_FILE="${AUDIT_RULES_DIR}/50-cis-hardening.rules"
readonly CIS_PRIV_FILE="${AUDIT_RULES_DIR}/50-cis-privileged.rules"
readonly AUDIT_INIT_FILE="${AUDIT_RULES_DIR}/01-cis-initialize.rules"
readonly AUDIT_FINALIZE_FILE="${AUDIT_RULES_DIR}/99-cis-finalize.rules"

SYS_UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs 2>/dev/null || echo 1000)
readonly SYS_UID_MIN

_RULES_CHANGED=false

# ---------------------------------------------------------------------------
# Rule data arrays — each entry tagged with its CIS ID in the description
# ---------------------------------------------------------------------------
readonly -a AUDIT_FILE_RULES=(
    "/etc/sudoers|path|wa|scope|6.2.3.1 /etc/sudoers modification"
    "/etc/sudoers.d|dir|wa|scope|6.2.3.1 /etc/sudoers.d modification"
    "/var/log/sudo.log|path|wa|sudo_log_file|6.2.3.3 sudo log file modification"
    "/etc/localtime|path|wa|localtime-change|6.2.3.4 localtime modification"
    "/etc/issue|path|wa|system-locale|6.2.3.6 /etc/issue modification"
    "/etc/issue.net|path|wa|system-locale|6.2.3.6 /etc/issue.net modification"
    "/etc/hosts|path|wa|system-locale|6.2.3.7 /etc/hosts modification"
    "/etc/hostname|path|wa|system-locale|6.2.3.7 /etc/hostname modification"
    "/etc/network/interfaces|path|wa|system-locale|6.2.3.8 network interfaces modification"
    "/etc/network/interfaces.d|dir|wa|system-locale|6.2.3.8 interfaces.d modification"
    "/etc/netplan|dir|wa|system-locale|6.2.3.8 netplan modification"
    "/etc/NetworkManager|dir|wa|system-locale|6.2.3.9 NetworkManager modification"
    "/etc/group|path|wa|identity|6.2.3.12 /etc/group modification"
    "/etc/passwd|path|wa|identity|6.2.3.13 /etc/passwd modification"
    "/etc/shadow|path|wa|identity|6.2.3.14 /etc/shadow modification"
    "/etc/gshadow|path|wa|identity|6.2.3.14 /etc/gshadow modification"
    "/etc/security/opasswd|path|wa|identity|6.2.3.15 /etc/security/opasswd modification"
    "/etc/nsswitch.conf|path|wa|identity|6.2.3.16 /etc/nsswitch.conf modification"
    "/etc/pam.conf|path|wa|identity|6.2.3.17 /etc/pam.conf modification"
    "/etc/pam.d|dir|wa|identity|6.2.3.17 /etc/pam.d modification"
    "/var/run/utmp|path|wa|session|6.2.3.22 utmp session info"
    "/var/log/wtmp|path|wa|session|6.2.3.22 wtmp session info"
    "/var/log/btmp|path|wa|session|6.2.3.22 btmp session info"
    "/var/log/lastlog|path|wa|logins|6.2.3.23 lastlog login events"
    "/var/run/faillock|path|wa|logins|6.2.3.23 faillock login events"
    "/etc/apparmor|path|wa|MAC-policy|6.2.3.26 AppArmor modification"
    "/etc/apparmor.d|dir|wa|MAC-policy|6.2.3.26 AppArmor.d modification"
    "/usr/bin/chcon|path|x -F auid>=${SYS_UID_MIN} -F auid!=unset|perm_chng|6.2.3.27 chcon use"
    "/usr/bin/setfacl|path|x -F auid>=${SYS_UID_MIN} -F auid!=unset|perm_chng|6.2.3.28 setfacl use"
    "/usr/bin/chacl|path|x -F auid>=${SYS_UID_MIN} -F auid!=unset|perm_chng|6.2.3.29 chacl use"
    "/usr/sbin/usermod|path|x -F auid>=${SYS_UID_MIN} -F auid!=unset|usermod|6.2.3.30 usermod use"
    "/usr/bin/kmod|path|x -F auid>=${SYS_UID_MIN} -F auid!=unset|kernel_modules|6.2.3.31 kmod use"
)

readonly -a AUDIT_SYSCALL_RULES=(
    "execve|-C euid!=uid -F auid!=unset|user_emulation|6.2.3.2 actions as another user"
    "adjtimex,settimeofday||time-change|6.2.3.4 date/time (adjtimex/settimeofday)"
    "clock_settime|-F a0=0x0|time-change|6.2.3.4 date/time (clock_settime)"
    "sethostname,setdomainname||system-locale|6.2.3.5 hostname/domainname change"
    "creat,open,openat,truncate,ftruncate|-F exit=-EACCES -F auid>=${SYS_UID_MIN} -F auid!=unset|access|6.2.3.11 unsuccessful access (EACCES)"
    "creat,open,openat,truncate,ftruncate|-F exit=-EPERM -F auid>=${SYS_UID_MIN} -F auid!=unset|access|6.2.3.11 unsuccessful access (EPERM)"
    "chmod,fchmod,fchmodat,fchmodat2|-F auid>=${SYS_UID_MIN} -F auid!=unset|perm_mod|6.2.3.18 chmod events"
    "chown,fchown,lchown,fchownat|-F auid>=${SYS_UID_MIN} -F auid!=unset|perm_mod|6.2.3.19 chown events"
    "setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr|-F auid>=${SYS_UID_MIN} -F auid!=unset|perm_mod|6.2.3.20 xattr events"
    "mount|-F auid>=${SYS_UID_MIN} -F auid!=unset|mounts|6.2.3.21 file system mounts"
    "unlink,unlinkat|-F auid>=${SYS_UID_MIN} -F auid!=unset|delete|6.2.3.24 unlink deletion events"
    "rename,renameat,renameat2|-F auid>=${SYS_UID_MIN} -F auid!=unset|delete|6.2.3.25 rename deletion events"
    "init_module,finit_module|-F auid>=${SYS_UID_MIN} -F auid!=unset|kernel_modules|6.2.3.32 init_module/finit_module"
    "delete_module|-F auid>=${SYS_UID_MIN} -F auid!=unset|kernel_modules|6.2.3.33 delete_module"
    "query_module|-F auid>=${SYS_UID_MIN} -F auid!=unset|kernel_modules|6.2.3.34 query_module"
)

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 6.2.3.1 – 6.2.3.37 (37 checks)
# ---------------------------------------------------------------------------
readonly -a AUDITD_RULE_CHECKS=(
    "6.2.3.1 |_audit_rules_for 6.2.3.1 |_rem_rules_for 6.2.3.1 |/etc/sudoers modification collected"
    "6.2.3.2 |_audit_rules_for 6.2.3.2 |_rem_rules_for 6.2.3.2 |actions as another user logged"
    "6.2.3.3 |_audit_rules_for 6.2.3.3 |_rem_rules_for 6.2.3.3 |sudo log file events collected"
    "6.2.3.4 |_audit_rules_for 6.2.3.4 |_rem_rules_for 6.2.3.4 |date/time modification collected"
    "6.2.3.5 |_audit_rules_for 6.2.3.5 |_rem_rules_for 6.2.3.5 |hostname/domainname changes collected"
    "6.2.3.6 |_audit_rules_for 6.2.3.6 |_rem_rules_for 6.2.3.6 |/etc/issue modifications collected"
    "6.2.3.7 |_audit_rules_for 6.2.3.7 |_rem_rules_for 6.2.3.7 |/etc/hosts modifications collected"
    "6.2.3.8 |_audit_rules_for 6.2.3.8 |_rem_rules_for 6.2.3.8 |network environment changes collected"
    "6.2.3.9 |_audit_rules_for 6.2.3.9 |_rem_rules_for 6.2.3.9 |NetworkManager changes collected"
    "6.2.3.10|_audit_privileged_cmds     |_rem_privileged_cmds     |privileged commands collected"
    "6.2.3.11|_audit_rules_for 6.2.3.11|_rem_rules_for 6.2.3.11|unsuccessful file access collected"
    "6.2.3.12|_audit_rules_for 6.2.3.12|_rem_rules_for 6.2.3.12|/etc/group modification collected"
    "6.2.3.13|_audit_rules_for 6.2.3.13|_rem_rules_for 6.2.3.13|/etc/passwd modification collected"
    "6.2.3.14|_audit_rules_for 6.2.3.14|_rem_rules_for 6.2.3.14|/etc/shadow,gshadow collected"
    "6.2.3.15|_audit_rules_for 6.2.3.15|_rem_rules_for 6.2.3.15|/etc/security/opasswd collected"
    "6.2.3.16|_audit_rules_for 6.2.3.16|_rem_rules_for 6.2.3.16|/etc/nsswitch.conf collected"
    "6.2.3.17|_audit_rules_for 6.2.3.17|_rem_rules_for 6.2.3.17|/etc/pam.conf,pam.d collected"
    "6.2.3.18|_audit_rules_for 6.2.3.18|_rem_rules_for 6.2.3.18|chmod events collected"
    "6.2.3.19|_audit_rules_for 6.2.3.19|_rem_rules_for 6.2.3.19|chown events collected"
    "6.2.3.20|_audit_rules_for 6.2.3.20|_rem_rules_for 6.2.3.20|xattr events collected"
    "6.2.3.21|_audit_rules_for 6.2.3.21|_rem_rules_for 6.2.3.21|file system mounts collected"
    "6.2.3.22|_audit_rules_for 6.2.3.22|_rem_rules_for 6.2.3.22|session initiation collected"
    "6.2.3.23|_audit_rules_for 6.2.3.23|_rem_rules_for 6.2.3.23|login/logout events collected"
    "6.2.3.24|_audit_rules_for 6.2.3.24|_rem_rules_for 6.2.3.24|unlink deletion events collected"
    "6.2.3.25|_audit_rules_for 6.2.3.25|_rem_rules_for 6.2.3.25|rename deletion events collected"
    "6.2.3.26|_audit_rules_for 6.2.3.26|_rem_rules_for 6.2.3.26|MAC changes collected"
    "6.2.3.27|_audit_rules_for 6.2.3.27|_rem_rules_for 6.2.3.27|chcon use collected"
    "6.2.3.28|_audit_rules_for 6.2.3.28|_rem_rules_for 6.2.3.28|setfacl use collected"
    "6.2.3.29|_audit_rules_for 6.2.3.29|_rem_rules_for 6.2.3.29|chacl use collected"
    "6.2.3.30|_audit_rules_for 6.2.3.30|_rem_rules_for 6.2.3.30|usermod use collected"
    "6.2.3.31|_audit_rules_for 6.2.3.31|_rem_rules_for 6.2.3.31|kmod use collected"
    "6.2.3.32|_audit_rules_for 6.2.3.32|_rem_rules_for 6.2.3.32|init_module/finit_module collected"
    "6.2.3.33|_audit_rules_for 6.2.3.33|_rem_rules_for 6.2.3.33|delete_module collected"
    "6.2.3.34|_audit_rules_for 6.2.3.34|_rem_rules_for 6.2.3.34|query_module collected"
    "6.2.3.35|_audit_continue_on_error  |_rem_continue_on_error  |audit configured to continue on error"
    "6.2.3.36|_audit_immutable          |_rem_immutable          |audit configuration immutable"
    "6.2.3.37|_audit_augenrules_check   |_rem_augenrules_reload  |running config matches on-disk"
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
_trim()       { local v="$*"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

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
_is_auditd_installed() {
    command -v auditctl >/dev/null 2>&1
}

_ensure_rules_dir() {
    [[ -d "$AUDIT_RULES_DIR" ]] || mkdir -p "$AUDIT_RULES_DIR"
}

_ensure_cis_rules_file() {
    _ensure_rules_dir
    [[ -f "$CIS_RULES_FILE" ]] || { touch "$CIS_RULES_FILE"; chmod 640 "$CIS_RULES_FILE"; }
}

_cleanup_stale_file_rules() {
    [[ -f "$CIS_RULES_FILE" ]] || return 0
    local tmp
    tmp=$(mktemp)
    while IFS= read -r line; do
        local fpath ftype
        fpath=$(echo "$line" | grep -oP '(?<=-F\s)(path|dir)=\K\S+' || true)
        ftype=$(echo "$line" | grep -oP '-F\s\K(path|dir)(?==)' || true)
        if [[ -n "$fpath" ]]; then
            if [[ "$ftype" == "path" && ! -e "$fpath" ]]; then
                log_warn "Removing stale rule (path gone): ${fpath}"
                continue
            fi
            if [[ "$ftype" == "dir" && ! -d "$fpath" ]]; then
                log_warn "Removing stale rule (dir gone): ${fpath}"
                continue
            fi
        fi
        printf '%s\n' "$line"
    done < "$CIS_RULES_FILE" > "$tmp"
    mv "$tmp" "$CIS_RULES_FILE"
}

# ---------------------------------------------------------------------------
# Generic file rule audit/remediation
# ---------------------------------------------------------------------------
_audit_file_rule() {
    local entry="$1"
    local f_path="${entry%%|*}"
    local tmp="${entry#*|}"
    local f_type="${tmp%%|*}"

    if [[ "$f_type" == "path" && ! -e "$f_path" ]]; then
        if [[ "$f_path" == "/var/log/sudo.log" ]]; then
            log_debug "Skipping runtime check for ${f_path}: file not yet created by sudo"
            return 0
        fi
        log_debug "Skipping audit check for ${f_path}: path does not exist"
        return 0
    fi
    if [[ "$f_type" == "dir" && ! -d "$f_path" ]]; then
        log_debug "Skipping audit check for ${f_path}: directory does not exist"
        return 0
    fi
    if ! grep -Psiq "^\h*-a\h+(always,exit|exit,always)\h+.*-F\h+${f_type}=${f_path}\b" \
            "$AUDIT_RULES_DIR"/*.rules 2>/dev/null; then
        log_debug "File rule for ${f_path} (${f_type}) missing from rules.d"
        return 1
    fi
    if ! auditctl -l 2>/dev/null | grep -Pq "\b${f_type}=${f_path}\b"; then
        log_debug "File rule for ${f_path} not loaded in running config"
        return 1
    fi
    return 0
}

_remediate_file_rule() {
    local entry="$1"
    local f_path="${entry%%|*}"
    local tmp="${entry#*|}"
    local f_type="${tmp%%|*}"
    tmp="${tmp#*|}"
    local f_perm="${tmp%%|*}"
    tmp="${tmp#*|}"
    local f_key="${tmp%%|*}"

    if [[ "$f_path" == "/var/run/faillock" && ! -d "$f_path" ]]; then
        mkdir -p "$f_path"
        chmod 755 "$f_path"
        log_info "Created ${f_path} (tmpfs runtime dir)"
    fi

    if [[ "$f_path" == "/var/log/sudo.log" && ! -e "$f_path" ]]; then
        log_info "Creating ${f_path} (sudo will populate it on first use)"
        touch "$f_path"
        chmod 640 "$f_path"
    fi

    if [[ "$f_type" == "path" && ! -e "$f_path" ]]; then
        log_warn "Skipping rule for ${f_path}: path does not exist on this system"
        return 0
    fi
    if [[ "$f_type" == "dir" && ! -d "$f_path" ]]; then
        log_warn "Skipping rule for ${f_path}: directory does not exist on this system"
        return 0
    fi
    local rule_string="-a always,exit -F arch=${AUDIT_ARCH} -S all -F ${f_type}=${f_path} -F perm=${f_perm} -k ${f_key}"

    _ensure_cis_rules_file
    if ! grep -Fxq -- "$rule_string" "$CIS_RULES_FILE"; then
        log_info "Adding file rule: ${f_path}"
        printf '%s\n' "$rule_string" >> "$CIS_RULES_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Generic syscall rule audit/remediation
# ---------------------------------------------------------------------------
_audit_syscall_rule() {
    local entry="$1"
    local s_calls="${entry%%|*}"

    local first_syscall
    first_syscall=$(echo "$s_calls" | cut -d, -f1)

    if ! grep -Psiq "^\h*-a\h+(always,exit|exit,always).*(-S\h+${first_syscall}\b|\b${first_syscall}\b)" \
            "$AUDIT_RULES_DIR"/*.rules 2>/dev/null; then
        log_debug "Syscall rule for '${s_calls}' missing from rules.d"
        return 1
    fi
    if ! auditctl -l 2>/dev/null | grep -Pq "\b${first_syscall}\b"; then
        log_debug "Syscall rule for '${s_calls}' not loaded in running config"
        return 1
    fi
    return 0
}

_remediate_syscall_rule() {
    local entry="$1"
    local s_calls="${entry%%|*}"
    local tmp="${entry#*|}"
    local s_filters="${tmp%%|*}"
    tmp="${tmp#*|}"
    local s_key="${tmp%%|*}"

    local rule_string="-a always,exit -F arch=${AUDIT_ARCH} ${s_filters} -S ${s_calls} -k ${s_key}"

    _ensure_cis_rules_file
    if ! grep -Fxq -- "$rule_string" "$CIS_RULES_FILE"; then
        log_info "Adding syscall rule: ${s_calls}"
        printf '%s\n' "$rule_string" >> "$CIS_RULES_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Generic CIS-ID-based rule dispatcher (DRY)
# ---------------------------------------------------------------------------
_audit_rules_for() {
    local cis_id="$1"
    _is_auditd_installed || { log_debug "auditd not installed"; return 1; }

    local fail=0 entry desc entry_cis

    for entry in "${AUDIT_FILE_RULES[@]}"; do
        desc="${entry##*|}"
        entry_cis="${desc%% *}"
        [[ "$entry_cis" == "$cis_id" ]] || continue
        _audit_file_rule "$entry" || fail=1
    done

    for entry in "${AUDIT_SYSCALL_RULES[@]}"; do
        desc="${entry##*|}"
        entry_cis="${desc%% *}"
        [[ "$entry_cis" == "$cis_id" ]] || continue
        _audit_syscall_rule "$entry" || fail=1
    done

    return "$fail"
}

_rem_rules_for() {
    local cis_id="$1"
    _is_auditd_installed || { log_error "auditd not installed — cannot remediate rules"; return 1; }

    local entry desc entry_cis

    for entry in "${AUDIT_FILE_RULES[@]}"; do
        desc="${entry##*|}"
        entry_cis="${desc%% *}"
        [[ "$entry_cis" == "$cis_id" ]] || continue
        _remediate_file_rule "$entry"
    done

    for entry in "${AUDIT_SYSCALL_RULES[@]}"; do
        desc="${entry##*|}"
        entry_cis="${desc%% *}"
        [[ "$entry_cis" == "$cis_id" ]] || continue
        _remediate_syscall_rule "$entry"
    done

    _RULES_CHANGED=true
}

# ---------------------------------------------------------------------------
# CIS 6.2.3.10 — privileged commands (SUID/SGID)
# ---------------------------------------------------------------------------
_generate_privileged_rules() {
    local partitions
    partitions=$(findmnt -n -l -k -it "$(awk '/nodev/ { print $2 }' /proc/filesystems 2>/dev/null \
        | paste -sd,)" | grep -Pv "noexec|nosuid" | awk '{print $1}')

    local part f
    for part in $partitions; do
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            printf -- '-a always,exit -F arch=%s -S all -F path=%s -F perm=x -F auid>=%s -F auid!=unset -k privileged\n' \
                "$AUDIT_ARCH" "$f" "$SYS_UID_MIN"
        done < <(find "$part" -xdev -type f -perm /6000 2>/dev/null)
    done
}

_audit_privileged_cmds() {
    _is_auditd_installed || { log_debug "auditd not installed"; return 1; }
    [[ -f "$CIS_PRIV_FILE" && -s "$CIS_PRIV_FILE" ]] && return 0
    log_debug "Privileged commands rules file missing or empty (${CIS_PRIV_FILE})"
    return 1
}

_rem_privileged_cmds() {
    _is_auditd_installed || { log_error "auditd not installed — cannot remediate rules"; return 1; }

    log_info "Scanning filesystems for SUID/SGID binaries (may take a moment)..."
    local new_rules
    new_rules=$(_generate_privileged_rules)

    _ensure_rules_dir
    if [[ -n "$new_rules" ]]; then
        printf '%s\n' "$new_rules" | sort -u > "$CIS_PRIV_FILE"
        chmod 640 "$CIS_PRIV_FILE"
        log_ok "Privileged commands audit rules generated at ${CIS_PRIV_FILE}."
    else
        log_warn "No SUID/SGID files found. Creating empty rule file."
        touch "$CIS_PRIV_FILE"
    fi
    _RULES_CHANGED=true
}

# ---------------------------------------------------------------------------
# CIS 6.2.3.35 — audit configuration loaded regardless of errors (-c)
# ---------------------------------------------------------------------------
_audit_continue_on_error() {
    _is_auditd_installed || { log_debug "auditd not installed"; return 1; }
    grep -Phq '^\h*-c\b' "$AUDIT_RULES_DIR"/*.rules 2>/dev/null && return 0
    log_debug "Audit rule '-c' (continue on error) is missing"
    return 1
}

_rem_continue_on_error() {
    _is_auditd_installed || { log_error "auditd not installed — cannot remediate rules"; return 1; }
    log_info "Writing '-c' to ${AUDIT_INIT_FILE}..."
    _ensure_rules_dir
    printf '%s\n' "-c" > "$AUDIT_INIT_FILE"
    chmod 640 "$AUDIT_INIT_FILE"
    _RULES_CHANGED=true
}

# ---------------------------------------------------------------------------
# CIS 6.2.3.36 — audit configuration immutable (-e 2)
# ---------------------------------------------------------------------------
_audit_immutable() {
    _is_auditd_installed || { log_debug "auditd not installed"; return 1; }
    grep -Phq '^\h*-e\h+2\b' "$AUDIT_RULES_DIR"/*.rules 2>/dev/null && return 0
    log_debug "Audit rule '-e 2' (immutable) is missing"
    return 1
}

_rem_immutable() {
    _is_auditd_installed || { log_error "auditd not installed — cannot remediate rules"; return 1; }
    log_info "Writing '-e 2' to ${AUDIT_FINALIZE_FILE}..."
    _ensure_rules_dir
    printf '%s\n' "-e 2" > "$AUDIT_FINALIZE_FILE"
    chmod 640 "$AUDIT_FINALIZE_FILE"
    _RULES_CHANGED=true
}

# ---------------------------------------------------------------------------
# CIS 6.2.3.37 — running and on-disk configuration is the same
# ---------------------------------------------------------------------------
_audit_augenrules_check() {
    _is_auditd_installed || { log_debug "auditd not installed"; return 1; }
    local check_out
    check_out=$(augenrules --check 2>&1 || true)
    if echo "$check_out" | grep -q "No change"; then
        return 0
    fi
    log_debug "augenrules drift: ${check_out}"
    return 1
}

_rem_augenrules_reload() {
    _is_auditd_installed || { log_error "auditd not installed — cannot reload rules"; return 1; }
    _RULES_CHANGED=true
}

# ---------------------------------------------------------------------------
# Reload audit rules (deferred — called once after remediation)
# ---------------------------------------------------------------------------
_reload_auditd_rules() {
    _is_auditd_installed || return 0
    log_info "Merging and loading audit rules (augenrules --load)..."

    if augenrules --load >/dev/null 2>&1; then
        log_ok "Audit rules loaded successfully."
    else
        log_error "Failed to load audit rules. Syntax error in .rules files?"
        return 1
    fi

    if auditctl -s 2>/dev/null | grep -q "enabled=2"; then
        log_warn "Audit system is IMMUTABLE (locked). A SYSTEM REBOOT IS REQUIRED."
    fi
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#AUDITD_RULE_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${AUDITD_RULE_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func=$(_trim "$audit_func")
        (( ++current_row ))
        if [[ $current_row -eq $total_rows ]]; then branch="└─"; else branch="├─"; fi
        # shellcheck disable=SC2086  # Intentional word splitting: "func arg" → func arg
        _audit_tree_row "$cis_id" "$desc" "$branch" $audit_func || global_status=1
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

    _run_audit_checks "auditd Rules  (CIS 6.2.3.1 – 6.2.3.37)" || global_status=1

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
    _RULES_CHANGED=false

    log_info "Cleaning stale rules from ${CIS_RULES_FILE}..."
    _cleanup_stale_file_rules

    for entry in "${AUDITD_RULE_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func=$(_trim "$audit_func")
        rem_func=$(_trim "$rem_func")
        if ! $audit_func; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            $rem_func || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} — already compliant."
        fi
    done

    if [[ "$_RULES_CHANGED" == "true" ]]; then
        _reload_auditd_rules || any_failure=true
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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.2.3.1 – 6.2.3.37)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.2.3: Configure auditd Rules"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply auditd rule configurations."
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
    echo -e "\n${C_BOLD}--- CIS 6.2.3 auditd Rules — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply audit rules)" > /dev/tty
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
    print_section_header "CIS 6.2.3" "Configure auditd Rules"
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