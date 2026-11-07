<h1 align="center">
  <img src="static/openness-logo.svg" alt="openness" width="300px">
  <br>
</h1>

<h4 align="center">Credentialed vulnerability scanning with evidence for every finding. An open source alternative to Nessus.</h4>

<p align="center">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-1f5fbf"></a>
<a href="https://github.com/s4e-io/openness-collector/releases"><img src="https://img.shields.io/github/v/release/s4e-io/openness-collector?label=collector"></a>
<a href="https://github.com/s4e-io/openness-resolver/releases"><img src="https://img.shields.io/github/v/release/s4e-io/openness-resolver?label=resolver"></a>
<a href="https://github.com/s4e-io/openness-app-mapper/releases"><img src="https://img.shields.io/github/v/release/s4e-io/openness-app-mapper?label=app-mapper"></a>
<a href="#-contributing"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen"></a>
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-install">Install</a> •
  <a href="#-usage">Usage</a> •
  <a href="#-projects">Projects</a> •
  <a href="#-evidence-first">Evidence first</a> •
  <a href="#-contributing">Contributing</a> •
  <a href="https://getopenness.com/openness/documentation">Documentation</a>
</p>

**openness** finds the vulnerabilities on your Linux and Windows servers by reading what is really installed, matching it against each vendor's own security data and comparing versions the way the vendor's package manager does. Every finding says what is affected, which rule applies, which version fixes it and which evidence it is based on.

> [!IMPORTANT]
> **Beta.** Interfaces, file formats and coverage may still change.

---

## ✨ Features

- **Credentialed and agentless.** The collector is copied to the host over SSH or WinRM, collects, and is removed. Nothing stays installed.
- **Vendor data, native comparators.** Ubuntu OVAL and USN, the Debian Security Tracker, Alpine secdb, Red Hat, Rocky, AlmaLinux, Amazon Linux, openSUSE, Microsoft MSRC, OSV for PyPI, with dpkg, rpm, apk and PEP 440 version rules.
- **Windows applications.** The [application catalog](https://github.com/s4e-io/openness-app-mapper) maps installed programs to NVD products, rebuilt from NVD every day.
- **Containers and network devices.** Packages inside running containers, and network devices over SNMPv3.
- **No false all-clear.** A host whose packages could not be read, or whose distribution has no data, is reported as a coverage gap, never as clean.
- **Machine-readable findings.** JSON with the reasons and evidence of every result, for people, pipelines and AI agents.
- **Works offline.** Vulnerability data and licenses can be loaded from files on air-gapped networks.

## 📥 Install

**openness Desktop** (recommended): the app with a web UI. It adds your servers, runs the scans and shows the findings and the fixes. The collector and the resolver are built in.

Windows, macOS and Linux (deb, rpm): [download](https://getopenness.com/openness/releases/latest) · [install guide](https://getopenness.com/openness/documentation)

**Command line tools** (collector and resolver), for automation and CI:

```sh
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/s4e-io/openness/dev/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/s4e-io/openness/dev/install.ps1 | iex
```

The installer verifies every binary against its release's `SHA256SUMS` and installs `openness-collector` and `openness-resolver` into `~/.local/bin` (Windows: `%LOCALAPPDATA%\Openness`). No root or Administrator rights are needed. `OPENNESS_COMPONENTS=collector` (or `resolver`) installs one, `OPENNESS_COLLECTOR_VERSION` / `OPENNESS_RESOLVER_VERSION` pin a release, `OPENNESS_INSTALL_DIR` picks the directory and `OPENNESS_DRY_RUN=1` shows the plan.

## 🚀 Usage

```sh
sudo openness-collector collect --output host.openness                      # on the host to assess
openness-resolver feed sync --for host.openness --data-dir ./openness-data   # the vendor data this host needs
openness-resolver resolve --input host.openness --output findings.json --data-dir ./openness-data
```

A finding in `findings.json`:

```json
{
  "cve_id": "CVE-2025-0411",
  "state": "vulnerable",
  "installed_version": "19.00",
  "fixed_version": "24.09",
  "confidence": "high",
  "reasons": ["7-Zip 19.00 is in an affected range of NVD cpe 7-zip:7-zip"]
}
```

Remote servers over SSH, Windows, containers, air-gapped networks and keeping the data fresh are covered in the [collector](https://github.com/s4e-io/openness-collector#usage) and [resolver](https://github.com/s4e-io/openness-resolver#usage) READMEs.

---

## 📦 Projects

```text
openness-collector  ──▶  evidence  ──▶  openness-resolver  ──▶  findings  ──▶  people, pipelines, AI agents
```

| Project | What it does |
|---|---|
| 🖥️ **openness Desktop** | The app: targets, scans, findings, reports, offline use. [Download](https://getopenness.com/openness/releases/latest) |
| 🔎 **[openness-collector](https://github.com/s4e-io/openness-collector)** | Collects evidence on Linux and Windows hosts: OS, packages, kernel, processes, libraries, containers, applications, updates, configuration. |
| 🧠 **[openness-resolver](https://github.com/s4e-io/openness-resolver)** | Turns evidence into findings with vendor advisories and native version comparison. Downloads the vendor data itself: no account, no API key. [Data sources](https://github.com/s4e-io/openness-resolver#data-sources) |
| 🗂️ **[openness-app-mapper](https://github.com/s4e-io/openness-app-mapper)** | The application catalog: Windows applications mapped to NVD products, with their CVEs. |

## 🔍 Evidence first

A scanner that says only

```text
CVE-XXXX-YYYY → HIGH → VULNERABLE
```

leaves you to guess why. openness answers, for every finding: **what is affected, where, why the rule applies, which vendor rule, which version fixes it, and which evidence shows it.**

```text
System evidence → exact package → vendor rule → fixed version → native comparison → finding
```

We prefer correct support for fewer platforms over broad coverage built on package-name guessing. What works today is listed in the [collector](https://github.com/s4e-io/openness-collector) and [resolver](https://github.com/s4e-io/openness-resolver) READMEs.

---

## 🤝 Contributing

Bug reports, test environments, wrong or missed findings, new platforms and new data sources are all welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md); the collector, the resolver and the application catalog have their own guides and issue forms.

- **Bugs and wrong findings:** open an issue in the project it belongs to.
- **Security vulnerabilities:** report them privately, see [SECURITY.md](SECURITY.md).
- **Ideas, research and datasets:** [Dr. Onur AKTAS](https://www.linkedin.com/in/dr-onur-aktas/), [onur@s4e.io](mailto:onur@s4e.io).

## 📜 License

This repository, [openness-collector](https://github.com/s4e-io/openness-collector) and [openness-resolver](https://github.com/s4e-io/openness-resolver) are licensed under the [Apache License, Version 2.0](LICENSE): use them for anything, including commercial use, and keep the LICENSE and NOTICE files with any copy you distribute. Vendor data the resolver downloads stays under its publishers' terms.

openness is developed and maintained by [S4E (Security For Everyone)](https://s4e.io).

## ⚖️ Disclaimer

openness is an independent open source project and is not affiliated with, endorsed by, or sponsored by Tenable. Nessus is a trademark of its respective owner. Scan only systems you own or are authorised to test.
