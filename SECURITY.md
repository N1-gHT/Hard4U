# 🔒 Security Policy

Security is a top priority for this project, especially given its role in automating CIS Benchmark hardening for Debian 13. I am committed to maintaining a secure environment for all users and appreciate the community's help in identifying potential vulnerabilities.

---

## Supported Versions

Only the latest version on `main` is actively supported and receives security updates.

| Version | Supported |
| :-------- | :---------: |
| Latest (`main`) | ✅ |
| Older releases | ❌ |

---

## Reporting a Vulnerability

> [!CAUTION]
> **Please do NOT open a public GitHub Issue to report a security vulnerability.**
> Public disclosure before a fix is available puts all users at risk.

### Primary Channel — GitHub Security Advisories

The preferred way to report a vulnerability is via the **[GitHub Security Advisories](https://github.com/N1-gHT/Hard4U/security/advisories/new)** feature. This ensures your report remains **private** while I work on a fix.

### Fallback Channel — Email

If you are unable to use GitHub Advisories, you may contact me directly at **[security@n1ght.fr](mailto:security@n1ght.fr)**.

---

### What to Include in Your Report

To help me investigate and resolve the issue efficiently, please provide:

- **Description** — A clear and concise summary of the vulnerability
- **Affected component** — Which script or module is affected? (e.g. `2_privilege.sh`)
- **Steps to reproduce** — Detailed instructions, including commands or configuration used
- **Impact** — What is the potential risk or consequence for a system running Hard4U?
- **Version** — The specific version or commit you are using
- **Suggested fix** *(optional)* — Any patches or remediation ideas you may have

---

## Disclosure Policy

I follow a **Responsible Disclosure** process:

| Step | Timeframe |
| ------ | ----------- |
| Acknowledgement of your report | Within **1 week** |
| Status update (confirmed / investigating) | Within **2 weeks** |
| Fix & public advisory | Depends on severity and complexity |

As I maintain this project as a **solo developer**, resolution time may vary depending on the complexity of the issue. I am committed to addressing verified vulnerabilities as quickly as possible.

Once a fix is verified and released, a **security advisory** will be published on the repository to inform all users. Contributors who help identify and resolve security issues will be **formally credited** in the advisory and release notes, unless they prefer to remain anonymous.

---

## Scope

### In Scope

- Logic errors in remediation scripts that could weaken security instead of hardening it
- Privilege escalation risks introduced by the scripts themselves
- Incorrect or dangerous CIS rule implementations
- Hardcoded sensitive values (passwords, keys) accidentally left in scripts

### Out of Scope

- **Upstream Debian vulnerabilities** — Issues inherent to Debian packages themselves should be reported to the [Debian Security Team](https://www.debian.org/security/)
- **User configuration** — Issues resulting from custom modifications or misuse of the tool after execution
- **Theoretical vulnerabilities** — Reports must be demonstrably exploitable or present a clear, logical security flaw within the provided code; unproven theoretical risks will not be considered

---

## Disclaimer

This project is developed on a voluntary, open-source basis. While I strive to ensure the highest level of quality and security, please note that response times depend on my availability as a solo maintainer.

I deeply value the work of security researchers who help improve this tool. While there is no formal bug bounty program, all contributors who help identify and resolve security issues will be acknowledged and credited in the project's security history and release notes.

Thank you for helping make the community safer. 🛡️
