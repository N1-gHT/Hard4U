#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section 1.2.1: Configure Package Repositories
#
# Sub-sections covered:
#   1.2.1.1 - Ensure source.list/.sources files use the Signed-By option (Manual)
#   1.2.1.2 - Ensure weak dependencies are configured
#   1.2.1.3 - Ensure access to GPG key files is configured
#   1.2.1.4 - Ensure access to /etc/apt/trusted.gpg.d is configured
#   1.2.1.5 - Ensure access to /etc/apt/auth.conf.d is configured
#   1.2.1.6 - Ensure access to files in /etc/apt/auth.conf.d/ is configured
#   1.2.1.7 - Ensure access to /usr/share/keyrings is configured
#   1.2.1.8 - Ensure access to /etc/apt/sources.list.d is configured
#   1.2.1.9 - Ensure access to files in /etc/apt/sources.list.d is configured

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors — auto-disabled when stdout is not a TTY or NO_COLOR=true
# Follows the no-color.org convention; compatible with non-interactive callers.
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
# Global variables — single source of truth (DATA-DRIVEN)
# ---------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

readonly APT_SOURCES_LIST="/etc/apt/sources.list"
readonly APT_SOURCES_DIR="/etc/apt/sources.list.d"
readonly APT_WEAK_DEPS_CONF="/etc/apt/apt.conf.d/60-no-weak-dependencies"
readonly APT_AUTH_DIR="/etc/apt/auth.conf.d"
readonly APT_SHARE_KEYRINGS_DIR="/usr/share/keyrings"
readonly TRUSTED_GPG_DIR="/etc/apt/trusted.gpg.d"

readonly -a WEAK_DEP_SETTINGS=(
    "APT::Install-Recommends|0"
    "APT::Install-Suggests|0"
)

readonly -a KEYRING_DIRS=(
    "${TRUSTED_GPG_DIR}/"
    "${APT_SHARE_KEYRINGS_DIR}/"
)

readonly -a APT_DIR_CHECKS=(
    "1.2.1.4|${TRUSTED_GPG_DIR}|compliant|0755"
    "1.2.1.5|${APT_AUTH_DIR}|compliant|0755"
    "1.2.1.7|${APT_SHARE_KEYRINGS_DIR}|warn|0755"
    "1.2.1.8|${APT_SOURCES_DIR}|warn|0755"
)

readonly -a APT_FILE_CHECKS=(
    "1.2.1.6|${APT_AUTH_DIR}|/137|0640|compliant"
    "1.2.1.9|${APT_SOURCES_DIR}|/133|0644|compliant"
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
# Column inner widths: W_ID=9  W_DESC=36  W_ST=6
# ---------------------------------------------------------------------------
print_summary_table() {
    [[ "${#_RESULT_IDS[@]}" -eq 0 ]] && return 0

    local pass_count=0 fail_count=0
    for status in "${_RESULT_STATUSES[@]}"; do
        if [[ "$status" == "PASS" ]]; then (( ++pass_count )); else (( ++fail_count )); fi
    done
    local total="${#_RESULT_IDS[@]}"

    local W_ID=9 W_DESC=36 W_ST=6

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
# Permission helpers
# ---------------------------------------------------------------------------

_mode_lte_755() {
    [[ "$1" =~ ^0?[0-7]?[0-7][0145][0145]$ ]]
}

# ---------------------------------------------------------------------------
# CIS 1.2.1.1 — APT sources Signed-By (Manual)
# ---------------------------------------------------------------------------

audit_apt_sources_signed_by() {
    _tree_label "APT Sources Signed-By  (CIS 1.2.1.1 — Manual)"

    local non_compliant
    non_compliant=$(grep -PRLs -- '^([^#\n\r]+)?\bSigned-By\b' \
        "$APT_SOURCES_LIST" "$APT_SOURCES_DIR" 2>/dev/null \
        | grep -E '\.(list|sources)$|^/etc/apt/sources\.list$' || true)

    if [[ -z "$non_compliant" ]]; then
        printf "  └─ %-30s  ${C_GREEN}[PASS]${C_RESET} all sources use Signed-By\n" "sources.list(.d)"
        record_result "1.2.1.1" "APT sources: Signed-By" "PASS"
        return 0
    else
        local count; count=$(echo "$non_compliant" | wc -l)
        printf "  └─ %-30s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s file(s) missing Signed-By\n" \
            "sources.list(.d)" "$count"
        log_debug "Files without Signed-By:\n$non_compliant"
        record_result "1.2.1.1" "APT sources: Signed-By" "FAIL" "$count files missing"
        return 1
    fi
}

remediate_apt_sources_signed_by() {
    print_section_header "REMEDIATION" "APT Sources Modernization (CIS 1.2.1.1)"

    log_warn "CIS 1.2.1.1 is a Manual check. The following is a best-effort automated attempt."

    if ! apt help modernize-sources &>/dev/null; then
        log_error "'apt modernize-sources' is not available on this system."
        log_info "Manual intervention required: add 'Signed-By' to your APT source entries."
        return 1
    fi

    log_info "Backing up APT sources..."
    local backup_dir
    backup_dir="/var/backups/apt_sources_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$APT_SOURCES_LIST" "$APT_SOURCES_DIR/" "$backup_dir/" 2>/dev/null || true
    log_ok "Backup created: $backup_dir"

    log_info "Running 'apt modernize-sources'..."
    if apt modernize-sources --assume-yes; then
        log_ok "APT sources modernized to DEB822 format."
        log_info "Verifying with apt-get update..."
        if apt-get update -q; then
            log_ok "APT update successful with new configuration."
        else
            log_error "APT update failed after modernization. Manual review required."
            return 1
        fi
    else
        log_error "Failed to run 'apt modernize-sources'."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.2.1.2 — Weak dependencies (DATA-DRIVEN on WEAK_DEP_SETTINGS)
# ---------------------------------------------------------------------------

audit_apt_weak_deps() {
    local audit_fail=0
    local last=$(( ${#WEAK_DEP_SETTINGS[@]} - 1 ))

    _tree_label "APT Weak Dependencies  (CIS 1.2.1.2)"

    for i in "${!WEAK_DEP_SETTINGS[@]}"; do
        local entry="${WEAK_DEP_SETTINGS[$i]}"
        local key expected
        IFS='|' read -r key expected <<< "$entry"
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        local current
        current=$(apt-config dump 2>/dev/null | grep "^${key} " | cut -d'"' -f2 || true)

        if [[ -z "$current" ]]; then
            [[ "$key" == "APT::Install-Recommends" ]] && current="1" || current="0"
        fi

        if [[ "$current" == "$expected" ]]; then
            printf "  %s %-30s  ${C_GREEN}[PASS]${C_RESET} = %s\n" "$branch" "$key" "$current"
            record_result "1.2.1.2" "$key" "PASS"
        else
            printf "  %s %-30s  ${C_BRIGHT_RED}[FAIL]${C_RESET} = %s (expected %s)\n" \
                "$branch" "$key" "$current" "$expected"
            record_result "1.2.1.2" "$key" "FAIL" "value=$current"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

remediate_apt_weak_deps() {
    log_info "Writing weak dependency config to $APT_WEAK_DEPS_CONF..."

    local content=""
    for entry in "${WEAK_DEP_SETTINGS[@]}"; do
        local key expected
        IFS='|' read -r key expected <<< "$entry"
        content+="${key} \"${expected}\";\n"
    done

    if printf '%b' "$content" > "$APT_WEAK_DEPS_CONF"; then
        log_ok "Weak dependencies configured in $APT_WEAK_DEPS_CONF."
    else
        log_error "Failed to write $APT_WEAK_DEPS_CONF."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CIS 1.2.1.3 — GPG key file access (DATA-DRIVEN on KEYRING_DIRS)
# ---------------------------------------------------------------------------

audit_gpg_key_access() {
    local audit_fail=0
    local last=$(( ${#KEYRING_DIRS[@]} - 1 ))

    _tree_label "GPG Key File Access  (CIS 1.2.1.3)"

    for i in "${!KEYRING_DIRS[@]}"; do
        local dir="${KEYRING_DIRS[$i]}"
        local short; short=$(basename "${dir%/}")
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if [[ ! -d "$dir" ]]; then
            printf "  %s %-28s  ${C_DIM}[SKIP]${C_RESET} directory not found\n" "$branch" "$short"
            continue
        fi

        local bad_files
        bad_files=$(find -L "$dir" -mount -xdev -type f \
            \( ! -user root -o ! -group root -o -perm /133 \) \
            -name '*gpg' 2>/dev/null || true)

        if [[ -z "$bad_files" ]]; then
            printf "  %s %-28s  ${C_GREEN}[PASS]${C_RESET} all .gpg files root:root 0644\n" "$branch" "$short"
            record_result "1.2.1.3" "gpg files: $short" "PASS"
        else
            local count; count=$(echo "$bad_files" | wc -l)
            printf "  %s %-28s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s file(s) non-compliant\n" \
                "$branch" "$short" "$count"
            log_debug "Non-compliant GPG files in $dir:\n$bad_files"
            record_result "1.2.1.3" "gpg files: $short" "FAIL" "$count non-compliant"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

remediate_gpg_key_access() {
    print_section_header "REMEDIATION" "GPG Key File Access (CIS 1.2.1.3)"
    local any_failure=false

    for dir in "${KEYRING_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue

        local bad_files
        bad_files=$(find -L "$dir" -mount -xdev -type f \
            \( ! -user root -o ! -group root -o -perm /133 \) \
            -name '*gpg' 2>/dev/null || true)

        [[ -z "$bad_files" ]] && continue

        log_info "Fixing GPG file permissions in $dir..."
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if chown root:root "$f" && chmod 0644 "$f"; then
                log_ok "  Fixed: $f"
            else
                log_error "  Failed: $f"
                any_failure=true
            fi
        done <<< "$bad_files"
    done

    [[ "$any_failure" == "true" ]] && return 1 || return 0
}

# ---------------------------------------------------------------------------
# CIS 1.2.1.4 / 1.2.1.5 / 1.2.1.7 / 1.2.1.8
# ---------------------------------------------------------------------------

audit_apt_directories() {
    local audit_fail=0
    local last=$(( ${#APT_DIR_CHECKS[@]} - 1 ))

    _tree_label "APT Directory Access  (CIS 1.2.1.4 / 1.2.1.5 / 1.2.1.7 / 1.2.1.8)"

    for i in "${!APT_DIR_CHECKS[@]}"; do
        local entry="${APT_DIR_CHECKS[$i]}"
        local cis_id path missing_behavior remediate_mode
        IFS='|' read -r cis_id path missing_behavior remediate_mode <<< "$entry"

        local short; short=$(basename "$path")
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"

        if [[ ! -d "$path" ]]; then
            case "$missing_behavior" in
                compliant)
                    printf "  %s %-28s  ${C_DIM}[SKIP]${C_RESET} does not exist (compliant)\n" "$branch" "$short"
                    record_result "$cis_id" "$short dir" "PASS" "absent (compliant)"
                    ;;
                warn)
                    printf "  %s %-28s  ${C_BRIGHT_RED}[FAIL]${C_RESET} directory not found\n" "$branch" "$short"
                    record_result "$cis_id" "$short dir" "FAIL" "directory not found"
                    audit_fail=1
                    ;;
            esac
            continue
        fi

        local file_stat mode uid gid
        file_stat=$(stat -Lc '%a %u %g' "$path" 2>/dev/null)
        read -r mode uid gid <<< "$file_stat"

        local fail_reasons=()
        [[ "$uid" -ne 0 || "$gid" -ne 0 ]] && \
            fail_reasons+=("owner: $(stat -Lc '%U:%G' "$path") (expected root:root)")
        _mode_lte_755 "$mode" || fail_reasons+=("mode: $mode (expected ≤ 0755)")

        if [[ "${#fail_reasons[@]}" -eq 0 ]]; then
            printf "  %s %-28s  ${C_GREEN}[PASS]${C_RESET} root:root  %s\n" "$branch" "$short" "$mode"
            record_result "$cis_id" "$short dir" "PASS"
        else
            local detail; detail=$(printf '%s  ' "${fail_reasons[@]}")
            printf "  %s %-28s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s\n" "$branch" "$short" "$detail"
            record_result "$cis_id" "$short dir" "FAIL" "$detail"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

remediate_apt_directories() {
    print_section_header "REMEDIATION" "APT Directory Access"
    local any_failure=false

    for entry in "${APT_DIR_CHECKS[@]}"; do
        local cis_id path missing_behavior remediate_mode
        IFS='|' read -r cis_id path missing_behavior remediate_mode <<< "$entry"

        if [[ ! -d "$path" ]]; then
            [[ "$missing_behavior" == "compliant" ]] && continue
            log_warn "[$cis_id] $path not found, skipping."
            continue
        fi

        log_info "[$cis_id] Applying root:root / $remediate_mode to $path..."
        if chown root:root "$path" && chmod "$remediate_mode" "$path"; then
            log_ok "  $path fixed."
        else
            log_error "  Failed to fix $path."
            any_failure=true
        fi
    done

    [[ "$any_failure" == "true" ]] && return 1 || return 0
}

# ---------------------------------------------------------------------------
# CIS 1.2.1.6 / 1.2.1.9
# ---------------------------------------------------------------------------

audit_apt_files() {
    local audit_fail=0
    local last=$(( ${#APT_FILE_CHECKS[@]} - 1 ))

    _tree_label "APT File Access  (CIS 1.2.1.6 / 1.2.1.9)"

    for i in "${!APT_FILE_CHECKS[@]}"; do
        local entry="${APT_FILE_CHECKS[$i]}"
        local cis_id path find_mask remediate_mode missing_behavior
        IFS='|' read -r cis_id path find_mask remediate_mode missing_behavior <<< "$entry"

        local short; short=$(basename "$path")
        local branch; [[ $i -eq $last ]] && branch="└─" || branch="├─"
        local display_mode="${remediate_mode#0}"

        if [[ ! -d "$path" ]] || [[ -z "$(ls -A "$path" 2>/dev/null)" ]]; then
            if [[ "$missing_behavior" == "compliant" ]]; then
                printf "  %s %-30s  ${C_DIM}[SKIP]${C_RESET} no files found (compliant)\n" \
                    "$branch" "$short files ($display_mode)"
                record_result "$cis_id" "$short files" "PASS" "no files (compliant)"
            else
                printf "  %s %-30s  ${C_BRIGHT_RED}[FAIL]${C_RESET} directory not found\n" \
                    "$branch" "$short files ($display_mode)"
                record_result "$cis_id" "$short files" "FAIL" "directory not found"
                audit_fail=1
            fi
            continue
        fi

        local non_compliant
        non_compliant=$(find "$path" -type f \
            \( ! -user root -o ! -group root -o -perm "$find_mask" \) 2>/dev/null || true)

        if [[ -z "$non_compliant" ]]; then
            printf "  %s %-30s  ${C_GREEN}[PASS]${C_RESET} all files root:root %s\n" \
                "$branch" "$short files ($display_mode)" "$display_mode"
            record_result "$cis_id" "$short files" "PASS"
        else
            local count; count=$(echo "$non_compliant" | wc -l)
            printf "  %s %-30s  ${C_BRIGHT_RED}[FAIL]${C_RESET} %s file(s) non-compliant\n" \
                "$branch" "$short files ($display_mode)" "$count"
            log_debug "Non-compliant files in $path:\n$non_compliant"
            record_result "$cis_id" "$short files" "FAIL" "$count non-compliant"
            audit_fail=1
        fi
    done

    return "$audit_fail"
}

remediate_apt_files() {
    print_section_header "REMEDIATION" "APT File Access"
    local any_failure=false

    for entry in "${APT_FILE_CHECKS[@]}"; do
        local cis_id path find_mask remediate_mode missing_behavior
        IFS='|' read -r cis_id path find_mask remediate_mode missing_behavior <<< "$entry"

        if [[ ! -d "$path" ]] || [[ -z "$(ls -A "$path" 2>/dev/null)" ]]; then
            [[ "$missing_behavior" == "compliant" ]] && continue
            log_warn "[$cis_id] $path not found or empty, skipping."
            continue
        fi

        log_info "[$cis_id] Applying root:root / $remediate_mode to files in $path..."
        if find "$path" -type f -exec chown root:root {} + && \
           find "$path" -type f -exec chmod "$remediate_mode" {} +; then
            log_ok "  Files in $path fixed."
        else
            log_error "  Failed to fix files in $path."
            any_failure=true
        fi
    done

    [[ "$any_failure" == "true" ]] && return 1 || return 0
}

# ---------------------------------------------------------------------------
# Phased execution logic
# ---------------------------------------------------------------------------

_check_compliance() {
    local audit_func="$1"
    local msg_ok="$2"
    local msg_fail="$3"
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
    local audit_func="$1"
    local rem_func="$2"
    local check_msg="$3"
    local already_ok_msg="$4"

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

    _check_compliance audit_apt_sources_signed_by \
        "All APT sources use the Signed-By option." \
        "One or more APT sources are missing the Signed-By option." || global_status=1

    _check_compliance audit_apt_weak_deps \
        "Weak dependencies are disabled (Recommends=0, Suggests=0)." \
        "One or more weak dependency settings are non-compliant." || global_status=1

    _check_compliance audit_gpg_key_access \
        "All GPG key files have correct permissions (root:root 0644)." \
        "One or more GPG key files have incorrect permissions." || global_status=1

    _check_compliance audit_apt_directories \
        "All APT directories have correct ownership and permissions." \
        "One or more APT directories have incorrect access." || global_status=1

    _check_compliance audit_apt_files \
        "All APT configuration files have correct permissions." \
        "One or more APT files have incorrect permissions." || global_status=1

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

    _apply_remediation audit_apt_sources_signed_by remediate_apt_sources_signed_by \
        "Checking APT sources Signed-By..." \
        "APT sources already compliant." || any_failure=true

    _apply_remediation audit_apt_weak_deps remediate_apt_weak_deps \
        "Checking weak dependency settings..." \
        "Weak dependencies already disabled." || any_failure=true

    _apply_remediation audit_gpg_key_access remediate_gpg_key_access \
        "Checking GPG key file permissions..." \
        "GPG key file permissions already correct." || any_failure=true

    _apply_remediation audit_apt_directories remediate_apt_directories \
        "Checking APT directory permissions..." \
        "APT directory permissions already correct." || any_failure=true

    _apply_remediation audit_apt_files remediate_apt_files \
        "Checking APT file permissions..." \
        "APT file permissions already correct." || any_failure=true

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

    _check_compliance audit_apt_sources_signed_by \
        "APT sources are compliant." \
        "APT sources remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_apt_weak_deps \
        "Weak dependencies are disabled." \
        "Weak dependencies remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_gpg_key_access \
        "GPG key permissions are correct." \
        "GPG key permissions remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_apt_directories \
        "APT directory permissions are correct." \
        "APT directory permissions remediation FAILED." \
        "Verification" || verify_status=1

    _check_compliance audit_apt_files \
        "APT file permissions are correct." \
        "APT file permissions remediation FAILED." \
        "Verification" || verify_status=1

    print_summary_table

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. System is now compliant."
        return 0
    else
        log_warn "Auto-remediation finished with pending items. Manual review required."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# User interface & main
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section 1.2.1: Configure Package Repositories"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply APT hardening configurations."
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
    echo -e "\n${C_BOLD}--- CIS 1.2.1 APT Hardening — Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply fixes)" > /dev/tty
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
    print_section_header "CIS 1.2.1" "Configure Package Repositories"
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