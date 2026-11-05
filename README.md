<h1 align="center">
  <img src="static/openness-logo.svg" alt="OpenNess Vulnerability Scanner" width="300px">
  <br>
  OpenNess Vulnerability Scanner
</h1>

<h4 align="center">A better open source alternative to Nessus, built for the age of autonomous cybersecurity.</h4>

<p align="center">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-1f5fbf"></a>
<a href="https://github.com/s4e-io/openness-collector/releases"><img src="https://img.shields.io/github/v/release/s4e-io/openness-collector?label=openness-collector"></a>
<a href="https://github.com/s4e-io/openness-resolver/releases"><img src="https://img.shields.io/github/v/release/s4e-io/openness-resolver?label=openness-resolver"></a>
<a href="#-lets-build-it-together"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen"></a>
</p>

<p align="center">
  <a href="#-projects">Projects</a> •
  <a href="#-install">Install</a> •
  <a href="#-quick-start">Quick start</a> •
  <a href="#-evidence-first">Evidence first</a> •
  <a href="#-built-for-autonomous-cybersecurity">Vision</a> •
  <a href="#-lets-build-it-together">Contribute</a> •
  <a href="https://s4e.io">S4E.io</a>
</p>

> **Planned by cybersecurity experts. Developed with AI models. Created for everyone.**

**OpenNess Vulnerability Scanner** is an open source vulnerability assessment and security evidence platform. It collects real system evidence, resolves vulnerabilities with the vendors' own security intelligence, and produces **explainable, verifiable, machine-readable findings**.

Our goal goes beyond vulnerability scanning: we want to create the **open security data layer that future AI agents need to observe, reason, remediate, act and verify safely.**

> [!IMPORTANT]
> **Beta.** OpenNess Vulnerability Scanner is in beta. Interfaces, file formats and coverage may still change.

---

## 📦 Projects

```text
   openness-collector  ──▶  structured evidence  ──▶  openness-resolver  ──▶  explainable findings  ──▶  AI / human action
```

| Project | What it does | Read more |
|---|---|---|
| 🔎 **[openness-collector](https://github.com/s4e-io/openness-collector)** | Runs on the host and collects system and runtime evidence: OS, packages, kernel, processes, libraries, containers, applications, updates, configuration. Linux and Windows. | [Usage and every flag](https://github.com/s4e-io/openness-collector#usage) · [Releases](https://github.com/s4e-io/openness-collector/releases) |
| 🧠 **[openness-resolver](https://github.com/s4e-io/openness-resolver)** | Turns evidence into findings with vendor advisories, CVEs, applicability rules, fixed versions and native version comparators. Downloads the vendor data itself: no account, no API key. | [Usage and every flag](https://github.com/s4e-io/openness-resolver#usage) · [Data sources](https://github.com/s4e-io/openness-resolver#data-sources) · [Releases](https://github.com/s4e-io/openness-resolver/releases) |

---

## 📥 Install

**Linux / macOS**

```sh
curl -fsSL https://raw.githubusercontent.com/s4e-io/openness/main/install.sh | sh
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/s4e-io/openness/main/install.ps1 | iex
```

The installer finds the latest releases, verifies every binary against its release's `SHA256SUMS` and installs `openness-collector` and `openness-resolver` into `~/.local/bin` (Windows: `%LOCALAPPDATA%\Openness`, added to PATH). No root or Administrator rights are needed. `OPENNESS_COMPONENTS=collector` (or `resolver`) installs one, `OPENNESS_COLLECTOR_VERSION` / `OPENNESS_RESOLVER_VERSION` pin a release, `OPENNESS_INSTALL_DIR` picks the directory and `OPENNESS_DRY_RUN=1` shows the plan.

Prefer to do it by hand? Each project's README explains the release download, checksum check and building from source.

## 🚀 Quick start

```sh
sudo openness-collector collect --output host.openness                      # on the host to assess
openness-resolver feed sync --for host.openness --data-dir ./openness-data   # vendor data this host needs
openness-resolver resolve --input host.openness --output findings.json --data-dir ./openness-data
```

Remote servers over SSH, Windows, containers, air-gapped networks and keeping the data fresh are covered in the [collector](https://github.com/s4e-io/openness-collector#usage) and [resolver](https://github.com/s4e-io/openness-resolver#usage) READMEs.

---

## 🔍 Evidence First

Openness does not want to produce findings like:

```text
CVE-XXXX-YYYY → HIGH → VULNERABLE
```

It should be able to explain:

```text
Installed Version → Fixed Version → Vendor Rule
        ↓                 ↓              ↓
    Evidence      Native Comparator   Advisory
        └───────────────┬───────────────┘
                        ▼
                 VULNERABLE / FIXED
```

Every finding should answer:

**What? · Where? · Why applicable? · Which vendor rule? · Which fixed version? · What evidence?**

---

## 🧠 Vendor-Aware Resolution

Openness does **not** assume:

```text
package name + upstream CVE = vulnerable
```

Instead:

```text
System Evidence → Exact Software Identity → Vendor Applicability → Advisory / CVE → Fixed Version → Native Version Comparison → Explainable Finding
```

**Ubuntu → OVAL/USN + DPKG** · **Red Hat → advisories + RPM EVR** · **Alpine → SecDB + APK** · **Windows → MSRC + build** · **PyPI → OSV + PEP 440**

The resolver downloads this data straight from the publishers. Every source is listed in its [data sources](https://github.com/s4e-io/openness-resolver#data-sources) table.

---

## 🤖 Built for Autonomous Cybersecurity

Traditional scanners were designed mainly to produce reports for humans. Openness is being designed for both **humans and AI agents**.

```text
Evidence → Finding → Risk → Action → Verification
```

Future security agents will need reliable data before they can safely:

**Investigate · Prioritize · Patch · Mitigate · Validate · Verify**

Autonomy without evidence is dangerous. **Our goal is evidence-backed autonomous security.**

---

## 🌍 What We Want to Cover

**Operating Systems**
🐧 Ubuntu · Debian · Red Hat · Rocky · AlmaLinux · Amazon Linux · openSUSE · CentOS Stream · Alpine · Windows · macOS

**Software & Runtime**
📦 DEB · RPM · APK · Python/PyPI · Processes · Libraries · Containers · Kernels · Windows applications

**Security Intelligence**
🛡️ Vendor advisories · OVAL · CSAF/VEX · OSV · CVEs · Fixed versions · Runtime evidence

We prefer **correct support for fewer platforms** over broad coverage based on weak package-name matching. What works today is listed in each project's README.

---

## 🔬 More Than a Scanner

Openness starts as **a better open source alternative to Nessus.** The long-term vision is larger: structured security datasets that join

```text
System State + Vulnerability + Evidence + Applicability + Remediation + Action + Verification
```

for the next generation of **security agents · autonomous remediation · cyber reasoning models · security copilots · AI security evaluations**.

> 🧑‍💻 **Planned by cybersecurity experts** · 🤖 **Developed with AI models** · 🧪 **Validated against real systems** · 🌍 **Open source** · ❤️ **Created for everyone**

---

## 🤝 Let's Build It Together

Openness should not belong to one company, one team, or one AI model. It should be built by the global security community.

👨‍💻 **Code** · 🐛 **Report bugs** · 🧪 **Create test environments** · 🔍 **Validate findings** · 📦 **Add platforms** · 🛡️ **Add security feeds** · 💡 **Challenge the architecture**

You can help us prove where Openness is right, **and discover where it is wrong.** Start with the contributing guide of [openness-collector](https://github.com/s4e-io/openness-collector/blob/development/CONTRIBUTING.md) or [openness-resolver](https://github.com/s4e-io/openness-resolver/blob/main/CONTRIBUTING.md).

### Let's create a better open source alternative to Nessus, together.

---

## ✉️ Contact

Ideas, contributions, research collaborations, datasets and validation environments are welcome.

**Dr. Onur AKTAS** · [onur@s4e.io](mailto:onur@s4e.io) · [![LinkedIn](https://img.shields.io/badge/LinkedIn-Profile-blue?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/dr-onur-aktas/)

---

## 📜 License

Openness (this hub, [openness-collector](https://github.com/s4e-io/openness-collector) and [openness-resolver](https://github.com/s4e-io/openness-resolver)) is licensed under the [Apache License, Version 2.0](LICENSE).

- **Use it for anything:** personal, research, education and commercial use, modification and redistribution.
- **What it asks of you:** keep the LICENSE and NOTICE files with any copy you distribute and state significant changes.
- **Vendor data** the resolver downloads stays under its publishers' terms.

Openness is developed and maintained by [S4E (Security For Everyone)](https://s4e.io).

---

## ⚖️ Disclaimer

Openness is an independent open source project and is not affiliated with, endorsed by, or sponsored by Tenable. Nessus is a trademark of its respective owner. Scan only systems you own or are authorised to test.
