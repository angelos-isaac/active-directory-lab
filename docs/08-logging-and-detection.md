# Phase 8 — Logging and detection

**Status:** Planned — not yet implemented  ·  **Systems:** All + SIEM01

> Build guide reference: Guide Part 11

---

## Scope of this document

**Nothing in this phase has been built yet.** This document records the intended design so the plan is visible, and will be replaced with implementation detail and evidence once the work is done. Nothing here should be read as a description of the current environment.

The environment as it stands is documented in Phases 1 through 7 and in the [access control review](../audit/findings-register.md).

---

## Planned design

| Source | Provides |
|---|---|
| Sysmon | Process creation with parent process and hashes, network connections mapped to processes, registry and file events |
| Windows Security log | Authentication, account management, object access — already configured in [Phase 6](06-group-policy.md) |
| PowerShell script block logging | Executed code after deobfuscation |

**Why Sysmon rather than native logging alone.** The parent process relationship is the addition that matters. Word spawning `powershell.exe` is a malicious document; `explorer.exe` spawning it is a user opening a terminal. Native Windows logging makes that distinction difficult to draw.

**Deployment approach.** Binary and configuration staged in SYSVOL, installed by a GPO startup script with an idempotency check so it does not reinstall on every boot. A startup script rather than a logon script, because installing a kernel driver requires SYSTEM rather than user privileges.

**Aggregation.** Wazuh on a dedicated Ubuntu host, agents on DC01, FS01, WKS01, and WKS02.

**Attack simulation.** Atomic Red Team on WKS01 only, on the isolated NAT network, against systems personally owned. Techniques selected for benign, unambiguous telemetry: T1136.001 (create account), T1059.001 (PowerShell execution), T1053.005 (scheduled task persistence).

---

## Groundwork already in place

The audit configuration this phase depends on was completed in Phase 6:

- Advanced audit policy across all eleven relevant subcategories, verified applied on the endpoint with `auditpol`
- Command line auditing enabled, so event 4688 records full commands rather than executable paths alone
- PowerShell module and script block logging enabled
- Object access auditing with SACLs on the Accounting and HR shares, confirmed generating 4663 events

---

## Note on rule development

Parent rule IDs and decoded field names differ between Wazuh versions. A custom rule chained to the wrong parent produces **no alert and no error**, which is the most dangerous failure mode in detection work because an empty dashboard is indistinguishable from an absence of malicious activity. Rules will be validated against live events with `wazuh-logtest` before being recorded as working.
