<p align="center"> <img src="https://img.shields.io/badge/Debian-13-A81D33?style=flat-square&logo=debian&logoColor=white" alt="Debian 13"> <img src="https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white" alt="Bash"> <img src="https://img.shields.io/badge/Standard-CIS_Benchmark-00447C?style=flat-square" alt="CIS Benchmark"> <img src="https://img.shields.io/badge/Version-v0.1.0-orange?style=flat-square" alt="Version"> <img src="https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat-square" alt="License: GPL v3"> <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square" alt="PRs Welcome"> </p> <h1 align="center">Hard4U</h1> <p align="center"> <strong>Automated CIS Benchmark Hardening Scripts for Debian 13</strong><br> Audit, remediate and verify your system's security posture — automatically. </p> <p align="center"> <!-- Replace with your actual demo GIF once available --> <img src="https://placehold.co/860x440/1a1a2e/39d353?text=Hard4U+Demo+(GIF+coming+soon)" alt="Hard4U demo" width="860"> </p>

---

## ⚡ Quick Start

```bash
git clone https://github.com/N1-gHT/Hard4U.git && cd Hard4U
chmod +x Hardening_Controller.sh modules/*.sh
sudo ./Hardening_Controller.sh --audit        # Dry-run — no changes made
sudo ./Hardening_Controller.sh --auto         # Audit → Fix → Verify

```

> Not sure where to start? Run `--audit` first to get a full compliance report, then decide what to remediate.

---

## Table of Contents

- [⚡ Quick Start](#-quick-start)
- [⚠️ Important Disclaimer](#%EF%B8%8F-important-disclaimer)
- [📖 About the Project](#-about-the-project)
  - [Origin & Reference](#origin--reference)
  - [Objectives](#objectives)
- [✅ Prerequisites](#-prerequisites)
- [📦 Installation](#-installation)
  - [Quick Install (One-liner)](#quick-install-one-liner)
  - [Manual Installation](#manual-installation)
- [🚀 Usage](#-usage)
  - [Command-Line Options](#command-line-options)
  - [Interactive Mode](#interactive-mode)
  - [Configuration (Global Variables)](#configuration-global-variables)
- [🗂️ Project Architecture](#%EF%B8%8F-project-architecture)
- [📊 CIS Modules Coverage](#-cis-modules-coverage)
- [🗺️ Roadmap & Future Developments](#%EF%B8%8F-roadmap--future-developments)
- [📋 Changelog](#-changelog)
- [🤝 Contributing](#-contributing)
- [❓ FAQ](#-faq)
- [📚 References](#-references)
- [📄 License](#-license)
- [💬 Contact & Support](#-contact--support)

---

## ⚠️ Important Disclaimer

> [!WARNING] 
> This project provides a set of hardening scripts based on the **CIS Benchmark for Debian 13** published by the Center for Internet Security.
>
> These scripts are provided **"as is"**, without warranty of any kind, express or implied, including but not limited to warranties of fitness for a particular purpose or non-infringement.
>
> Running these scripts may significantly modify system configuration (services, access controls, network settings, authentication mechanisms, permissions, etc.) and may result in:
>
> - Loss of access (including SSH access)
> - Service disruption
> - Application incompatibilities
> - Performance impacts
>
> ### Before Using
>
> - Test thoroughly in a **lab or staging environment**.
> - Perform **full system backups** before execution.
> - Review and adapt the scripts to fit your specific environment and requirements.
>
> The author shall not be held liable for any damages, data loss, service interruption, or other issues arising from the use or misuse of these scripts. **Use at your own risk.**

---

## 📖 About the Project

### Origin & Reference

**Hard4U** was created to automate the tedious and complex process of securing a Linux operating system. The configurations and checks performed by these scripts strictly follow the guidelines established by the **[Center for Internet Security (CIS)](https://www.cisecurity.org/)** Benchmark for **Debian 13**.

> **Note:** Currently, the scripts apply hardening rules regardless of CIS Level 1 or Level 2 profiles — all rules are applied by default. Level-based selection is planned for a future release.

### Objectives

| Goal           | Description                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| **Audit**      | Quickly verify if your Debian 13 system complies with CIS recommendations — read-only, no changes made |
| **Remediate**  | Automatically fix non-compliant settings with a single command                                         |
| **Modularity** | Run checks on specific components or launch a full global audit via the controller                     |

---

## ✅ Prerequisites

|Requirement|Details|
|---|---|
|**OS**|Debian 13 (Trixie)|
|**Privileges**|Root access (`sudo` or native `root` user)|
|**Dependencies**|`bash`, `awk`, `grep` — pre-installed on Debian by default|

---

## 📦 Installation

### Quick Install (One-liner)

> [!NOTE] 
> The one-liner installer will be available once the initial stable release is published. Track progress on the [Roadmap](#%EF%B8%8F-roadmap--future-developments).

```bash
curl -sL https://raw.githubusercontent.com/N1-gHT/Hard4U/main/install.sh | sudo bash
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/N1-gHT/Hard4U.git

# Navigate to the project directory
cd Hard4U

# Make the scripts executable
chmod +x Hardening_Controller.sh modules/*.sh
```

---

## 🚀 Usage

Hard4U is highly flexible. Use the master **controller** to orchestrate all modules, or run **independent modules** one by one.

> [!TIP] 
> All modules are **idempotent** — running them multiple times on an already-hardened system is safe and will not cause unintended side effects. A re-run simply confirms compliance.

### Command-Line Options

Every script supports the following arguments for automated/CI execution:

|Flag|Description|
|---|---|
|`--audit`|Run compliance checks only — **no changes made** to the system|
|`--remediation`|Apply security configurations (fixes non-compliant items)|
|`--auto`|Full pipeline: Audit → Fix → Re-Audit to verify|
|`--help` / `-h`|Display the help message|

**Examples:**

```bash
# Run a dry-run audit on the GRUB module
sudo ./modules/Hardening_4-Bootloader.sh --audit

# Auto-remediate privilege escalation settings
sudo ./modules/Hardening_18-Sudo.sh --auto

# Run the full controller in auto mode
sudo ./Hardening_Controller.sh --auto
```

### Interactive Mode

Running a script without any arguments launches a user-friendly interactive menu:

```bash
sudo ./Hardening_Controller.sh
```

```text
========== CIS 5.4: User Accounts and Environment ==========

--- CIS 5.4 User Accounts -- Select Operation Mode ---

1) Audit Only       (Check compliance, no changes)
2) Remediation Only (Apply user accounts and environment hardening)
3) Auto             (Audit, fix if needed, then verify)
4) Exit

Enter your choice [1-4]:
```

Each module displays its own CIS section header, making it easy to identify which benchmark category is currently being processed.

### Configuration (Global Variables)

Before running the scripts, **review and adjust** the variables at the top of each module to match your environment. Each module contains a `# --- Global Variables ---` section.

**Privilege Escalation module (`Hardening_18-Sudo.sh`):**

```bash
readonly SUDO_PKG="sudo"
readonly SUDO_LDAP_PKG="sudo-ldap"
readonly SSSD_SUDO_PKG="libsss-sudo"
readonly SSSD_PKG="sssd"
readonly USE_SUDO_LDAP_LEGACY="${USE_SUDO_LDAP_LEGACY:-false}"
readonly USE_SUDO_LDAP_MODERN="${USE_SUDO_LDAP_MODERN:-false}"

readonly SUDOERS_DIR="/etc/sudoers.d"
readonly SUDOERS_CIS_FILE="${SUDOERS_DIR}/60-cis-hardening"
readonly SUDO_TIMESTAMP_TIMEOUT="15"

readonly PAM_SU_FILE="/etc/pam.d/su"
readonly SU_RESTRICT_GROUP="sugroup"
```

**Bootloader module (`Hardening_4-Bootloader.sh`):**

```bash
readonly GRUB_USER="root"
readonly GRUB_PASSWORD_FILE="/etc/grub.d/01_users"
readonly GRUB_LINUX_FILE="/etc/grub.d/10_linux"

readonly GRUB_CFG_PATH="/boot/grub/grub.cfg"
readonly GRUB_CFG_EXPECTED_MODE="0600"
readonly GRUB_CFG_EXPECTED_OWNER="root:root"

readonly -a GRUB_PASSWORD_PATTERNS=(
    "superuser definition|^set superusers"
    "password hash|^password_pbkdf2"
)
```

---

## 🗂️ Project Architecture

Hard4U uses a modular architecture to allow granular control over what gets audited or modified.

```text
Hard4U/
├── Hardening_Controller.sh              # Master script — orchestrates all modules
├── README.md                 # Project documentation
├── docs/
│   └── CIS_Debian13.pdf      # CIS Benchmark reference (included for convenience)
└── modules/                  # Independent, self-contained hardening scripts
    ├── Hardening_1-Kernel_FS.sh         # Filesystem & kernel parameters  (CIS 1.x)
    ├── Hardening_2-APT.sh               # Package management              (CIS 1.x)
    ├── Hardening_3-AppArmor.sh          # Mandatory access control        (CIS 1.x)
    ├── Hardening_4-Bootloader.sh        # GRUB & boot settings            (CIS 1.x)
    ├── Hardening_5-Additional_Process.sh# Additional process hardening    (CIS 1.x)
    ├── Hardening_6-Banners.sh           # Warning banners                 (CIS 1.7)
    ├── Hardening_7-GDM.sh               # GNOME display manager           (CIS 1.x)
    ├── Hardening_8-Server_Service.sh    # Server services                 (CIS 2.x)
    ├── Hardening_9-Client_Services.sh   # Client services                 (CIS 2.x)
    ├── Hardening_10-Systemd_Timesyncd.sh# Time synchronization (systemd)  (CIS 2.x)
    ├── Hardening_11-Chrony.sh           # Time synchronization (chrony)   (CIS 2.x)
    ├── Hardening_12-Job_Scheduler.sh    # Cron & at job scheduling        (CIS 6.x)
    ├── Hardening_13-Network_1.sh        # Network stack hardening pt.1    (CIS 3.x)
    ├── Hardening_14-Network_2.sh        # Network stack hardening pt.2    (CIS 3.x)
    ├── Hardening_15-Firewall.sh         # Firewall (nftables/iptables)    (CIS 3.x)
    ├── Hardening_16-SSH.sh              # SSH server hardening            (CIS 5.x)
    ├── Hardening_17-SSH_Conf.sh         # SSH configuration               (CIS 5.x)
    ├── Hardening_18-Sudo.sh             # Sudo & su restrictions          (CIS 5.x)
    ├── Hardening_19-PAM_1.sh            # PAM configuration pt.1         (CIS 5.x)
    ├── Hardening_20-PAM_2.sh            # PAM configuration pt.2         (CIS 5.x)
    ├── Hardening_21-Accounts.sh         # User accounts & environment     (CIS 5.x)
    ├── Hardening_22-Journald.sh         # Journald logging                (CIS 4.x)
    ├── Hardening_23-Rsyslog.sh          # Rsyslog configuration           (CIS 4.x)
    ├── Hardening_24-Auditd_1.sh         # Auditd rules pt.1               (CIS 4.x)
    ├── Hardening_25-Auditd_2.sh         # Auditd rules pt.2               (CIS 4.x)
    ├── Hardening_26-Auditd_3.sh         # Auditd rules pt.3               (CIS 4.x)
    ├── Hardening_27-AIDE.sh             # File integrity (AIDE)           (CIS 6.x)
    ├── Hardening_28-System_Access.sh    # System access controls          (CIS 6.x)
    └── Hardening_29-User_Settings.sh    # User environment settings       (CIS 6.x)
    └── ...                   # Future modules
```

Each module is **fully self-contained** and implements three core functions:

- `check_compliance` — reads current system state and reports findings
- `apply_remediation` — applies the required changes
- Phased entrypoints: `run_phase_audit`, `run_phase_remediation`, `run_phase_auto`

---

## 📊 CIS Modules Coverage

|#|Module|Status|CIS Section|Level|
|---|---|:-:|---|:-:|
|1|Filesystem & Partitions|🚧 In Progress|CIS 1.x|L1/L2|
|2|Bootloader (GRUB)|✅ Available|CIS 1.x|L1|
|3|Privilege Escalation (sudo/su)|✅ Available|CIS 5.x|L1|
|4|Network Configuration|✅ Available|CIS 3.x|L1|
|5|Logging & Auditing (auditd)|✅ Available|CIS 4.x|L2|
|6|Access Control (PAM, SSH)|✅ Available|CIS 5.x|L1/L2|
|7|System Maintenance|✅ Available|CIS 6.x|L1|

> **Legend:** ✅ Available  |  🚧 In Progress  |  🔜 Planned

---

## 🗺️ Roadmap & Future Developments

- [ ] **Filesystem & Partitions** — Configure FS partitions per CIS recommendations
- [ ] **CIS Level Selection** — Strictly choose between Level 1 (Server/Workstation) and Level 2 profiles
- [ ] **Multi-Distribution Support** — Expand to RedHat / AlmaLinux / RockyLinux
- [ ] **Rollback Feature** — Restore system state to pre-remediation snapshot
- [ ] **One-liner Installer** — Stable `curl | bash` installer

---

## 📋 Changelog

All notable changes to this project are documented here. This project adheres to [Semantic Versioning](https://semver.org/).

### [v1.0.2] — 2026-04-01 _(Initial Release)_

#### Added

- `Hardening_Controller.sh` — master orchestration script with interactive menu
- `Hardening_1-Kernel_FS.sh` — filesystem & kernel parameter hardening
- `Hardening_2-APT.sh` — APT package manager hardening
- `Hardening_3-AppArmor.sh` — AppArmor mandatory access control
- `Hardening_4-Bootloader.sh` — GRUB bootloader hardening
- `Hardening_5-Additional_Process.sh` — additional process hardening
- `Hardening_6-Banners.sh` — warning banners configuration
- `Hardening_7-GDM.sh` — GNOME display manager hardening
- `Hardening_8-Server_Service.sh` — server services hardening
- `Hardening_9-Client_Services.sh` — client services hardening
- `Hardening_10-Systemd_Timesyncd.sh` — systemd time synchronization
- `Hardening_11-Chrony.sh` — chrony time synchronizatgit reset --hard origin/developion
- `Hardening_12-Job_Scheduler.sh` — cron & at job scheduling controls
- `Hardening_13-Network_1.sh` — network stack hardening (part 1)
- `Hardening_14-Network_2.sh` — network stack hardening (part 2)
- `Hardening_15-Firewall.sh` — firewall configuration (nftables/iptables)
- `Hardening_16-SSH.sh` — SSH server hardening
- `Hardening_17-SSH_Conf.sh` — SSH daemon configuration
- `Hardening_18-Sudo.sh` — sudo & su privilege escalation controls
- `Hardening_19-PAM_1.sh` — PAM configuration (part 1)
- `Hardening_20-PAM_2.sh` — PAM configuration (part 2)
- `Hardening_21-Accounts.sh` — user accounts & environment hardening
- `Hardening_22-Journald.sh` — journald logging configuration
- `Hardening_23-Rsyslog.sh` — rsyslog configuration
- `Hardening_24-Auditd_1.sh` — auditd rules (part 1)
- `Hardening_25-Auditd_2.sh` — auditd rules (part 2)
- `Hardening_26-Auditd_3.sh` — auditd rules (part 3)
- `Hardening_27-AIDE.sh` — file integrity monitoring (AIDE)
- `Hardening_28-System_Access.sh` — system access controls
- `Hardening_29-User_Settings.sh` — user environment settings
- `--audit`, `--remediation`, `--auto`, `--help` CLI flags for all modules

---

## 🤝 Contributing

Contributions, issues, and feature requests are highly welcome!

1. **Fork** the project
2. Create your feature branch: `git checkout -b feature/AmazingFeature`
3. Commit your changes: `git commit -m 'feat: add AmazingFeature'`
4. Push to the branch: `git push origin feature/AmazingFeature`
5. Open a **Pull Request** on GitHub

Please open an **[Issue](https://github.com/N1-gHT/Hard4U/issues/new/choose)** first if you spot a bug or want to discuss a new feature before starting work.

---

## ❓ FAQ

<details> <summary><strong>Is it safe to run the scripts multiple times on an already-hardened system?</strong></summary>

Yes. All modules are designed to be **idempotent** — re-running a remediation on a system that is already compliant will detect that settings are already in place and make no unnecessary changes. Running `--audit` after `--remediation` is the recommended way to confirm everything is applied correctly.

</details> <details> <summary><strong>Can I run Hard4U on Debian 12 (Bookworm) or other distributions?</strong></summary>

Hard4U is designed and tested specifically for **Debian 13 (Trixie)**. While some modules may partially work on Debian 12, compatibility is not guaranteed. Multi-distribution support (RedHat/AlmaLinux/RockyLinux) is on the roadmap.

</details> <details> <summary><strong>Will the audit mode change anything on my system?</strong></summary>

No. Running `--audit` is strictly **read-only**. It checks the current state of your system against CIS recommendations and reports findings without applying any changes.

</details> <details> <summary><strong>I lost SSH access after running a remediation. What do I do?</strong></summary>

This is a known risk when applying SSH hardening rules. You will need physical or console access to your machine to revert the SSH configuration. This is why testing in a **lab environment first** is strongly recommended. A rollback feature is planned for a future release.

</details> <details> <summary><strong>Does Hard4U support CIS Level 1 and Level 2 separately?</strong></summary>

Not yet — all rules are applied by default regardless of level. Granular Level 1 / Level 2 profile selection is on the [roadmap](#%EF%B8%8F-roadmap--future-developments).

</details> <details> <summary><strong>Can I run individual modules without the controller?</strong></summary>

Yes! Every module is fully self-contained and can be executed independently:

```bash
sudo ./modules/Hardening_1-Kernel_FS.sh --audit
```

</details>

---

## 📚 References

| Resource                                                                | Description                                                      |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 📄 [CIS Benchmark for Debian 13](./docs/CIS_Debian13.pdf)               | The full CIS Benchmark PDF included in this repository           |
| 🌐 [CIS Official Website](https://www.cisecurity.org/)                  | Center for Internet Security — source of the benchmark standards |
| 🌐 [CIS Benchmark Downloads](https://www.cisecurity.org/cis-benchmarks) | Download the latest official CIS Benchmarks                      |

> [!NOTE] 
> The CIS Benchmark PDF is included in this repository for reference convenience. It remains the intellectual property of the **Center for Internet Security**. Please refer to [CIS terms of use](https://www.cisecurity.org/terms-and-conditions-table-of-contents) for usage rights.

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](https://github.com/N1-gHT/Hard4U/blob/main/LICENSE) file for full details.

---

## 💬 Contact & Support

|Channel|Link|
|---|---|
|🐛 **GitHub Issues**|[Open an issue](https://github.com/N1-gHT/Hard4U/issues/new/choose)|
|💬 **Discord**|`n1h_`|
|📧 **Email**|[contact@n1ght.fr](mailto:contact@n1ght.fr)|
