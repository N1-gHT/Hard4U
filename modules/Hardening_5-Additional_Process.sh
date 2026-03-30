#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.5: Configure Additional Process Hardening
#
# Sub-sections covered:
#   1.5.1  - Ensure fs.protected_hardlinks is configured
#   1.5.2  - Ensure fs.protected_symlinks is configured
#   1.5.3  - Ensure kernel.yama.ptrace_scope is configured
#   1.5.4  - Ensure fs.suid_dumpable is configured
#   1.5.5  - Ensure kernel.dmesg_restrict is configured
#   1.5.6  - Ensure prelink is not installed
#   1.5.7  - Ensure Automatic Error Reporting is configured (apport)
#   1.5.8  - Ensure kernel.kptr_restrict is configured
#   1.5.9  - Ensure kernel.randomize_va_space is configured
#   1.5.10 - Ensure kernel.yama.ptrace_scope is configured (persistence)
#   1.5.11 - Ensure core file size is configured
#   1.5.12 - Ensure systemd-coredump ProcessSizeMax is configured
#   1.5.13 - Ensure systemd-coredump Storage is configured

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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------

readonly APPORT_CONF="/etc/default/apport"
readonly APPORT_SVC="apport.service"
readonly LIMITS_CONF="/etc/security/limits.conf"
readonly LIMITS_D_DIR="/etc/security/limits.d"
readonly CORE_LIMIT_FILE="/etc/security/limits.d/60-limits.conf"
readonly COREDUMP_CONF_DIR="/etc/systemd/coredump.conf.d"
readonly COREDUMP_HARDENING_FILE="${COREDUMP_CONF_DIR}/60-coredump.conf"
readonly SYSCTL_HARDENING_FILE="/etc/sysctl.d/60-process_hardening.conf"

readonly -a SYSCTL_CHECKS=(
    "1.5.1|fs.protected_hardlinks|^1$|1|Protected hardlinks"
    "1.5.2|fs.protected_symlinks|^1$|1|Protected symlinks"
    "1.5.3|kernel.yama.ptrace_scope|^[1-3]$|current:1|Yama ptrace scope"
    "1.5.4|fs.suid_dumpable|^0$|0|SUID dumpable"
    "1.5.5|kernel.dmesg_restrict|^1$|1|dmesg restriction"
    "1.5.8|kernel.kptr_restrict|^[1-2]$|current:2|Kernel pointer restriction"
    "1.5.9|kernel.randomize_va_space|^2$|2|ASLR (randomize_va_space)"
    "1.5.10|kernel.yama.ptrace_scope|^[1-3]$|current:1|Yama ptrace scope (persistence)"
)

readonly -a SPECIAL_CHECKS=(
    "1.5.6|_audit_prelink|_remediate_prelink|prelink not installed"
    "1.5.7|_audit_apport|_remediate_apport|Apport error reporting disabled"
    "1.5.11|_audit_core_limit|_remediate_core_limit|Core dump hard limit = 0"
)

readonly -a COREDUMP_CHECKS=(
    "1.5.12|ProcessSizeMax|0|systemd-coredump ProcessSizeMax=0"
    "1.5.13|Storage|none|systemd-coredump Storage=none"
)

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
declare -a _RESULT_IDS=()
declare -a _RESULT_DESCS=()
declare -a _RESULT_STATUSES=()
declare -a _RESULT_DETAILS=()

record_result() {
    _RESULT_IDS+=("$1")
    _RESULT_DESCS+=("$2")
    _RESULT_STATUSES+=("$3")
    _RESULT_DETAILS+=("${4:-}")
}

reset_results() {
    _RESULT_IDS=()
    _RESULT_DESCS=()
    _RESULT_STATUSES=()
    _RESULT_DETAILS=()
}

# ---------------------------------------------------------------------------
# Summary table
# Column inner widths: W_ID=8  W_DESC=44  W_ST=6
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

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
# Tree row renderer + record_result — used by all three phases.
# Calls the audit function silently and renders one tree row.
# $1=cis_id  $2=description  $3=branch  $4+=audit command + args
# Returns 0=PASS, 1=FAIL.
# ---------------------------------------------------------------------------
_audit_tree_row() {
    local cis_id="$1" desc="$2" branch="$3"
    shift 3

    local status=0
    "$@" || status=1

    if [[ "$status" -eq 0 ]]; then
        printf "  %s %-46s  ${C_GREEN}[PASS]${C_RESET}\n" "$branch" "$desc"
        record_result "$cis_id" "$desc" "PASS"
        return 0
    else
        printf "  %s %-46s  ${C_BRIGHT_RED}[FAIL]${C_RESET}\n" "$branch" "$desc"
        record_result "$cis_id" "$desc" "FAIL"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Sysctl helpers
# ---------------------------------------------------------------------------

_get_sysctl_files() {
    local l_systemdsysctl
    l_systemdsysctl="$(readlink -e /lib/systemd/systemd-sysctl 2>/dev/null \
        || readlink -e /usr/lib/systemd/systemd-sysctl 2>/dev/null || true)"

    local l_ufw_file=""
    if [[ -f /etc/default/ufw ]]; then
        l_ufw_file="$(awk -F= '/^\s*IPT_SYSCTL=/{print $2}' /etc/default/ufw)"
    fi

    local -a a_files=()
    [[ -f "$(readlink -e "$l_ufw_file" 2>/dev/null)" ]] \
        && a_files+=("$(readlink -e "$l_ufw_file")")

    a_files+=("/etc/sysctl.conf")

    if [[ -n "$l_systemdsysctl" ]]; then
        while IFS= read -r l_fname; do
            local l_file
            l_file="$(readlink -e "${l_fname//# /}" 2>/dev/null || true)"
            if [[ -n "$l_file" && ! " ${a_files[*]} " =~ ${l_file} ]]; then
                a_files+=("$l_file")
            fi
        done < <("$l_systemdsysctl" --cat-config 2>/dev/null \
            | tac \
            | grep -Psio -- '^\h*#\h*\/[^#\n\r\h]+\.conf\b')
    fi

    printf '%s\n' "${a_files[@]}"
}

_audit_generic_sysctl() {
    local param="$1"
    local expected_regex="$2"
    local fail=0

    local current_val
    current_val=$(sysctl -n "$param" 2>/dev/null || echo "not_found")
    if [[ ! "$current_val" =~ $expected_regex ]]; then
        log_debug "Audit fail: $param running value = $current_val"
        fail=1
    fi

    local -a files
    mapfile -t files < <(_get_sysctl_files)

    local found_correct=false
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            local l_opt
            l_opt="$(grep -Psoi '^\h*'"${param//./\\.}"'\h*=\h*\H+\b' "$f" \
                | tail -n 1 || true)"
            if [[ -n "$l_opt" ]]; then
                local l_val
                l_val=$(cut -d= -f2 <<< "$l_opt" | xargs)
                if [[ "$l_val" =~ $expected_regex ]]; then
                    found_correct=true
                else
                    log_debug "Audit fail: $param persisted as $l_val in $f"
                    fail=1
                fi
                break
            fi
        fi
    done

    [[ "$found_correct" == "false" ]] && fail=1
    return "$fail"
}

_remediate_generic_sysctl() {
    local param="$1"
    local value="$2"
    local expected_regex="$3"

    local -a files
    mapfile -t files < <(_get_sysctl_files)

    for f in "${files[@]}"; do
        if [[ -f "$f" && "$f" != "$SYSCTL_HARDENING_FILE" ]]; then
            if grep -Psio -- '\h*'"${param//./\\.}"'\h*=\h*\H+\b' "$f" \
                    | grep -Psivq -- '=\h*'"$expected_regex"'\b' 2>/dev/null; then
                log_info "Commenting out conflicting value in $f"
                sed -ri '/^\s*'"${param//./\\.}"'\s*=\s*/s/^/# /' "$f"
            fi
        fi
    done

    mkdir -p "$(dirname "$SYSCTL_HARDENING_FILE")"

    if grep -q "^${param} =" "$SYSCTL_HARDENING_FILE" 2>/dev/null; then
        sed -i "s|^${param} =.*|${param} = ${value}|" "$SYSCTL_HARDENING_FILE"
    else
        printf '%s = %s\n' "$param" "$value" >> "$SYSCTL_HARDENING_FILE"
    fi

    sysctl -w "${param}=${value}" >/dev/null 2>&1 || \
        log_warn "Could not apply $param=$value at runtime — will take effect after reboot."
}

_remediate_one_sysctl() {
    local param="$1" expected_regex="$2" remediate_val="$3"

    if [[ "$remediate_val" == current:* ]]; then
        local default_val="${remediate_val#current:}"
        local current
        current=$(sysctl -n "$param" 2>/dev/null || true)
        if [[ "$current" =~ $expected_regex ]]; then
            remediate_val="$current"
        else
            remediate_val="$default_val"
        fi
    fi

    _remediate_generic_sysctl "$param" "$remediate_val" "$expected_regex"
}

# ---------------------------------------------------------------------------
# CIS 1.5.6 — prelink not installed
# ---------------------------------------------------------------------------

_audit_prelink() {
    if dpkg-query -W -f='${Status}' prelink 2>/dev/null | grep -q "ok installed"; then
        log_debug "prelink is installed"
        return 1
    fi
    return 0
}

_remediate_prelink() {
    if command -v prelink &>/dev/null; then
        log_info "Restoring binaries before uninstall (prelink -ua)..."
        prelink -ua 2>/dev/null || log_warn "prelink -ua failed — proceeding with purge anyway."
    fi
    if apt-get purge -y prelink >/dev/null 2>&1; then
        log_ok "Package 'prelink' purged."
    else
        log_error "Failed to purge 'prelink'."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.5.7 — Apport disabled
# ---------------------------------------------------------------------------

_audit_apport() {
    if ! dpkg-query -W -f='${Status}' apport 2>/dev/null | grep -q "ok installed"; then
        return 0
    fi

    if grep -Psiq -- '^\h*enabled\h*=\h*[^0]\b' "$APPORT_CONF" 2>/dev/null; then
        log_debug "apport enabled in $APPORT_CONF"
        return 1
    fi

    if systemctl is-active "$APPORT_SVC" 2>/dev/null | grep -q '^active'; then
        log_debug "apport.service is active"
        return 1
    fi

    return 0
}

_remediate_apport() {
    if [[ -f "$APPORT_CONF" ]]; then
        sed -ri 's/^\s*enabled\s*=\s*.*/enabled=0/' "$APPORT_CONF"
    else
        echo "enabled=0" > "$APPORT_CONF"
    fi
    systemctl stop "$APPORT_SVC" 2>/dev/null || true
    systemctl mask "$APPORT_SVC" 2>/dev/null
    log_ok "Apport stopped and masked."
}

# ---------------------------------------------------------------------------
# CIS 1.5.11 — Core dump hard limit = 0
# ---------------------------------------------------------------------------

_audit_core_limit() {
    local -a files=("$LIMITS_CONF")

    if [[ -d "$LIMITS_D_DIR" ]]; then
        local -a d_files=("$LIMITS_D_DIR"/*.conf)
        [[ -f "${d_files[0]}" ]] && files+=("${d_files[@]}")
    fi

    local bad
    bad=$(grep -Psi '^\s*[^#\n\r]+\s+hard\s+core\s+[1-9]' "${files[@]}" 2>/dev/null || true)
    if [[ -n "$bad" ]]; then
        log_debug "Non-zero core hard limit found:\n$bad"
        return 1
    fi

    if ! grep -Psq '^\s*\*\s+hard\s+core\s+0\b' "${files[@]}" 2>/dev/null; then
        log_debug "No '* hard core 0' entry found in limits files"
        return 1
    fi

    return 0
}

_remediate_core_limit() {
    local -a files=("$LIMITS_CONF")
    if [[ -d "$LIMITS_D_DIR" ]]; then
        local -a d_files=("$LIMITS_D_DIR"/*.conf)
        [[ -f "${d_files[0]}" ]] && files+=("${d_files[@]}")
    fi

    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        sed -ri '/^\s*[^#\n\r]+\s+hard\s+core\s+[1-9]/s/^/# /' "$f"
    done

    mkdir -p "$LIMITS_D_DIR"
    if ! grep -Psq '^\s*\*\s+hard\s+core\s+0\b' "$CORE_LIMIT_FILE" 2>/dev/null; then
        printf '\n* hard core 0\n' >> "$CORE_LIMIT_FILE"
        log_ok "Added '* hard core 0' to $CORE_LIMIT_FILE."
    else
        log_ok "'* hard core 0' already present in $CORE_LIMIT_FILE."
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.5.12–1.5.13 — systemd-coredump generic helpers
# ---------------------------------------------------------------------------

_audit_coredump_key() {
    local key="$1" expected="$2"

    if ! dpkg-query -s systemd-coredump &>/dev/null; then
        log_debug "systemd-coredump not installed — compliant."
        return 0
    fi

    local analyze_cmd
    analyze_cmd="$(readlink -e /bin/systemd-analyze 2>/dev/null \
        || readlink -e /usr/bin/systemd-analyze 2>/dev/null || true)"

    if [[ -z "$analyze_cmd" ]]; then
        log_debug "systemd-analyze not found"
        return 1
    fi

    local val
    val=$("$analyze_cmd" cat-config systemd/coredump.conf 2>/dev/null \
        | awk '/\[Coredump\]/{a=1;next}/\[/{a=0}a' \
        | grep -Pi "^\h*${key}\h*=" \
        | tail -n1 | cut -d= -f2 | xargs || true)

    log_debug "_audit_coredump_key $key: effective='$val' expected='$expected'"
    [[ "$val" == "$expected" ]]
}

_remediate_coredump_key() {
    local key="$1" value="$2"

    if ! dpkg-query -s systemd-coredump &>/dev/null; then
        log_info "systemd-coredump not installed — skipping."
        return 0
    fi

    if [[ -d "$COREDUMP_CONF_DIR" ]]; then
        while IFS= read -r -d $'\0' f; do
            if awk '/\[Coredump\]/{a=1;next}/\[/{a=0}a' "$f" 2>/dev/null \
                    | grep -Piq "^\h*${key}\h*="; then
                log_info "Commenting out ${key} in $f"
                sed -ri "/^\s*${key}\s*=/s/^/# /" "$f"
            fi
        done < <(find "$COREDUMP_CONF_DIR" -type f -name '*.conf' -print0)
    fi

    mkdir -p "$COREDUMP_CONF_DIR"

    if [[ -f "$COREDUMP_HARDENING_FILE" ]] \
            && grep -q '^\[Coredump\]' "$COREDUMP_HARDENING_FILE"; then
        if grep -q "^${key}=" "$COREDUMP_HARDENING_FILE"; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$COREDUMP_HARDENING_FILE"
        else
            sed -i "/^\[Coredump\]/a ${key}=${value}" "$COREDUMP_HARDENING_FILE"
        fi
    else
        if [[ -f "$COREDUMP_HARDENING_FILE" ]]; then
            printf '\n[Coredump]\n%s=%s\n' "$key" "$value" >> "$COREDUMP_HARDENING_FILE"
        else
            printf '[Coredump]\n%s=%s\n' "$key" "$value" > "$COREDUMP_HARDENING_FILE"
        fi
    fi

    log_ok "Set ${key}=${value} in $COREDUMP_HARDENING_FILE."

    systemctl reload-or-restart systemd-coredump.socket 2>/dev/null || {
        log_warn "Could not reload systemd-coredump.socket (may require reboot)."
    }
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_check_compliance() {
    local audit_func="$1" msg_ok="$2" msg_fail="$3"
    local prefix="${4:-Audit}"
    if "$audit_func"; then
        log_ok "${prefix}: ${msg_ok}"
        return 0
    else
        log_warn "${prefix}: ${msg_fail}"
        return 1
    fi
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

# Phase 1: Audit Only
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0

    _tree_label "Sysctl Parameters  (CIS 1.5.1 – 1.5.5 / 1.5.8 – 1.5.10)"
    local last_s=$(( ${#SYSCTL_CHECKS[@]} - 1 ))
    for i in "${!SYSCTL_CHECKS[@]}"; do
        local cis_id param expected rem_val desc
        IFS='|' read -r cis_id param expected rem_val desc <<< "${SYSCTL_CHECKS[$i]}"
        local branch; [[ $i -eq $last_s ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_generic_sysctl "$param" "$expected" || global_status=1
    done

    _tree_label "Process Controls  (CIS 1.5.6 / 1.5.7 / 1.5.11)"
    local last_sp=$(( ${#SPECIAL_CHECKS[@]} - 1 ))
    for i in "${!SPECIAL_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "${SPECIAL_CHECKS[$i]}"
        local branch; [[ $i -eq $last_sp ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
    done

    _tree_label "Core Dump Configuration  (CIS 1.5.12 – 1.5.13)"
    local last_c=$(( ${#COREDUMP_CHECKS[@]} - 1 ))
    for i in "${!COREDUMP_CHECKS[@]}"; do
        local cis_id key expected desc
        IFS='|' read -r cis_id key expected desc <<< "${COREDUMP_CHECKS[$i]}"
        local branch; [[ $i -eq $last_c ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_coredump_key "$key" "$expected" || global_status=1
    done

    print_summary_table

    if [[ "$global_status" -eq 0 ]]; then
        log_ok "Global Audit: SYSTEM IS COMPLIANT."
    else
        log_warn "Global Audit: SYSTEM IS NOT COMPLIANT."
    fi

    return "$global_status"
}

# Phase 2: Remediation Only
run_phase_remediation() {
    print_section_header "MODE" "REMEDIATION ONLY"
    local any_failure=false

    for entry in "${SYSCTL_CHECKS[@]}"; do
        local cis_id param expected rem_val desc
        IFS='|' read -r cis_id param expected rem_val desc <<< "$entry"
        if ! _audit_generic_sysctl "$param" "$expected"; then
            log_info "[$cis_id] Remediating: $desc..."
            _remediate_one_sysctl "$param" "$expected" "$rem_val" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    for entry in "${SPECIAL_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        if ! "$audit_func"; then
            log_info "[$cis_id] Remediating: $desc..."
            "$rem_func" || any_failure=true
        else
            log_ok "[$cis_id] $desc — already compliant."
        fi
    done

    for entry in "${COREDUMP_CHECKS[@]}"; do
        local cis_id key expected desc
        IFS='|' read -r cis_id key expected desc <<< "$entry"
        if ! _audit_coredump_key "$key" "$expected"; then
            log_info "[$cis_id] Remediating: $desc..."
            _remediate_coredump_key "$key" "$expected" || any_failure=true
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

# Phase 3: Auto (Audit -> Remediation -> Re-Audit)
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

    _tree_label "Post-Remediation Verification — Sysctl  (CIS 1.5.1 – 1.5.5 / 1.5.8 – 1.5.10)"
    local last_s=$(( ${#SYSCTL_CHECKS[@]} - 1 ))
    for i in "${!SYSCTL_CHECKS[@]}"; do
        local cis_id param expected rem_val desc
        IFS='|' read -r cis_id param expected rem_val desc <<< "${SYSCTL_CHECKS[$i]}"
        local branch; [[ $i -eq $last_s ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_generic_sysctl "$param" "$expected" || verify_status=1
    done

    _tree_label "Post-Remediation Verification — Process Controls  (CIS 1.5.6 / 1.5.7 / 1.5.11)"
    local last_sp=$(( ${#SPECIAL_CHECKS[@]} - 1 ))
    for i in "${!SPECIAL_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "${SPECIAL_CHECKS[$i]}"
        local branch; [[ $i -eq $last_sp ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || verify_status=1
    done

    _tree_label "Post-Remediation Verification — Core Dump  (CIS 1.5.12 – 1.5.13)"
    local last_c=$(( ${#COREDUMP_CHECKS[@]} - 1 ))
    for i in "${!COREDUMP_CHECKS[@]}"; do
        local cis_id key expected desc
        IFS='|' read -r cis_id key expected desc <<< "${COREDUMP_CHECKS[$i]}"
        local branch; [[ $i -eq $last_c ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" \
            _audit_coredump_key "$key" "$expected" || verify_status=1
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
    echo "CIS Benchmark Debian 13 - Section 1.5: Configure Additional Process Hardening"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply process hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 1.5 Additional Process Hardening — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply hardening configurations)" > /dev/tty
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
    print_section_header "CIS 1.5" "Configure Additional Process Hardening"
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