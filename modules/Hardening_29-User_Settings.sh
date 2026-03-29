#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 7.2: Local User and Group Settings
#
# Sub-sections covered:
#   7.2.1  - Ensure accounts in /etc/passwd use shadowed passwords             (Automated)
#   7.2.2  - Ensure /etc/shadow password fields are not empty                  (Automated)
#   7.2.3  - Ensure all groups in /etc/passwd exist in /etc/group              (Automated)
#   7.2.4  - Ensure shadow group is empty                                      (Automated)
#   7.2.5  - Ensure no duplicate UIDs exist                                    (Automated)
#   7.2.6  - Ensure no duplicate GIDs exist                                    (Automated)
#   7.2.7  - Ensure no duplicate user names exist                              (Automated)
#   7.2.8  - Ensure no duplicate group names exist                             (Automated)
#   7.2.9  - Ensure local interactive user home directories are configured     (Automated)
#   7.2.10 - Ensure local interactive user dot files access is configured      (Automated)

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
readonly HOME_DIR_PERM_MASK="0027"
readonly MASK_DOT_644="0133"
readonly MASK_DOT_600="0177"
readonly -a DOT_FILES_STRICT=(".netrc" ".bash_history")
readonly -a DOT_FILES_DANGEROUS=(".forward" ".rhost")

# ---------------------------------------------------------------------------
# DATA-DRIVEN array — CIS 7.2.1 – 7.2.10 (10 checks)
# ---------------------------------------------------------------------------
readonly -a USER_CHECKS=(
    "7.2.1 |_audit_shadowed_passwords  |_rem_shadowed_passwords  |accounts use shadowed passwords"
    "7.2.2 |_audit_empty_shadow_fields |_rem_empty_shadow_fields |shadow password fields not empty"
    "7.2.3 |_audit_missing_groups      |_rem_manual              |all passwd groups exist in /etc/group"
    "7.2.4 |_audit_shadow_group        |_rem_shadow_group        |shadow group is empty"
    "7.2.5 |_audit_dup_uids            |_rem_manual              |no duplicate UIDs"
    "7.2.6 |_audit_dup_gids            |_rem_manual              |no duplicate GIDs"
    "7.2.7 |_audit_dup_usernames       |_rem_manual              |no duplicate user names"
    "7.2.8 |_audit_dup_groupnames      |_rem_manual              |no duplicate group names"
    "7.2.9 |_audit_home_dirs           |_rem_home_dirs           |home directories configured"
    "7.2.10|_audit_user_dot_files      |_rem_user_dot_files      |dot files access configured"
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

    local W_ID=9 W_DESC=42 W_ST=6
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
        printf "  %s %-44s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-44s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Generic utility helpers
# ---------------------------------------------------------------------------

_get_interactive_users() {
    local valid_shells
    valid_shells=$(grep -vE '(nologin|false)$' /etc/shells 2>/dev/null | paste -s -d '|' -)
    [[ -z "$valid_shells" ]] && return 0
    awk -F: -v shells="$valid_shells" '$NF ~ shells { print $1 ":" $(NF-1) }' /etc/passwd
}

_check_duplicates() {
    local file="$1" col="$2"
    [[ -f "$file" ]] || return 0

    local duplicates
    duplicates=$(cut -d: -f"$col" "$file" | sort | uniq -d)
    if [[ -n "$duplicates" ]]; then
        local dup
        for dup in $duplicates; do
            local entities
            entities=$(awk -F: -v val="$dup" -v c="$col" "\$c == val {print \$1}" "$file" \
                | tr '\n' ',' | sed 's/,$//')
            log_debug "Duplicate value '${dup}' in ${file} col ${col}: ${entities}"
        done
        return 1
    fi
    return 0
}

_rem_manual() {
    log_warn "This check requires manual remediation. Review and correct manually."
    return 1
}

# ---------------------------------------------------------------------------
# CIS 7.2.1 — accounts use shadowed passwords
# ---------------------------------------------------------------------------
_audit_shadowed_passwords() {
    local violators
    violators=$(awk -F: '$2 != "x" {print $1}' /etc/passwd 2>/dev/null || true)
    if [[ -n "$violators" ]]; then
        log_debug "Accounts without shadowed passwords: ${violators//$'\n'/, }"
        return 1
    fi
    return 0
}

_rem_shadowed_passwords() {
    log_info "Running pwconv to enable shadow passwords..."
    pwconv
}

# ---------------------------------------------------------------------------
# CIS 7.2.2 — shadow password fields not empty
# ---------------------------------------------------------------------------
_audit_empty_shadow_fields() {
    local violators
    violators=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null || true)
    if [[ -n "$violators" ]]; then
        log_debug "Accounts with empty shadow password: ${violators//$'\n'/, }"
        return 1
    fi
    return 0
}

_rem_empty_shadow_fields() {
    local user
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        log_info "Locking account with empty password: ${user}"
        passwd -l "$user" 2>/dev/null || log_error "Failed to lock ${user}"
    done < <(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null)
}

# ---------------------------------------------------------------------------
# CIS 7.2.3 — all groups in /etc/passwd exist in /etc/group
# ---------------------------------------------------------------------------
_audit_missing_groups() {
    local fail=0
    local gid
    while IFS= read -r gid; do
        if ! grep -q -E "^[^:]*:[^:]*:${gid}:" /etc/group; then
            local users
            users=$(awk -F: -v g="$gid" '$4 == g {print $1}' /etc/passwd | tr '\n' ',' | sed 's/,$//')
            log_debug "GID ${gid} missing from /etc/group (used by: ${users})"
            fail=1
        fi
    done < <(awk -F: '{print $4}' /etc/passwd | sort -u)
    return "$fail"
}

# ---------------------------------------------------------------------------
# CIS 7.2.4 — shadow group is empty
# ---------------------------------------------------------------------------
_audit_shadow_group() {
    local fail=0

    local shadow_members
    shadow_members=$(awk -F: '$1=="shadow" {print $4}' /etc/group)
    if [[ -n "$shadow_members" ]]; then
        log_debug "Shadow group has secondary members: ${shadow_members}"
        fail=1
    fi

    local shadow_gid
    shadow_gid=$(getent group shadow 2>/dev/null | awk -F: '{print $3}')
    if [[ -n "$shadow_gid" ]]; then
        local primary_members
        primary_members=$(awk -F: -v sg="$shadow_gid" '$4 == sg {print $1}' /etc/passwd)
        if [[ -n "$primary_members" ]]; then
            log_debug "Users with shadow as primary group: ${primary_members}"
            fail=1
        fi
    fi
    return "$fail"
}

_rem_shadow_group() {
    log_info "Removing secondary members from 'shadow' group..."
    sed -ri 's/(^shadow:[^:]*:[^:]*:)([^:]+$)/\1/' /etc/group

    local shadow_gid
    shadow_gid=$(getent group shadow 2>/dev/null | awk -F: '{print $3}')
    if [[ -n "$shadow_gid" ]]; then
        local primary_members
        primary_members=$(awk -F: -v sg="$shadow_gid" '$4 == sg {print $1}' /etc/passwd)
        if [[ -n "$primary_members" ]]; then
            log_warn "Manual action required: change primary group for users: ${primary_members}"
            return 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# CIS 7.2.5-8 — duplicate UIDs, GIDs, usernames, group names
# ---------------------------------------------------------------------------
_audit_dup_uids()        { _check_duplicates /etc/passwd 3; }
_audit_dup_gids()        { _check_duplicates /etc/group  3; }
_audit_dup_usernames()   { _check_duplicates /etc/passwd 1; }
_audit_dup_groupnames()  { _check_duplicates /etc/group  1; }

# ---------------------------------------------------------------------------
# CIS 7.2.9 — home directories configured
# ---------------------------------------------------------------------------
_audit_home_dirs() {
    local fail=0

    while IFS=: read -r user home; do
        if [[ ! -d "$home" ]]; then
            log_debug "User ${user}: home dir ${home} does not exist"
            fail=1; continue
        fi

        local owner
        owner=$(stat -Lc '%U' "$home")
        if [[ "$owner" != "$user" ]]; then
            log_debug "User ${user}: home dir owned by ${owner}"
            fail=1
        fi

        local mode
        mode=$(stat -Lc '%#a' "$home")
        if (( mode & HOME_DIR_PERM_MASK )); then
            log_debug "User ${user}: home dir mode ${mode} too permissive"
            fail=1
        fi
    done < <(_get_interactive_users)
    return "$fail"
}

_rem_home_dirs() {
    while IFS=: read -r user home; do
        if [[ -d "$home" ]]; then
            if [[ "$(stat -Lc '%U' "$home")" != "$user" ]]; then
                log_info "Fixing ownership of ${home} → ${user}"
                chown "$user" "$home"
            fi
            if (( $(stat -Lc '%#a' "$home") & HOME_DIR_PERM_MASK )); then
                log_info "Fixing permissions on ${home} (750)"
                chmod g-w,o-rwx "$home"
            fi
        else
            log_warn "Home dir ${home} for user ${user} does not exist — manual action required."
        fi
    done < <(_get_interactive_users)
}

# ---------------------------------------------------------------------------
# CIS 7.2.10 — dot files access configured
# ---------------------------------------------------------------------------
_is_dangerous_dotfile() {
    local fname="$1"
    local df
    for df in "${DOT_FILES_DANGEROUS[@]}"; do
        [[ "$fname" == "$df" ]] && return 0
    done
    return 1
}

_is_strict_dotfile() {
    local fname="$1"
    local sf
    for sf in "${DOT_FILES_STRICT[@]}"; do
        [[ "$fname" == "$sf" ]] && return 0
    done
    return 1
}

_audit_user_dot_files() {
    local fail=0

    while IFS=: read -r user home; do
        [[ -d "$home" ]] || continue
        local primary_group
        primary_group=$(id -gn "$user" 2>/dev/null) || continue

        while IFS= read -r -d '' dotfile; do
            local fname
            fname=$(basename "$dotfile")

            if _is_dangerous_dotfile "$fname"; then
                log_debug "User ${user}: dangerous file ${fname} exists"
                fail=1; continue
            fi

            local mode owner group
            IFS=: read -r mode owner group <<< "$(stat -Lc '%#a:%U:%G' "$dotfile")"

            if [[ "$owner" != "$user" || "$group" != "$primary_group" ]]; then
                log_debug "User ${user}: ${fname} wrong owner/group (${owner}:${group})"
                fail=1
            fi

            local mask="$MASK_DOT_644"
            _is_strict_dotfile "$fname" && mask="$MASK_DOT_600"
            if (( mode & mask )); then
                log_debug "User ${user}: ${fname} mode ${mode} too permissive"
                fail=1
            fi
        done < <(find "$home" -xdev -type f -name ".*" -print0 2>/dev/null)
    done < <(_get_interactive_users)
    return "$fail"
}

_rem_user_dot_files() {
    while IFS=: read -r user home; do
        [[ -d "$home" ]] || continue
        local primary_group
        primary_group=$(id -gn "$user" 2>/dev/null) || continue

        while IFS= read -r -d '' dotfile; do
            local fname
            fname=$(basename "$dotfile")

            if _is_dangerous_dotfile "$fname"; then
                log_warn "User ${user}: ${fname} found — manual deletion recommended."
                continue
            fi

            chown "${user}:${primary_group}" "$dotfile"
            if _is_strict_dotfile "$fname"; then
                chmod 0600 "$dotfile"
            else
                chmod 0644 "$dotfile"
            fi
        done < <(find "$home" -xdev -type f -name ".*" -print0 2>/dev/null)
    done < <(_get_interactive_users)
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#USER_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${USER_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"
        audit_func="${audit_func// /}"
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

    _run_audit_checks "Local User & Group Settings  (CIS 7.2.1 – 7.2.10)" || global_status=1

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

    for entry in "${USER_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 7.2.1 – 7.2.10)" \
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
    echo "CIS Benchmark Debian 13 - Section 7.2: Local User and Group Settings"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply user/group hardening."
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
    echo -e "\n${C_BOLD}--- CIS 7.2 Local User & Group Settings — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply user/group hardening)" > /dev/tty
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
    print_section_header "CIS 7.2" "Local User and Group Settings"
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