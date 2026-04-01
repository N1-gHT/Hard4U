#!/usr/bin/env bash

# =============================================================================
# install.sh — Installer & environment checker for Hard4U
# Detects whether the repo is already present; if not, downloads it first.
#
# Usage (one-liner) : curl -sL https://raw.githubusercontent.com/N1-gHT/Hard4U/main/install.sh | sudo bash
# Usage (local)     : sudo ./install.sh
# Override dir      : sudo INSTALL_DIR=/custom/path ./install.sh
#
# Exit  : 0 = all checks passed | 1 = one or more checks failed
# =============================================================================

set -uo pipefail

# =============================================================================
# COLORS — isatty-aware (declared early for use in all sections)
# =============================================================================
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BRIGHT_RED='\033[1;31m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
else
    C_RESET='' C_GREEN='' C_YELLOW='' C_BRIGHT_RED='' C_BLUE='' C_CYAN='' C_BOLD=''
fi
readonly C_RESET C_GREEN C_YELLOW C_BRIGHT_RED C_BLUE C_CYAN C_BOLD

# =============================================================================
# OUTPUT HELPERS
# =============================================================================
_ok()      { printf '%b  [OK]%b      %s\n'   "$C_GREEN"      "$C_RESET" "$*"; }
_fail()    { printf '%b  [FAIL]%b    %s\n'   "$C_BRIGHT_RED" "$C_RESET" "$*"; }
_warn()    { printf '%b  [WARN]%b    %s\n'   "$C_YELLOW"     "$C_RESET" "$*"; }
_info()    { printf '%b  [INFO]%b    %s\n'   "$C_BLUE"       "$C_RESET" "$*"; }
_section() { printf '\n%b── %s%b\n'          "$C_BOLD"       "$*" "$C_RESET"; }

# =============================================================================
# GLOBAL STATE
# =============================================================================
_ERRORS=0
_INSTALLED=()

_fail_count() { _ERRORS=$(( _ERRORS + 1 )); }

# =============================================================================
# ROOT CHECK
# =============================================================================
if [[ "$(id -u)" -ne 0 ]]; then
    printf '%b[CRITICAL] This script must be run as root (sudo).%b\n' \
        "${C_BRIGHT_RED}${C_BOLD}" "${C_RESET}" >&2
    exit 1
fi

# =============================================================================
# RUN MODE DETECTION
# =============================================================================
if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    _RUN_MODE="local"
    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _RUN_MODE="piped"
    BASE_DIR="${INSTALL_DIR:-/opt/Hard4U}"
fi
readonly _RUN_MODE BASE_DIR

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly REPO_URL="https://github.com/N1-gHT/Hard4U.git"
readonly TARBALL_URL="https://github.com/N1-gHT/Hard4U/archive/refs/heads/main.tar.gz"

readonly CONTROLLER_NAME="Hardening_Controller.sh"
readonly CONTROLLER_PATH="${BASE_DIR}/${CONTROLLER_NAME}"
readonly MODULES_DIR="${BASE_DIR}/modules"

# =============================================================================
# DEPENDENCIES  (data-driven — add entries here to extend checks)
# Format: "command:apt-package:human-label"
# =============================================================================
readonly DEPS=(
    "git:git:git (version control)"
    "jq:jq:jq (JSON processor)"
)

# =============================================================================
# HEADER
# =============================================================================
printf '\n%b=============================================%b\n' "$C_BOLD" "$C_RESET"
printf '%b  Hard4U — install.sh%b\n'                         "$C_BOLD" "$C_RESET"
printf '%b=============================================%b\n'  "$C_BOLD" "$C_RESET"
printf '  Mode           : %s\n' "${_RUN_MODE}"
printf '  Base dir       : %s\n' "${BASE_DIR}"
printf '  Modules dir    : %s\n' "${MODULES_DIR}"
printf '  Run by         : %s\n\n' "${SUDO_USER:-root}"

# =============================================================================
# SECTION 1 — SYSTEM DEPENDENCIES
# =============================================================================
_section "System dependencies"

_check_dep() {
    local cmd="$1" pkg="$2" label="$3"

    if command -v "$cmd" &>/dev/null; then
        _ok "${label}  →  $(command -v "$cmd")"
        return 0
    fi

    _warn "${label}  →  not found — installing ${pkg}…"

    if ! command -v apt-get &>/dev/null; then
        _fail "apt-get not found — cannot install ${pkg} automatically"
        _fail_count
        return 1
    fi

    apt-get update -qq 2>/dev/null
    if apt-get install -y "$pkg" &>/dev/null; then
        _ok "${label}  →  installed successfully ($(command -v "$cmd"))"
        _INSTALLED+=("$pkg")
    else
        _fail "${label}  →  installation of ${pkg} failed"
        _fail_count
        return 1
    fi
}

for dep in "${DEPS[@]}"; do
    IFS=':' read -r cmd pkg label <<< "$dep"
    _check_dep "$cmd" "$pkg" "$label"
done

# =============================================================================
# SECTION 2 — DOWNLOAD (only if repo not already present)
# =============================================================================
_repo_present() {
    [[ -f "${CONTROLLER_PATH}" && -d "${MODULES_DIR}" ]]
}

if _repo_present; then
    _section "Repository"
    _ok "Already present at: ${BASE_DIR} — skipping download"
else
    _section "Downloading Hard4U"

    if [[ -d "${BASE_DIR}" && -n "$(ls -A "${BASE_DIR}" 2>/dev/null)" ]]; then
        _warn "Target directory ${BASE_DIR} exists but is incomplete — proceeding"
    fi

    mkdir -p "${BASE_DIR}"

    _downloaded=false

    if command -v git &>/dev/null; then
        _info "Cloning repository via git into ${BASE_DIR}…"
        if git clone --depth=1 "${REPO_URL}" "${BASE_DIR}" 2>/dev/null; then
            _ok "Repository cloned successfully (git)"
            _downloaded=true
        else
            _warn "git clone failed — trying curl fallback…"
        fi
    fi

    if [[ "$_downloaded" == false ]] && command -v curl &>/dev/null; then
        _info "Downloading tarball via curl…"
        if curl -sL "${TARBALL_URL}" | tar -xz --strip-components=1 -C "${BASE_DIR}"; then
            _ok "Repository downloaded successfully (curl)"
            _downloaded=true
        else
            _warn "curl download failed — trying wget fallback…"
        fi
    fi

    if [[ "$_downloaded" == false ]] && command -v wget &>/dev/null; then
        _info "Downloading tarball via wget…"
        if wget -qO- "${TARBALL_URL}" | tar -xz --strip-components=1 -C "${BASE_DIR}"; then
            _ok "Repository downloaded successfully (wget)"
            _downloaded=true
        else
            _fail "wget download failed"
        fi
    fi

    if [[ "$_downloaded" == false ]]; then
        _fail "No download method available (git / curl / wget) — cannot continue"
        printf '\n%b%b  ✗ Download failed. Install git or curl and retry.%b\n\n' \
            "$C_BRIGHT_RED" "$C_BOLD" "$C_RESET"
        exit 1
    fi

    # Verify download integrity
    if ! _repo_present; then
        _fail "Download completed but expected files are missing"
        _fail_count
    fi
fi

# =============================================================================
# SECTION 3 — RUNTIME ENVIRONMENT
# =============================================================================
_section "Runtime environment"

bash_major="${BASH_VERSINFO[0]}"
if [[ "$bash_major" -ge 4 ]]; then
    _ok "bash ${BASH_VERSION}  (>= 4.x required)"
else
    _fail "bash ${BASH_VERSION}  — version 4 or higher required"
    _fail_count
fi

if command -v systemctl &>/dev/null; then
    _ok "systemctl  →  $(command -v systemctl)"
else
    _warn "systemctl not found — exclusive group detection will not work"
fi

# =============================================================================
# SECTION 4 — CONTROLLER FILE
# =============================================================================
_section "Controller"

if [[ -f "${CONTROLLER_PATH}" ]]; then
    _ok "Found: ${CONTROLLER_NAME}"
    if [[ -x "${CONTROLLER_PATH}" ]]; then
        _ok "Executable: ${CONTROLLER_NAME}"
    else
        _warn "${CONTROLLER_NAME} is not executable — applying chmod +x"
        chmod +x "${CONTROLLER_PATH}"
        if [[ -x "${CONTROLLER_PATH}" ]]; then
            _ok "Fixed: ${CONTROLLER_NAME} is now executable"
        else
            _fail "Could not make ${CONTROLLER_NAME} executable"
            _fail_count
        fi
    fi
else
    _fail "Not found: ${CONTROLLER_PATH}"
    _fail_count
fi

# =============================================================================
# SECTION 5 — MODULES DIRECTORY
# =============================================================================
_section "Modules directory"

if [[ -d "${MODULES_DIR}" ]]; then
    _ok "Directory exists: ${MODULES_DIR}"
else
    _fail "Directory not found: ${MODULES_DIR}"
    _fail_count
fi

if [[ -r "${MODULES_DIR}" ]]; then
    _ok "Directory is readable"
else
    _fail "Directory is not readable: ${MODULES_DIR}"
    _fail_count
fi

# =============================================================================
# SECTION 6 — MODULE INVENTORY
# =============================================================================
_section "Module inventory"

mapfile -t _MODULES < <(
    find "${MODULES_DIR}" -maxdepth 1 -name 'Hardening_[0-9]*.sh' \
        ! -name '*Controller*' -print \
    | while IFS= read -r f; do
        mod_base="$(basename "$f")"
        mod_num="${mod_base#Hardening_}"
        mod_num="${mod_num%%-*}"
        printf '%05d %s\n' "${mod_num}" "$f"
      done \
    | sort -n \
    | cut -d' ' -f2-
)

if [[ "${#_MODULES[@]}" -eq 0 ]]; then
    _warn "No Hardening_XX-*.sh modules found in: ${MODULES_DIR}"
else
    _info "${#_MODULES[@]} module(s) detected:"
    printf '\n'

    fixed=0
    for mod in "${_MODULES[@]}"; do
        mod_name="$(basename "$mod")"
        if [[ -x "$mod" ]]; then
            printf '    %b%-45s%b  %b[executable]%b\n' \
                "$C_CYAN" "$mod_name" "$C_RESET" "$C_GREEN" "$C_RESET"
        else
            printf '    %b%-45s%b  %b[not executable — fixing]%b\n' \
                "$C_CYAN" "$mod_name" "$C_RESET" "$C_YELLOW" "$C_RESET"
            chmod +x "$mod"
            fixed=$(( fixed + 1 ))
        fi
    done

    printf '\n'
    [[ "$fixed" -gt 0 ]] && _info "chmod +x applied to ${fixed} module(s)"
fi

# =============================================================================
# FINAL REPORT
# =============================================================================
printf '\n%b─────────────────────────────────────────────%b\n' "$C_BOLD" "$C_RESET"

if [[ "${#_INSTALLED[@]}" -gt 0 ]]; then
    _info "Packages installed during this run: ${_INSTALLED[*]}"
fi

if [[ "$_ERRORS" -eq 0 ]]; then
    printf '\n%b%b  ✓ All checks passed. Ready to run:%b\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
    printf '    sudo %s/%s --audit\n\n' "${BASE_DIR}" "${CONTROLLER_NAME}"
    exit 0
else
    printf '\n%b%b  ✗ %d check(s) failed. Review the output above.%b\n\n' \
        "$C_BRIGHT_RED" "$C_BOLD" "$_ERRORS" "$C_RESET"
    exit 1
fi