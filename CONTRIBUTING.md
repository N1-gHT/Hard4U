# 🤝 Contributing to Hard4U

First of all — **thank you for considering a contribution!** Every contribution matters, whether it's a typo fix, a new module, a bug report, or a feature idea. This project exists and improves because of people like you.

This guide will walk you through everything you need to know to contribute effectively.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Ways to Contribute](#ways-to-contribute)
- [Before You Start](#before-you-start)
- [Development Environment](#development-environment)
- [Branch & Commit Conventions](#branch--commit-conventions)
- [Module Structure](#module-structure)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting a Bug](#reporting-a-bug)
- [Proposing a Feature](#proposing-a-feature)

---

## Code of Conduct

This project is welcoming to everyone. Please be respectful and constructive in all interactions — in Issues, Pull Requests, and comments. Harassment or dismissive behaviour of any kind will not be tolerated.

---

## Ways to Contribute

Not sure where to start? Here are all the ways you can help:

| Type | Description |
| ------ | ------------- |
| 🐛 **Bug fix** | Found something broken? Fix it and open a PR |
| 🧩 **New module** | Implement a missing CIS section (check the [Roadmap](README.md#️-roadmap--future-developments)) |
| 📖 **Documentation** | Improve the README, fix typos, clarify instructions |
| 🧪 **Testing** | Test existing modules on a Debian 13 system and report your findings |
| 💡 **Feature request** | Have an idea? Open an Issue to discuss it |

> 💡 Look for Issues tagged [`good first issue`](https://github.com/N1-gHT/Hardening_OS/issues?q=label%3A%22good+first+issue%22) if you're just getting started.

---

## Before You Start

- **Check existing Issues and PRs** — someone may already be working on it
- **Open an Issue first** for significant changes (new modules, breaking changes) — this avoids wasted effort
- For small fixes (typos, minor bugs), you can go straight to a PR

---

## Development Environment

### Requirements

| Tool | Purpose | Install |
| ------ | --------- | --------- |
| **Debian 13** (VM recommended) | Test environment | [Download](https://www.debian.org/) |
| **ShellCheck** | Bash linter | `sudo apt install shellcheck` |
| **Git** | Version control | `sudo apt install git` |

### Setting Up ShellCheck

ShellCheck is **mandatory** before submitting any PR. It catches common Bash errors and enforces best practices.

```bash
# Install on Debian/Ubuntu
sudo apt install shellcheck

# Run against a single module
shellcheck modules/2_privilege.sh

# Run against all modules at once
shellcheck modules/*.sh
```

A clean ShellCheck output (no warnings, no errors) is required for all contributions.

### Testing in a VM

> [!WARNING]
> **Never test remediation scripts on your main system or production machines.**
> Always use a dedicated **Debian 13 VM** that you can snapshot and restore.

Recommended testing workflow:

1. Take a **snapshot** of your clean Debian 13 VM before running anything
2. Run the module in `--audit` mode first to check the baseline
3. Run in `--remediation` or `--auto` mode
4. Verify the results and check for regressions
5. Restore the snapshot between test runs

---

## Branch & Commit Conventions

### Branch Naming

| Type | Format | Example |
| ------ | -------- | --------- |
| New feature / module | `feature/<name>` | `feature/add-filesystem-module` |
| Bug fix | `fix/<name>` | `fix/ssh-remediation-crash` |
| Documentation | `docs/<name>` | `docs/update-contributing` |

All branches should be created from `develop`, not `main`.

```bash
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name
```

### Commit Messages — Conventional Commits

This project uses the **[Conventional Commits](https://www.conventionalcommits.org/)** format. This is required as it powers the automatic changelog generation.

```text
<type>: <short description>

[optional body]
```

| Type | When to use |
| ------ | ------------- |
| `feat:` | Adding a new feature or module |
| `fix:` | Fixing a bug |
| `docs:` | Documentation changes only |
| `test:` | Adding or updating tests |
| `chore:` | Maintenance (CI, dependencies, config) |
| `refactor:` | Code restructuring without behaviour change |

**Examples:**

```bash
feat: add filesystem partition hardening module
fix: grub password hash not applied on first run
docs: add VM testing instructions to CONTRIBUTING
chore: update shellcheck to latest version
```

---

## Module Structure

Every new module **must** follow the structure below to ensure consistency across the project. This skeleton reflects the actual architecture used in all existing modules.

> Before writing a new module, study an existing one (e.g. `2_privilege.sh`) to understand how the data-driven array and audit tree are used in practice.

```bash
#!/usr/bin/env bash

# CIS Benchmark Debian 13 - Section X.x: <Section Title>
#
# Sub-sections covered:
#   X.x.x.1 - <Description>   (Automated)
#   X.x.x.2 - <Description>   (Manual)
#   ...

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
# readonly MY_VAR="value"

# ---------------------------------------------------------------------------
# Data-driven array -- one entry per CIS check
# Format: "CIS_ID | audit_func | remediation_func | Description"
# ---------------------------------------------------------------------------
MY_CHECKS=(
    # "X.x.x.1 | _audit_check_1 | _rem_check_1 | Description of check 1"
    # "X.x.x.2 | _audit_check_2 | _rem_check_2 | Description of check 2"
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
# Tree & summary helpers -- do not modify, copy as-is from existing modules
# ---------------------------------------------------------------------------
_rep()        { local i; for (( i=0; i<$1; i++ )); do printf '%s' "$2"; done; }
_tree_label() { echo -e "\n  ${C_BOLD}$*${C_RESET}"; }

_audit_tree_row() {
    local cis_id="$1" desc="$2" branch="$3"
    shift 3
    local status=0
    "$@" || status=1
    printf "  %s %-46s  " "$branch" "$desc"
    if [[ "$status" -eq 0 ]]; then
        echo -e "${C_GREEN}[PASS]${C_RESET}"
        record_result "$cis_id" "$desc" "PASS"
    else
        echo -e "${C_BRIGHT_RED}[FAIL]${C_RESET}"
        record_result "$cis_id" "$desc" "FAIL"
    fi
    return "$status"
}

# ---------------------------------------------------------------------------
# Audit functions -- one per entry in MY_CHECKS
# Must return 0 (compliant) or 1 (non-compliant). No side effects.
# ---------------------------------------------------------------------------
_audit_check_1() {
    # Example: systemctl is-active --quiet some.service
    return 0
}

# ---------------------------------------------------------------------------
# Remediation functions -- one per entry in MY_CHECKS
# Applied only when the matching audit function returns 1.
# ---------------------------------------------------------------------------
_rem_check_1() {
    # Example: systemctl enable --now some.service
    :
}

# ---------------------------------------------------------------------------
# Shared audit tree renderer
# ---------------------------------------------------------------------------
_run_audit_checks() {
    local label="$1"
    local global_status=0

    _tree_label "$label"

    local total_rows="${#MY_CHECKS[@]}"
    local current_row=0
    local branch

    for entry in "${MY_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"; audit_func="${audit_func// /}"; rem_func="${rem_func// /}"
        (( ++current_row ))
        [[ $current_row -eq $total_rows ]] && branch="└─" || branch="├─"
        _audit_tree_row "$cis_id" "$desc" "$branch" "$audit_func" || global_status=1
    done

    print_summary_table
    return "$global_status"
}

# ---------------------------------------------------------------------------
# Phase runners
# ---------------------------------------------------------------------------
run_phase_audit() {
    print_section_header "MODE" "AUDIT ONLY"
    local global_status=0
    _run_audit_checks "Section X.x  (CIS X.x.x.1 - X.x.x.N)" || global_status=1
    [[ "$global_status" -eq 0 ]] \
        && log_ok  "Global Audit: SYSTEM IS COMPLIANT." \
        || log_warn "Global Audit: SYSTEM IS NOT COMPLIANT."
    return "$global_status"
}

run_phase_remediation() {
    print_section_header "MODE" "REMEDIATION ONLY"
    local any_failure=false

    for entry in "${MY_CHECKS[@]}"; do
        local cis_id audit_func rem_func desc
        IFS='|' read -r cis_id audit_func rem_func desc <<< "$entry"
        cis_id="${cis_id// /}"; audit_func="${audit_func// /}"; rem_func="${rem_func// /}"
        if ! "$audit_func"; then
            log_info "[${cis_id}] Remediating: ${desc}..."
            "$rem_func" || any_failure=true
        else
            log_ok "[${cis_id}] ${desc} -- already compliant."
        fi
    done

    [[ "$any_failure" == "true" ]] \
        && { log_error "Remediation completed with errors."; return 1; } \
        || { log_ok   "Remediation completed successfully."; return 0; }
}

run_phase_auto() {
    print_section_header "MODE" "AUTO (Audit + Fix + Verify)"

    if run_phase_audit; then
        log_ok "System is already compliant. No changes needed."
        return 0
    fi

    log_info "Non-compliant items found. Starting remediation..."
    local remediation_status=0
    run_phase_remediation || remediation_status=$?

    log_info "Verifying post-remediation compliance..."
    reset_results
    local verify_status=0
    _run_audit_checks "Post-Remediation Verification  (CIS X.x.x.1 - X.x.x.N)" \
        || verify_status=1

    if [[ "$remediation_status" -eq 0 && "$verify_status" -eq 0 ]]; then
        log_ok "Auto-remediation successful. System is now compliant."
    else
        log_warn "Auto-remediation finished with pending items. Manual review may be required."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Interactive menu & entry point
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CIS Benchmark Debian 13 - Section X.x: <Section Title>"
    echo ""
    echo "Options:"
    echo "  --audit        Run audit checks only (no changes)."
    echo "  --remediation  Apply hardening."
    echo "  --auto         Audit, apply fixes if needed, then verify."
    echo "  --help, -h     Show this help message."
    echo ""
    echo "Environment variables:"
    echo "  SCRIPT_DEBUG=true   Enable debug output on stderr."
    echo "  NO_COLOR=true       Disable ANSI color output."
}

show_interactive_menu() {
    echo -e "\n${C_BOLD}--- CIS X.x <Title> -- Select Operation Mode ---${C_RESET}" > /dev/tty
    echo "1) Audit Only       (Check compliance, no changes)" > /dev/tty
    echo "2) Remediation Only (Apply hardening)" > /dev/tty
    echo "3) Auto             (Audit, fix if needed, then verify)" > /dev/tty
    echo "4) Exit" > /dev/tty
    echo "" > /dev/tty
    local choice
    IFS= read -rp "Enter your choice [1-4]: " choice < /dev/tty
    case "$choice" in
        1) echo "audit" ;; 2) echo "remediation" ;;
        3) echo "auto"  ;; 4) echo "exit"        ;;
        *) echo "invalid" ;;
    esac
}

main() {
    print_section_header "CIS X.x" "<Section Title>"
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
        esac
    fi

    case "$mode" in
        audit)       run_phase_audit ;;
        remediation) run_phase_remediation ;;
        auto)        run_phase_auto ;;
    esac
}

main "$@"
```

---

## Submitting a Pull Request

1. **Fork** the repository and clone it locally
2. Create your branch from `develop` (see [Branch Naming](#branch--commit-conventions))
3. Make your changes
4. Run ShellCheck and fix all warnings: `shellcheck modules/*.sh`
5. Test your changes in a Debian 13 VM in both `--audit` and `--remediation` mode
6. Commit using Conventional Commits format
7. Push your branch and open a PR **targeting `develop`**

In your PR description, fill in the provided template completely — incomplete PRs may be closed.

---

## Reporting a Bug

Open an Issue using the **Bug Report** template and fill in all the fields. The more detail you provide, the faster the fix.

Please include:

- The module and flag used (e.g. `5_access_control.sh --remediation`)
- Your Debian 13 version (`cat /etc/os-release`)
- The exact error message or unexpected behaviour
- Steps to reproduce

---

## Proposing a Feature

Open an Issue using the **Feature Request** template. Describe:

- What problem does it solve?
- Which CIS section does it relate to?
- Any implementation ideas you already have

Large features will be discussed in the Issue before any code is written.

---

*Thank you again for your time and interest in Hard4U. Every contribution, big or small, makes this tool better for everyone.* 🛡️
