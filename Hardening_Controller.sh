#!/usr/bin/env bash

# =============================================================================
# CIS Debian 13 v1.0 — Master Hardening Controller
# Orchestrates hardening sub-scripts with audit/remediation/auto modes.
# Generates terminal summary, log file, JSON and HTML reports.
#
# Requirements : bash >= 4.x, jq
# Usage        : sudo ./Hardening_Controller.sh [--audit|--remediation|--auto]
# =============================================================================

set -uo pipefail

# =============================================================================
# COLORS — disabled automatically when not a terminal (pipe / redirect)
# =============================================================================
_setup_colors() {
    if [[ -t 1 ]]; then
        C_RESET='\033[0m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_BRIGHT_RED='\033[1;31m'
        C_BOLD='\033[1m'
    else
        C_RESET='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BRIGHT_RED='' C_BOLD=''
    fi
    readonly C_RESET C_GREEN C_YELLOW C_BLUE C_BRIGHT_RED C_BOLD C_CYAN
}
_setup_colors

# =============================================================================
# PATHS
# =============================================================================
CONTROLLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONTROLLER_DIR
readonly MODULES_DIR="${CONTROLLER_DIR}/modules"

TIMESTAMP="$(date '+%Y-%m-%d_%Hh%M')"
readonly TIMESTAMP

readonly REPORT_DIR="${CONTROLLER_DIR}/reports/${TIMESTAMP}"
readonly LOG_FILE="${REPORT_DIR}/hardening_${TIMESTAMP}.log"
readonly JSON_FILE="${REPORT_DIR}/hardening_${TIMESTAMP}.json"
readonly HTML_FILE="${REPORT_DIR}/hardening_${TIMESTAMP}.html"

# =============================================================================
# LOGGING
# All log_* functions write to terminal + log file.
# log_critical also writes to log file before exiting.
# =============================================================================
log_info()     { local m="[INFO] $*";     echo -e "${C_BLUE}${m}${C_RESET}";                     echo "${m}" >> "${LOG_FILE}"; }
log_ok()       { local m="[OK] $*";       echo -e "${C_GREEN}${m}${C_RESET}";                    echo "${m}" >> "${LOG_FILE}"; }
log_warn()     { local m="[WARN] $*";     echo -e "${C_YELLOW}${m}${C_RESET}" >&2;               echo "${m}" >> "${LOG_FILE}"; }
log_error()    { local m="[ERROR] $*";    echo -e "${C_BRIGHT_RED}${m}${C_RESET}" >&2;           echo "${m}" >> "${LOG_FILE}"; }
log_critical() { local m="[CRITICAL] $*"; echo -e "${C_BRIGHT_RED}${C_BOLD}${m}${C_RESET}" >&2; echo "${m}" >> "${LOG_FILE}" 2>/dev/null; exit 1; }

print_section_header() { echo -e "\n${C_BOLD}========== ${1}: ${2} ==========${C_RESET}"; }

# =============================================================================
# ROOT CHECK
# =============================================================================
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${C_BRIGHT_RED}${C_BOLD}[CRITICAL] This script must be run as root.${C_RESET}" >&2
    exit 1
fi

# =============================================================================
# REAL USER DETECTION
# Identifies the human operator who invoked sudo.
# SUDO_USER is set automatically by sudo; falls back to root if run directly.
# =============================================================================
REAL_USER="${SUDO_USER:-root}"
readonly REAL_USER

# =============================================================================
# MODULE AUTODISCOVERY
# Finds every Hardening_*.sh in the same directory, excluding this controller.
# =============================================================================
_discover_subscripts() {
    local self
    self="$(realpath "${BASH_SOURCE[0]}")"

    mapfile -t SUB_SCRIPTS < <(
        find "${MODULES_DIR}" -maxdepth 1 -name 'Hardening_[0-9]*.sh' -print \
        | while IFS= read -r f; do
            local abs
            abs="$(realpath "$f")"
            [[ "$abs" == "$self"      ]] && continue
            [[ "$abs" == *Controller* ]] && continue
            local base num
            base="$(basename "$f")"
            num="${base#Hardening_}"
            num="${num%%-*}"
            printf '%05d %s\n' "${num}" "$f"
          done \
        | sort -n \
        | cut -d' ' -f2-
    )
    readonly SUB_SCRIPTS
}
_discover_subscripts

# =============================================================================
# SETUP REPORT DIRECTORY & LOG HEADER
# Must be called before any log_* that writes to LOG_FILE.
# =============================================================================
setup_reports() {
    local mode="$1"
    mkdir -p "${REPORT_DIR}"
    {
        echo "=================================================="
        echo " CIS Debian 13 v1.0 — Hardening Report"
        printf " Host     : %s\n" "$(hostname)"
        printf " Mode     : %s\n" "${mode^^}"
        printf " User     : %s\n" "${REAL_USER}"
        printf " Generated: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================================="
        echo ""
    } > "${LOG_FILE}"
    log_info "Report directory: ${REPORT_DIR}"
    log_info "Modules discovered: ${#SUB_SCRIPTS[@]}"
}

# =============================================================================
# EXCLUSIVE MODULE GROUPS  (data-driven — edit here, no logic changes needed)
# =============================================================================
readonly EXCLUSIVE_GROUPS=(
    "timesync:chrony:Hardening_Chrony.sh:systemd-timesyncd:Hardening_Systemd_Timesyncd.sh"
    "logging:rsyslog:Hardening_Rsyslog.sh:systemd-journald:Hardening_Journald.sh"
)

declare -a _SKIP_NAMES=()
declare -a _SKIP_REASONS=()

# =============================================================================
# RESULT STORAGE — parallel arrays (Bash 4 compatible, no declare -A)
# =============================================================================
declare -a SCRIPT_NAMES=()
declare -a SCRIPT_STATUSES=()
declare -a SCRIPT_EXIT_CODES=()
declare -a SCRIPT_PASS_COUNTS=()
declare -a SCRIPT_WARN_COUNTS=()
declare -a SCRIPT_FAIL_COUNTS=()
declare -a SCRIPT_CHECKS=()
declare -a SCRIPT_SKIP_REASONS=()

_G_PASS=0; _G_FAIL=0; _G_ERROR=0; _G_SKIPPED=0

# =============================================================================
# ANSI STRIPPER
# =============================================================================
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# =============================================================================
# PARSER — box-drawing table → structured check records
#
# Matches lines of the form:
#   │ 7.2.1  │  description text         │ PASS   │
#
# Outputs one line per matched check:
#   STATUS|CIS_ID|DESCRIPTION
# =============================================================================
parse_module_checks() {
    local raw="$1"
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*'│'[[:space:]]*([0-9]+(\.[0-9]+)+)[[:space:]]*'│'[[:space:]]*([^│]+[^│[:space:]])[[:space:]]*'│'[[:space:]]*(PASS|FAIL|WARN|ERROR)[[:space:]]*'│' ]]; then
            local cis_id desc status
            desc="${BASH_REMATCH[3]}"
            desc="${desc%"${desc##*[![:space:]]}"}"
            cis_id="${BASH_REMATCH[1]}"
            status="${BASH_REMATCH[4]}"
            printf '%s|%s|%s\n' "$status" "$cis_id" "$desc"
        fi
    done <<< "$raw"
}

# =============================================================================
# HELPERS
# =============================================================================

_count_status() {
    local checks="$1" target="$2"
    printf '%s\n' "$checks" | grep -c "^${target}|" || true
}

_module_status() {
    local exit_code="$1" checks="$2"
    if [[ "$exit_code" -ne 0 ]]; then
        echo "ERROR"
        return
    fi
    local bad
    bad=$(printf '%s\n' "$checks" | grep -cE "^(FAIL|WARN|ERROR)\|" || true)
    [[ "$bad" -gt 0 ]] && echo "FAIL" || echo "PASS"
}

_store_module() {
    local name="$1" exit_code="$2" checks="$3"
    local status pass warn fail
    status="$(_module_status "$exit_code" "$checks")"
    pass="$(_count_status "$checks" "PASS")"
    warn="$(_count_status "$checks" "WARN")"
    fail="$(_count_status "$checks" "FAIL")"

    SCRIPT_NAMES+=("$name")
    SCRIPT_STATUSES+=("$status")
    SCRIPT_EXIT_CODES+=("$exit_code")
    SCRIPT_PASS_COUNTS+=("$pass")
    SCRIPT_WARN_COUNTS+=("$warn")
    SCRIPT_FAIL_COUNTS+=("$fail")
    SCRIPT_CHECKS+=("$checks")
    SCRIPT_SKIP_REASONS+=("")
}

# =============================================================================
# EXCLUSIVE GROUP RESOLUTION
# Reads EXCLUSIVE_GROUPS, queries systemctl, builds _SKIP_NAMES/_SKIP_REASONS.
# Call once before run_all_subscripts.
# =============================================================================
_build_skip_list() {
    local entry group svc_a script_a svc_b script_b
    for entry in "${EXCLUSIVE_GROUPS[@]+"${EXCLUSIVE_GROUPS[@]}"}"; do
        IFS=':' read -r group svc_a script_a svc_b script_b <<< "$entry"

        local active_a=false active_b=false
        systemctl is-active --quiet "$svc_a" 2>/dev/null && active_a=true
        systemctl is-active --quiet "$svc_b" 2>/dev/null && active_b=true

        if [[ "$active_a" == true && "$active_b" == false ]]; then
            _SKIP_NAMES+=("$script_b")
            _SKIP_REASONS+=("excluded — ${svc_a} is active (group: ${group})")
            log_info "Group [${group}]: ${svc_a} active → running ${script_a}, skipping ${script_b}"

        elif [[ "$active_b" == true && "$active_a" == false ]]; then
            _SKIP_NAMES+=("$script_a")
            _SKIP_REASONS+=("excluded — ${svc_b} is active (group: ${group})")
            log_info "Group [${group}]: ${svc_b} active → running ${script_b}, skipping ${script_a}"

        elif [[ "$active_a" == true && "$active_b" == true ]]; then
            _SKIP_NAMES+=("$script_b")
            _SKIP_REASONS+=("excluded — both services active, ${svc_a} has priority (group: ${group})")
            log_warn "Group [${group}]: both ${svc_a} and ${svc_b} active — ${svc_a} has priority"

        else
            log_warn "Group [${group}]: neither ${svc_a} nor ${svc_b} is active — running both scripts"
        fi
    done
}

_is_skipped() {
    local name="$1"
    local i
    for (( i=0; i<${#_SKIP_NAMES[@]}; i++ )); do
        if [[ "${_SKIP_NAMES[$i]}" == "$name" ]]; then
            _skip_reason="${_SKIP_REASONS[$i]}"
            return 0
        fi
    done
    return 1
}

_store_skipped_module() {
    local name="$1" reason="$2"
    SCRIPT_NAMES+=("$name")
    SCRIPT_STATUSES+=("SKIPPED")
    SCRIPT_EXIT_CODES+=(0)
    SCRIPT_PASS_COUNTS+=(0)
    SCRIPT_WARN_COUNTS+=(0)
    SCRIPT_FAIL_COUNTS+=(0)
    SCRIPT_CHECKS+=("")
    SCRIPT_SKIP_REASONS+=("$reason")
}

_compute_global_stats() {
    _G_PASS=0; _G_FAIL=0; _G_ERROR=0; _G_SKIPPED=0
    local s
    for s in "${SCRIPT_STATUSES[@]+"${SCRIPT_STATUSES[@]}"}"; do
        case "$s" in
            PASS)    _G_PASS=$(( _G_PASS + 1 ))       ;;
            FAIL)    _G_FAIL=$(( _G_FAIL + 1 ))       ;;
            ERROR)   _G_ERROR=$(( _G_ERROR + 1 ))     ;;
            SKIPPED) _G_SKIPPED=$(( _G_SKIPPED + 1 )) ;;
        esac
    done
}

# =============================================================================
# RUN SINGLE SCRIPT
# =============================================================================
run_single_script() {
    local script_path="$1" mode="$2"
    local script_name exit_code=0
    script_name="$(basename "$script_path")"

    print_section_header "Running" "${script_name} [${mode}]"
    printf '[%s] --- %s --%s ---\n' "$(date '+%H:%M:%S')" "$script_name" "$mode" >> "${LOG_FILE}"

    if [[ ! -f "$script_path" ]]; then
        log_warn "Script not found: ${script_path} — SKIPPING"
        _store_module "$script_name" 1 ""
        return
    fi
    if [[ ! -x "$script_path" ]]; then
        log_warn "Script not executable: ${script_path} — applying chmod +x"
        chmod +x "$script_path"
    fi

    local tmp
    tmp="$(mktemp /tmp/hardening_XXXXXX)"

    "${script_path}" "--${mode}" 2>&1 | tee "$tmp" || true
    exit_code="${PIPESTATUS[0]}"

    local clean checks
    clean="$(strip_ansi < "$tmp")"
    rm -f "$tmp"

    printf '\n%s\n\n' "$clean" >> "${LOG_FILE}"

    checks="$(parse_module_checks "$clean")"
    _store_module "$script_name" "$exit_code" "$checks"

    local idx=$(( ${#SCRIPT_NAMES[@]} - 1 ))
    local status="${SCRIPT_STATUSES[$idx]}"
    local p="${SCRIPT_PASS_COUNTS[$idx]}"
    local w="${SCRIPT_WARN_COUNTS[$idx]}"
    local f="${SCRIPT_FAIL_COUNTS[$idx]}"

    case "$status" in
        PASS)  log_ok    "${script_name}: PASS  (PASS=${p})" ;;
        FAIL)  log_warn  "${script_name}: FAIL  (PASS=${p} | WARN=${w} | FAIL=${f})" ;;
        ERROR) log_error "${script_name}: ERROR (exit_code=${exit_code})" ;;
    esac
}

# =============================================================================
# RUN ALL SCRIPTS
# Returns exit code 1 if any sub-script crashed (exit != 0).
# =============================================================================
run_all_subscripts() {
    local mode="$1"
    local total="${#SUB_SCRIPTS[@]}"
    local has_crash=0

    _build_skip_list

    print_section_header "${mode^^}" "Starting execution of ${total} modules"

    local script _skip_reason
    for script in "${SUB_SCRIPTS[@]+"${SUB_SCRIPTS[@]}"}"; do
        local script_name
        script_name="$(basename "$script")"
        _skip_reason=""

        if _is_skipped "$script_name"; then
            log_info "SKIPPING ${script_name} — ${_skip_reason}"
            _store_skipped_module "$script_name" "$_skip_reason"
            continue
        fi

        run_single_script "$script" "$mode"
        [[ "${SCRIPT_EXIT_CODES[-1]}" -ne 0 ]] && has_crash=1
    done

    _compute_global_stats

    print_summary
    generate_json  "$mode" 2>/dev/null
    generate_html  "$mode" 2>/dev/null

    echo ""
    log_info "All reports saved in: ${REPORT_DIR}"
    log_info "  Log  : ${LOG_FILE}"
    log_info "  JSON : ${JSON_FILE}"
    log_info "  HTML : ${HTML_FILE}"

    if [[ "${REAL_USER}" != "root" ]]; then
        chown -R "${REAL_USER}:${REAL_USER}" "${REPORT_DIR}"
        log_info "Report ownership transferred to: ${REAL_USER}"
    fi

    return "$has_crash"
}

# =============================================================================
# TERMINAL SUMMARY TABLE
# Relies on _G_PASS / _G_FAIL / _G_ERROR set by _compute_global_stats().
# =============================================================================
print_summary() {
    local sep="+--------------------------------------+--------+-------+-------+-------+"
    local hdr="| Script                               | Status |  PASS | WARN  | FAIL  |"

    { echo ""; echo "$sep"; echo "$hdr"; echo "$sep"; } | tee -a "${LOG_FILE}"

    local i
    for (( i=0; i<${#SCRIPT_NAMES[@]}; i++ )); do
        local name="${SCRIPT_NAMES[$i]}"
        local status="${SCRIPT_STATUSES[$i]}"
        local p="${SCRIPT_PASS_COUNTS[$i]}"
        local w="${SCRIPT_WARN_COUNTS[$i]}"
        local f="${SCRIPT_FAIL_COUNTS[$i]}"
        local color

        case "$status" in
            PASS)    color="$C_GREEN"      ;;
            FAIL)    color="$C_YELLOW"     ;;
            ERROR)   color="$C_BRIGHT_RED" ;;
            SKIPPED) color="$C_CYAN"       ;;
            *)       color="$C_RESET"      ;;
        esac

        local line
        if [[ "$status" == "SKIPPED" ]]; then
            local reason="${SCRIPT_SKIP_REASONS[$i]:-}"
            line="$(printf '| %-36s | %-7s | %-19s |' \
                "${name:0:36}" "$status" "${reason:0:19}")"
        else
            line="$(printf '| %-36s | %-6s | %5d | %5d | %5d |' \
                "${name:0:36}" "$status" "$p" "$w" "$f")"
        fi

        echo -e "${color}${line}${C_RESET}"
        echo "$line" >> "${LOG_FILE}"
    done

    {
        echo "$sep"
        echo ""
        printf '  Modules: PASS=%-3d  FAIL=%-3d  ERROR=%-3d\n' \
            "$_G_PASS" "$_G_FAIL" "$_G_ERROR"
        echo ""
    } | tee -a "${LOG_FILE}"

    if [[ "$_G_FAIL" -eq 0 && "$_G_ERROR" -eq 0 ]]; then
        echo -e "${C_GREEN}${C_BOLD}  [OK] SYSTEM IS FULLY COMPLIANT${C_RESET}"
        echo "  [OK] SYSTEM IS FULLY COMPLIANT" >> "${LOG_FILE}"
    else
        echo -e "${C_YELLOW}${C_BOLD}  [WARN] SYSTEM IS NOT FULLY COMPLIANT  (FAIL=${_G_FAIL} / ERROR=${_G_ERROR})${C_RESET}"
        echo "  [WARN] SYSTEM IS NOT FULLY COMPLIANT  (FAIL=${_G_FAIL} / ERROR=${_G_ERROR})" >> "${LOG_FILE}"
    fi
    echo ""
}

# =============================================================================
# JSON REPORT — generated with jq (no manual escaping)
# =============================================================================
generate_json() {
    local mode="$1"
    local total="${#SCRIPT_NAMES[@]}"
    local compliant
    [[ "$_G_FAIL" -eq 0 && "$_G_ERROR" -eq 0 ]] && compliant=true || compliant=false

    local modules_json="["
    local i
    for (( i=0; i<total; i++ )); do
        local name="${SCRIPT_NAMES[$i]}"
        local status="${SCRIPT_STATUSES[$i]}"
        local p="${SCRIPT_PASS_COUNTS[$i]}"
        local w="${SCRIPT_WARN_COUNTS[$i]}"
        local f="${SCRIPT_FAIL_COUNTS[$i]}"
        local checks="${SCRIPT_CHECKS[$i]}"

        local checks_json
        if [[ -n "$checks" ]]; then
            checks_json="$(
                printf '%s\n' "$checks" | \
                jq -Rn '[inputs | split("|") | {status: .[0], cis_id: .[1], description: .[2]}]'
            )"
        else
            checks_json="[]"
        fi

        local mod_json
        mod_json="$(jq -n \
            --arg  name     "$name"         \
            --arg  status   "$status"       \
            --argjson pass  "$p"            \
            --argjson warn  "$w"            \
            --argjson fail  "$f"            \
            --argjson checks "$checks_json" \
            '{
                name:   $name,
                status: $status,
                counts: { pass: $pass, warn: $warn, fail: $fail },
                checks: $checks
            }'
        )"

        [[ $i -gt 0 ]] && modules_json+=","
        modules_json+="$mod_json"
    done
    modules_json+="]"

    jq -n \
        --arg  generated_at  "$(date '+%Y-%m-%dT%H:%M:%S')" \
        --arg  hostname      "$(hostname)"                   \
        --arg  mode          "$mode"                         \
        --arg  benchmark     "CIS Debian 13 v1.0"            \
        --argjson total      "$total"                        \
        --argjson pass       "$_G_PASS"                      \
        --argjson fail       "$_G_FAIL"                      \
        --argjson error      "$_G_ERROR"                     \
        --argjson skipped    "$_G_SKIPPED"                   \
        --argjson compliant  "$compliant"                    \
        --argjson modules    "$modules_json"                 \
        '{
            report: {
                generated_at:  $generated_at,
                hostname:      $hostname,
                mode:          $mode,
                cis_benchmark: $benchmark,
                summary: {
                    total:     $total,
                    pass:      $pass,
                    fail:      $fail,
                    error:     $error,
                    skipped:   $skipped,
                    compliant: $compliant
                },
                modules: $modules
            }
        }' > "${JSON_FILE}"
}

# =============================================================================
# HTML REPORT
# Shares SCRIPT_CHECKS[] with generate_json — no second parse of raw output.
# =============================================================================
generate_html() {
    local mode="$1"
    local total="${#SCRIPT_NAMES[@]}"
    local total_pass=0 total_warn=0 total_fail=0 i

    for (( i=0; i<total; i++ )); do
        total_pass=$(( total_pass + SCRIPT_PASS_COUNTS[i] ))
        total_warn=$(( total_warn + SCRIPT_WARN_COUNTS[i] ))
        total_fail=$(( total_fail + SCRIPT_FAIL_COUNTS[i] ))
    done

    local compliant_label compliant_class
    if [[ "$_G_FAIL" -eq 0 && "$_G_ERROR" -eq 0 ]]; then
        compliant_label="COMPLIANT";     compliant_class="compliant"
    else
        compliant_label="NON-COMPLIANT"; compliant_class="non-compliant"
    fi

    {
        cat << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CIS Debian 13 — Hardening Report</title>
<style>
  :root {
    --pass:       #1a7a1a;
    --fail:       #b85c00;
    --error-col:  #a00000;
    --ok-bg:      #e8f5e9;
    --warn-bg:    #fff8e1;
    --err-bg:     #fdecea;
    --header-bg:  #1a2636;
    --accent:     #2a6496;
    --section-bg: #f4f6f9;
    --border:     #d0d7e2;
    --font:       'Segoe UI', Arial, sans-serif;
    --mono:       'Courier New', Consolas, monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: var(--font); background: #eef1f6; color: #222; }

  header { background: var(--header-bg); color: #fff; padding: 22px 40px; display: flex; align-items: center; justify-content: space-between; border-bottom: 4px solid var(--accent); }
  .cis-badge { display: inline-block; background: var(--accent); color: #fff; font-size: 0.72em; padding: 3px 10px; border-radius: 3px; font-weight: 700; letter-spacing: 1px; margin-bottom: 6px; }
  header h1  { font-size: 1.45em; font-weight: 700; }
  header .meta { font-size: 0.82em; opacity: 0.65; margin-top: 5px; }

  .global-badge { font-size: 1.1em; font-weight: 700; padding: 10px 24px; border-radius: 6px; letter-spacing: 1px; border: 2px solid; }
  .global-badge.compliant     { background: #e8f5e9;      color: var(--pass);      border-color: var(--pass); }
  .global-badge.non-compliant { background: var(--err-bg); color: var(--error-col); border-color: var(--error-col); }

  .container  { max-width: 1100px; margin: 28px auto; padding: 0 20px; }
  .stats-row  { display: flex; gap: 16px; margin-bottom: 28px; flex-wrap: wrap; }
  .stat-card  { flex: 1; min-width: 130px; background: #fff; border-radius: 8px; border: 1px solid var(--border); padding: 18px 20px; text-align: center; }
  .stat-card .val { font-size: 2.2em; font-weight: 700; }
  .stat-card .lbl { font-size: 0.75em; text-transform: uppercase; color: #666; margin-top: 4px; letter-spacing: 1px; }
  .stat-card.pass    .val { color: var(--pass); }
  .stat-card.fail    .val { color: var(--fail); }
  .stat-card.error   .val { color: var(--error-col); }
  .stat-card.skipped .val { color: #0077aa; }
  .stat-card.total   .val { color: var(--accent); }

  .checks-bar { background: #fff; border: 1px solid var(--border); border-radius: 8px; padding: 14px 24px; margin-bottom: 28px; font-size: 0.88em; color: #444; display: flex; gap: 24px; align-items: center; }
  .c-pass { color: var(--pass);      font-weight: 600; }
  .c-warn { color: var(--fail);      font-weight: 600; }
  .c-fail { color: var(--error-col); font-weight: 600; }

  h2.section-title { font-size: 1.05em; font-weight: 700; color: var(--header-bg); margin-bottom: 14px; border-left: 4px solid var(--accent); padding-left: 10px; text-transform: uppercase; letter-spacing: 0.5px; }

  .module-card   { background: #fff; border-radius: 8px; border: 1px solid var(--border); margin-bottom: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
  .module-header { display: flex; align-items: center; justify-content: space-between; padding: 13px 20px; cursor: pointer; user-select: none; transition: background 0.15s; }
  .module-header:hover { background: var(--section-bg); }
  .module-left   { display: flex; align-items: center; gap: 12px; }
  .module-right  { display: flex; align-items: center; gap: 16px; font-size: 0.82em; color: #666; }
  .module-name   { font-weight: 600; font-size: 0.95em; font-family: var(--mono); }

  .badge       { padding: 3px 11px; border-radius: 4px; font-weight: 700; font-size: 0.8em; letter-spacing: 0.5px; }
  .badge.PASS    { background: var(--ok-bg);    color: var(--pass); }
  .badge.FAIL    { background: var(--warn-bg);  color: var(--fail); }
  .badge.ERROR   { background: var(--err-bg);   color: var(--error-col); }
  .badge.SKIPPED { background: #e8f4fd;          color: #0077aa; }

  .count-pills span { margin-right: 10px; }
  .toggle-btn { font-size: 0.78em; background: var(--section-bg); border: 1px solid var(--border); border-radius: 4px; padding: 3px 10px; cursor: pointer; color: #555; font-family: var(--font); }

  .module-body      { display: none; border-top: 1px solid var(--border); }
  .module-body.open { display: block; }

  .checks-table { width: 100%; border-collapse: collapse; font-size: 0.84em; font-family: var(--mono); }
  .checks-table thead th { padding: 8px 18px; text-align: left; background: var(--section-bg); font-size: 0.78em; text-transform: uppercase; letter-spacing: 0.5px; color: #555; border-bottom: 1px solid var(--border); }
  .checks-table th:first-child  { width: 70px;  text-align: center; }
  .checks-table th:nth-child(2) { width: 90px; }
  .checks-table tr  { border-bottom: 1px solid #f0f2f5; }
  .checks-table td  { padding: 7px 18px; vertical-align: top; }
  .checks-table td:first-child  { font-weight: 700; text-align: center; white-space: nowrap; }
  .checks-table td:nth-child(2) { color: #777; white-space: nowrap; }

  tr.pass-row { background: #fafffe; } tr.pass-row td:first-child { color: var(--pass); }
  tr.warn-row { background: #fffdf6; } tr.warn-row td:first-child { color: var(--fail); }
  tr.fail-row { background: #fffafa; } tr.fail-row td:first-child { color: var(--error-col); }

  footer { text-align: center; padding: 20px; color: #aaa; font-size: 0.78em; margin-top: 10px; }
</style>
</head>
<body>
HTMLEOF

        cat << DYNEOF
<header>
  <div>
    <div class="cis-badge">CIS Debian 13 v1.0</div>
    <h1>Hardening Report</h1>
    <div class="meta">
      Mode: <strong>${mode^^}</strong>
      &nbsp;&bull;&nbsp; Host: <strong>$(hostname)</strong>
      &nbsp;&bull;&nbsp; User: <strong>${REAL_USER}</strong>
      &nbsp;&bull;&nbsp; Generated: <strong>$(date '+%Y-%m-%d %H:%M:%S')</strong>
    </div>
  </div>
  <div class="global-badge ${compliant_class}">${compliant_label}</div>
</header>

<div class="container">

  <div class="stats-row">
    <div class="stat-card pass">    <div class="val">${_G_PASS}</div>    <div class="lbl">Modules Pass</div>    </div>
    <div class="stat-card fail">    <div class="val">${_G_FAIL}</div>    <div class="lbl">Modules Fail</div>    </div>
    <div class="stat-card error">   <div class="val">${_G_ERROR}</div>   <div class="lbl">Modules Error</div>   </div>
    <div class="stat-card skipped"> <div class="val">${_G_SKIPPED}</div> <div class="lbl">Modules Skipped</div> </div>
    <div class="stat-card total">   <div class="val">${total}</div>      <div class="lbl">Modules Total</div>   </div>
  </div>

  <div class="checks-bar">
    <span>Individual checks &mdash;</span>
    <span class="c-pass"><strong>${total_pass}</strong> PASS</span>
    <span class="c-warn"><strong>${total_warn}</strong> WARN</span>
    <span class="c-fail"><strong>${total_fail}</strong> FAIL</span>
  </div>

  <h2 class="section-title">Module Results</h2>
DYNEOF

        for (( i=0; i<total; i++ )); do
            local name="${SCRIPT_NAMES[$i]}"
            local status="${SCRIPT_STATUSES[$i]}"
            local p="${SCRIPT_PASS_COUNTS[$i]}"
            local w="${SCRIPT_WARN_COUNTS[$i]}"
            local f="${SCRIPT_FAIL_COUNTS[$i]}"
            local checks="${SCRIPT_CHECKS[$i]}"

            cat << MODEOF
  <div class="module-card">
    <div class="module-header" onclick="toggleModule('mod-${i}', this)">
      <div class="module-left">
        <span class="badge ${status}">${status}</span>
        <span class="module-name">${name}</span>
      </div>
      <div class="module-right">
        <span class="count-pills">
          <span class="c-pass">PASS: ${p}</span>
          <span class="c-warn">WARN: ${w}</span>
          <span class="c-fail">FAIL: ${f}</span>
        </span>
        <button class="toggle-btn" id="btn-mod-${i}">[+] Details</button>
      </div>
    </div>
    <div class="module-body" id="mod-${i}">
      <table class="checks-table">
        <thead><tr><th>Status</th><th>CIS ID</th><th>Description</th></tr></thead>
        <tbody>
MODEOF

            while IFS='|' read -r chk_status cis_id desc; do
                [[ -z "$chk_status" ]] && continue
                local row_class
                case "$chk_status" in
                    PASS)        row_class="pass-row" ;;
                    WARN)        row_class="warn-row" ;;
                    FAIL|ERROR)  row_class="fail-row" ;;
                    *)           row_class="" ;;
                esac
                desc="${desc//&/&amp;}"
                desc="${desc//</&lt;}"
                desc="${desc//>/&gt;}"
                printf '          <tr class="%s"><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
                    "$row_class" "$chk_status" "$cis_id" "$desc"
            done <<< "$checks"

            echo "        </tbody>"
            echo "      </table>"
            echo "    </div>"
            echo "  </div>"
        done

        cat << 'FOOTEREOF'

</div><!-- /container -->

<footer>CIS Debian 13 v1.0 &mdash; Hardening Master Controller &mdash; All rights reserved</footer>

<script>
function toggleModule(id, header) {
  var body = document.getElementById(id);
  var btn  = document.getElementById('btn-' + id);
  var isOpen = body.classList.contains('open');
  body.classList.toggle('open', !isOpen);
  btn.textContent = isOpen ? '[+] Details' : '[-] Hide';
}
</script>
</body>
</html>
FOOTEREOF

    } > "${HTML_FILE}"
}

# =============================================================================
# USER INTERFACE & MAIN
# =============================================================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --audit        Run audit on all modules (read-only, no changes).
  --remediation  Apply hardening configuration on all modules.
  --auto         Audit, apply, and verify all modules.
  --help, -h     Show this help message.

If no option is given, an interactive menu is displayed.
EOF
}

show_interactive_menu() {
    {
        echo ""
        echo -e "${C_BOLD}==========================================${C_RESET}"
        echo -e "${C_BOLD}  CIS Debian 13 v1.0 — Hardening Master  ${C_RESET}"
        echo -e "${C_BOLD}==========================================${C_RESET}"
        echo ""
        printf '  1) Audit All       (Check all modules, no changes)\n'
        printf '  2) Remediate All   (Apply all configurations)\n'
        printf '  3) Auto All        (Audit, Fix, and Verify everything)\n'
        printf '  4) Exit\n'
        echo ""
    } > /dev/tty

    local choice
    read -rp "Enter your choice [1-4]: " choice < /dev/tty
    echo "" > /dev/tty

    case "$choice" in
        1) echo "audit"       ;;
        2) echo "remediation" ;;
        3) echo "auto"        ;;
        4) echo "exit"        ;;
        *) echo "invalid"     ;;
    esac
}

main() {
    local mode=""

    if [[ "$#" -gt 0 ]]; then
        case "$1" in
            --audit)       mode="audit"       ;;
            --remediation) mode="remediation" ;;
            --auto)        mode="auto"        ;;
            --help|-h)     usage; exit 0      ;;
            *)             log_error "Unknown argument: $1"; usage; exit 1 ;;
        esac
    else
        mode="$(show_interactive_menu)"
    fi

    case "$mode" in
        audit|remediation|auto)
            setup_reports "$mode"
            run_all_subscripts "$mode"
            ;;
        exit)
            echo "Exiting."
            exit 0
            ;;
        invalid)
            echo -e "${C_BRIGHT_RED}${C_BOLD}[CRITICAL] Invalid selection.${C_RESET}" >&2
            exit 1
            ;;
    esac
}

main "$@"