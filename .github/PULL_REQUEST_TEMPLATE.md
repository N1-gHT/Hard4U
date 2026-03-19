## 🔗 Related Issue

Closes #<!-- Issue number, e.g. Closes #42 -->

---

## 📋 Type of Change

<!-- Check all that apply -->

- [ ] 🐛 Bug fix
- [ ] 🧩 New module
- [ ] 📖 Documentation
- [ ] 🔨 Refactoring
- [ ] ⚙️ CI/CD
- [ ] 💥 Breaking change *(existing functionality is affected — describe below)*

---

## 📝 Description

### Problem / Motivation
<!-- What problem does this PR solve? Why is this change needed? -->

### Solution
<!-- What did you change and how does it solve the problem? -->

---

## ✅ Checklist

<!-- All boxes must be checked before requesting a review. -->

- [ ] ShellCheck passes with no warnings or errors (`shellcheck modules/*.sh`)
- [ ] Module tested in `--audit` mode on a Debian 13 VM
- [ ] Module tested in `--remediation` mode on a Debian 13 VM
- [ ] README / documentation updated if needed
- [ ] Commits follow the [Conventional Commits](https://www.conventionalcommits.org/) format

---

## 🖥️ ShellCheck Output

<!-- Paste the full output of: shellcheck modules/<your_module>.sh -->
<!-- Expected: no warnings, no errors -->

```
$ shellcheck modules/<your_module>.sh

```

---

## 🖥️ Terminal Output

<details>
<summary>Audit mode output (<code>--audit</code>)</summary>

```
<!-- Paste the full terminal output of your module in --audit mode -->
```

</details>

<details>
<summary>Remediation mode output (<code>--remediation</code>)</summary>

```
<!-- Paste the full terminal output of your module in --remediation mode -->
```

</details>

---

## 📝 Notes for Reviewer

<!-- Anything specific the reviewer should pay attention to?
     Edge cases, known limitations, decisions you made and why, etc.
     Delete this section if not needed. -->