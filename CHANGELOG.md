# Changelog

All notable changes to **Hard4U** are documented here.
This project adheres to [Semantic Versioning](https://semver.org/) and [Conventional Commits](https://www.conventionalcommits.org/).

---

## [v1.1.0] — 2026-04-02

### ✨ Features

- Add `CHANGELOG.md` — dedicated changelog file, removed from README

### 📖 Documentation

- Update README — replace changelog section with a link to `CHANGELOG.md`
- Update version to `v1.1.0`

---

## [v1.0.7] — 2026-04-02

### ⚙️ CI/CD

- Remove `paths` filter from `pull_request` trigger on all workflows to run checks on all PRs regardless of modified files

---

## [v1.0.6] — 2026-04-02

### 📖 Documentation

- Add `CODE_OF_CONDUCT.md` using Contributor Covenant v2.1 ([#15](https://github.com/N1-gHT/Hard4U/pull/15))
- Fix asterisk list style → dash in `CODE_OF_CONDUCT.md` ([#16](https://github.com/N1-gHT/Hard4U/pull/16))
- Fix bare URLs in `CODE_OF_CONDUCT.md`
- Fix dead and redirecting links in `CODE_OF_CONDUCT.md`

### ⚙️ CI/CD

- Exclude `contributor-covenant.org/faq` from dead link checker

---

## [v1.0.5] — 2026-04-02

### ⚙️ CI/CD

- Fix path triggers on all workflows — add `.github/**` and `.gitignore` to `push` paths
- Add `workflow_dispatch` trigger to `markdown.yml`
- Update README to reflect `v1.0.2`

---

## [v1.0.4] — 2026-04-02

### 🐛 Bug Fixes

- Fix broken code block syntax in Project Architecture section of README
- Fix GitHub Alerts syntax (`[!WARNING]`, `[!NOTE]`, `[!TIP]`)
- Remove `Shellcheck.yml` redundant workflow

### ⚙️ CI/CD

- Update README syntax and fix version to `v1.0.2`

---

## [v1.0.3] — 2026-04-02

### 🐛 Bug Fixes

- Resolve merge conflicts between `develop` and `main`
- Clean README conflict markers
- Update version to `v1.0.2`

---

## [v1.0.2] — 2026-04-02

### ✨ Features

- Initial stable release of all 29 CIS hardening modules
- Add `install.sh` one-liner installer script

### ⚙️ CI/CD

- Add GitHub Actions workflows: `markdown.yml`, `shellcheck.yml`, `test-audit.yml`, `release.yml`
- Add `.github/` configuration files: `CODEOWNERS`, `markdownlint.json`, issue templates, PR template

---

## [v1.0.1] — 2026-04-01

### ✨ Features

- Initial release of **Hard4U**
- Add `Hardening_Controller.sh` master orchestration script
- Add all 29 CIS Benchmark hardening modules for Debian 13
- Add `--audit`, `--remediation`, `--auto`, `--help` CLI flags for all modules
- Add interactive menu mode

### 📖 Documentation

- Add `README.md` with full project documentation
- Add `LICENSE` (GPLv3)
- Add `CONTRIBUTING.md`
- Add `SECURITY.md`
- Add `docs/CIS_Debian13.pdf` reference document