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
|------|-------------|
| 🐛 **Bug fix** | Found something broken? Fix it and open a PR |
| 🧩 **New module** | Implement a missing CIS section (check the [Roadmap](README.md#️-roadmap--future-developments)) |
| 📖 **Documentation** | Improve the README, fix typos, clarify instructions |
| 🧪 **Testing** | Test existing modules on a Debian 13 system and report your findings |
| 💡 **Feature request** | Have an idea? Open an Issue to discuss it |

> 💡 Look for Issues tagged [`good first issue`](https://github.com/N1-gHT/Hard4U/issues?q=label%3A%22good+first+issue%22) if you're just getting started.

---

## Before You Start

- **Check existing Issues and PRs** — someone may already be working on it
- **Open an Issue first** for significant changes (new modules, breaking changes) — this avoids wasted effort
- For small fixes (typos, minor bugs), you can go straight to a PR

---

## Development Environment

### Requirements

| Tool | Purpose | Install |
|------|---------|---------|
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
|------|--------|---------|
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

```
<type>: <short description>

[optional body]
```

| Type | When to use |
|------|-------------|
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

Every new module must follow the structure of existing modules to ensure consistency. Here is the expected skeleton:

```bash
#!/usr/bin/env bash
# ==============================================================================
# Hard4U — CIS Benchmark Hardening for Debian 13
# Module : <Module Name>
# CIS    : Section X.x — <Section Title>
# ==============================================================================

set -euo pipefail

# --- Global Variables ---------------------------------------------------------
readonly SOME_VAR="value"

# --- Helper Functions ---------------------------------------------------------
log_info()  { echo "[INFO]  $*"; }
log_ok()    { echo "[OK]    $*"; }
log_warn()  { echo "[WARN]  $*"; }
log_fail()  { echo "[FAIL]  $*"; }

# --- Compliance Checks --------------------------------------------------------
check_compliance() {
    # Read-only checks — no system changes here
}

# --- Remediation --------------------------------------------------------------
apply_remediation() {
    # Apply fixes to non-compliant settings
}

# --- Phase Runners ------------------------------------------------------------
run_phase_audit() {
    echo "========== <CIS Section Title> =========="
    check_compliance
}

run_phase_remediation() {
    apply_remediation
}

run_phase_auto() {
    run_phase_audit
    apply_remediation
    run_phase_audit
}

# --- Entry Point --------------------------------------------------------------
case "${1:-}" in
    --audit)       run_phase_audit ;;
    --remediation) run_phase_remediation ;;
    --auto)        run_phase_auto ;;
    --help|-h)     echo "Usage: $0 [--audit|--remediation|--auto|--help]" ;;
    "")            interactive_menu ;;
    *)             echo "Unknown option: $1"; exit 1 ;;
esac
```

> Before writing a new module, check the existing ones (e.g. `2_privilege.sh`) for reference on logging patterns and variable conventions.

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
