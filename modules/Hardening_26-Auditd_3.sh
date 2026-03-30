#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 6.2.4: Configure auditd File Access
#
# Sub-sections covered:
#   6.2.4.1  - Ensure audit log files mode is configured                       (Automated)
#   6.2.4.2  - Ensure audit log files owner is configured                      (Automated)
#   6.2.4.3  - Ensure audit log files group owner is configured                (Automated)
#   6.2.4.4  - Ensure the audit log file directory mode is configured          (Automated)
#   6.2.4.5  - Ensure audit configuration files mode is configured             (Automated)
#   6.2.4.6  - Ensure audit configuration files owner is configured            (Automated)
#   6.2.4.7  - Ensure audit configuration files group owner is configured      (Automated)
#   6.2.4.8  - Ensure audit tools mode is configured                           (Automated)
#   6.2.4.9  - Ensure audit tools owner is configured                          (Automated)
#   6.2.4.10 - Ensure audit tools group owner is configured                    (Automated)

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------
readonly AUDITD_CONF="/etc/audit/auditd.conf"
readonly AUDITD_SVC="auditd"

readonly AUDIT_TOOLS_NAMES='( -name "auditctl" -o -name "aureport" -o -name "ausearch" -o -name "auditd" -o -name "augenrules" )'

# ---------------------------------------------------------------------------
# DATA-DRIVEN: file permission/ownership rules
# ---------------------------------------------------------------------------
readonly -a FILE_RULES=(
    "6.2.4.1|_get_audit_log_dir|-maxdepth 1 -type f -perm /0137|chmod u-x,g-wx,o-rwx|audit log files mode"
    "6.2.4.2|_get_audit_log_dir|-maxdepth 1 -type f ! -user root|chown root|audit log files owner"
    "6.2.4.3|_get_audit_log_dir|-not -path '*/lost+found*' -type f ! -group adm ! -group root|chgrp adm|audit log files group"
    "6.2.4.4|_get_audit_log_dir|-maxdepth 0 -type d -perm /0027|chmod g-w,o-rwx|audit log directory mode"
    "6.2.4.5|/etc/audit/|-type f \\( -name '*.conf' -o -name '*.rules' \\) -perm /0137|chmod u-x,g-wx,o-rwx|audit config files mode"
    "6.2.4.6|/etc/audit/|-type f \\( -name '*.conf' -o -name '*.rules' \\) ! -user root|chown root|audit config files owner"
    "6.2.4.7|/etc/audit/|-type f \\( -name '*.conf' -o -name '*.rules' \\) ! -group root|chgrp root|audit config files group"
    "6.2.4.8|/sbin/|-maxdepth 1 -type f ${AUDIT_TOOLS_NAMES} -perm /0022|chmod go-w|audit tools mode"
    "6.2.4.9|/sbin/|-maxdepth 1 -type f ${AUDIT_TOOLS_NAMES} ! -user root|chown root|audit tools owner"
    "6.2.4.10|/sbin/|-maxdepth 1 -type f ${AUDIT_TOOLS_NAMES} ! -group root|chgrp root|audit tools group"
)

# ---------------------------------------------------------------------------
# DATA-DRIVEN: config parameter rules
# ---------------------------------------------------------------------------
readonly -a CONF_RULES=(
    "6.2.4.3;${AUDITD_CONF};log_group;^(adm|root)$;adm;${AUDITD_SVC};audit log group (config)"
)

# ---------------------------------------------------------------------------
# DATA-DRIVEN: dispatch array — CIS 6.2.4.1 – 6.2.4.10
# ---------------------------------------------------------------------------
readonly -a AUDITD_ACCESS_CHECKS=(
    "6.2.4.1 |_audit_file_check 6.2.4.1 |_rem_file_check 6.2.4.1 |audit log files mode"
    "6.2.4.2 |_audit_file_check 6.2.4.2 |_rem_file_check 6.2.4.2 |audit log files owner"
    "6.2.4.3 |_audit_log_group          |_rem_log_group          |audit log files group owner"
    "6.2.4.4 |_audit_file_check 6.2.4.4 |_rem_file_check 6.2.4.4 |audit log directory mode"
    "6.2.4.5 |_audit_file_check 6.2.4.5 |_rem_file_check 6.2.4.5 |audit config files mode"
    "6.2.4.6 |_audit_file_check 6.2.4.6 |_rem_file_check 6.2.4.6 |audit config files owner"
    "6.2.4.7 |_audit_file_check 6.2.4.7 |_rem_file_check 6.2.4.7 |audit config files group"
    "6.2.4.8 |_audit_file_check 6.2.4.8 |_rem_file_check 6.2.4.8 |audit tools mode"
    "6.2.4.9 |_audit_file_check 6.2.4.9 |_rem_file_check 6.2.4.9 |audit tools owner"
    "6.2.4.10|_audit_file_check 6.2.4.10|_rem_file_check 6.2.4.10|audit tools group"
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

    local W_ID=10 W_DESC=36 W_ST=6
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
        printf "  %s %-38s  " "$branch" "$desc"
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-38s  " "$branch" "$desc"
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Generic utility helpers
# ---------------------------------------------------------------------------

_get_audit_log_dir() {
    [[ -f "$AUDITD_CONF" ]] || return 1
    local log_file
    log_file=$(awk -F '=' '/^[[:space:]]*log_file[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}' \
        "$AUDITD_CONF" | tail -1)
    [[ -n "$log_file" ]] || return 1
    dirname "$log_file"
}

_resolve_dir() {
    local resolver="$1"
    if [[ "$resolver" == _* ]]; then
        "$resolver" || return 1
    else
        printf '%s' "$resolver"
    fi
}

# ---------------------------------------------------------------------------
# Generic file-rule audit / remediation (driven by FILE_RULES data)
# ---------------------------------------------------------------------------
_find_file_rule_entry() {
    local cis_id="$1"
    local entry entry_id
    for entry in "${FILE_RULES[@]}"; do
        entry_id="${entry%%|*}"
        [[ "$entry_id" == "$cis_id" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 1
}

_audit_file_check() {
    local cis_id="$1"
    local entry
    entry=$(_find_file_rule_entry "$cis_id") || { log_debug "No file rule for ${cis_id}"; return 1; }

    local _id resolver find_args _rem _desc
    IFS='|' read -r _id resolver find_args _rem _desc <<< "$entry"

    local target_dir
    target_dir=$(_resolve_dir "$resolver") || { log_debug "Cannot resolve dir for ${cis_id}"; return 1; }
    [[ -d "$target_dir" ]] || { log_debug "Directory ${target_dir} does not exist"; return 1; }

    local violators
    violators=$(eval find "'${target_dir}'" "$find_args" -print 2>/dev/null) || true
    if [[ -n "$violators" ]]; then
        log_debug "${cis_id}: violators found in ${target_dir}"
        return 1
    fi
    return 0
}

_rem_file_check() {
    local cis_id="$1"
    local entry
    entry=$(_find_file_rule_entry "$cis_id") || { log_error "No file rule for ${cis_id}"; return 1; }

    local _id resolver find_args rem_cmd _desc
    IFS='|' read -r _id resolver find_args rem_cmd _desc <<< "$entry"

    local target_dir
    target_dir=$(_resolve_dir "$resolver") || { log_error "Cannot resolve dir for ${cis_id}"; return 1; }
    [[ -d "$target_dir" ]] || { log_error "Directory ${target_dir} does not exist"; return 1; }

    log_info "Fixing: ${_desc} in ${target_dir}..."
    eval find "'${target_dir}'" "$find_args" -exec "$rem_cmd" {} + 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# CIS 6.2.4.3 — compound: config param (log_group) + file ownership
# ---------------------------------------------------------------------------
_find_conf_rule_entry() {
    local cis_id="$1"
    local entry entry_id
    for entry in "${CONF_RULES[@]}"; do
        entry_id="${entry%%;*}"
        [[ "$entry_id" == "$cis_id" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 1
}

_audit_conf_param() {
    local cis_id="$1"
    local entry
    entry=$(_find_conf_rule_entry "$cis_id") || return 1

    local _id file key regex _target _svc _desc
    IFS=';' read -r _id file key regex _target _svc _desc <<< "$entry"

    [[ -f "$file" ]] || { log_debug "Config file ${file} not found"; return 1; }

    local current_val
    current_val=$(awk -F '=' "/^[[:space:]]*${key}[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$/,\"\",\$2); print \$2}" \
        "$file" | tail -1)
    if [[ -z "$current_val" || ! "$current_val" =~ $regex ]]; then
        log_debug "${cis_id}: ${key}='${current_val}' (expected match '${regex}')"
        return 1
    fi
    return 0
}

_remediate_conf_param() {
    local cis_id="$1"
    local entry
    entry=$(_find_conf_rule_entry "$cis_id") || return 1

    local _id file key _regex target svc _desc
    IFS=';' read -r _id file key _regex target svc _desc <<< "$entry"

    log_info "Setting ${key} → ${target} in ${file}"
    if grep -qE "^\s*#?\s*${key}\s*=" "$file" 2>/dev/null; then
        sed -ri "s/^\s*#?\s*${key}\s*=.*$/${key} = ${target}/" "$file"
    else
        printf '%s = %s\n' "$key" "$target" >> "$file"
    fi
    if [[ -n "$svc" ]]; then
        systemctl restart "$svc" 2>/dev/null || true
    fi
}

_audit_log_group() {
    local fail=0
    _audit_conf_param "6.2.4.3"      || fail=1
    _audit_file_check "6.2.4.3"      || fail=1
    return "$fail"
}

_rem_log_group() {
    _remediate_conf_param "6.2.4.3"
    _rem_file_check "6.2.4.3"
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#AUDITD_ACCESS_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${AUDITD_ACCESS_CHECKS[@]}"; do
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

    _run_audit_checks "auditd File Access  (CIS 6.2.4.1 – 6.2.4.10)" || global_status=1

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

    for entry in "${AUDITD_ACCESS_CHECKS[@]}"; do
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
    _run_audit_checks "Post-Remediation Verification  (CIS 6.2.4.1 – 6.2.4.10)" \
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
    echo "CIS Benchmark Debian 13 - Section 6.2.4: Configure auditd File Access"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply auditd file access hardening."
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
    echo -e "\n${C_BOLD}--- CIS 6.2.4 auditd File Access — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply file access hardening)" > /dev/tty
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
    print_section_header "CIS 6.2.4" "Configure auditd File Access"
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