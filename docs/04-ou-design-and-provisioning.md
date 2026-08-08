# Phase 4 — OU design and user provisioning

**Status:** Complete  ·  **Date completed:** 2026-08-06  ·  **Systems:** DC01

> Build guide reference: Guide Part 7

---

## Objective

Build an OU structure that supports targeted Group Policy, and populate it with realistic scale through automation rather than manual creation.

---

## Design rationale

```
corp.isaacsolutions.lab
├── IS-Users ── Accounting, IT, Sales, Executives
├── IS-Computers ── Workstations, Servers
├── IS-Groups ── Global, DomainLocal
├── IS-ServiceAccounts
└── IS-AdminAccounts
```

I kept users and computers in separate OUs because Group Policy has two independent halves, Computer Configuration and User Configuration. Computer settings only apply to computer objects and user settings only apply to user objects, so if you mix both types into one OU, half of every policy you link there does nothing.

The departments sit inside IS-Users because policy inherits downward. A GPO linked to IS-Users hits everyone, and a GPO linked to Accounting only hits Accounting, so company-wide settings get written once at the top and department-specific settings go on the department. If they conflict, the closer OU wins.

Servers and workstations are split for the same reason. A workstation should lock after a few minutes of inactivity, but a server needs to run unattended, so they need different policy.

Service accounts and admin accounts have their own OUs so they can be found and monitored as a group. A service account logging in interactively is a warning sign, and you can only alert on that if you know which accounts are service accounts.

![OU structure in ADUC](../images/aduc-ou-structure.png)

---

## Group model — AGDLP

| Layer | Naming | Example | Contains |
|---|---|---|---|
| Global | `GG-` | `GG-Accounting` | User accounts |
| Domain Local | `DL-` | `DL-Accounting-Share-Modify` | Global groups |
| Permission | — | NTFS ACL on the share | Domain local groups only |

Assigning users directly to folders works until it does not. Moving someone between departments would mean finding and changing every permission attached to them across every share, and answering a question like "who can modify financial records" would mean crawling every ACL on every server and hoping nothing was missed. Under AGDLP both become a single group membership, and the audit question becomes reading one group.

---

## Automated provisioning

`scripts/provisioning/New-LabUsers.ps1`

![Provisioning run output](../images/provisioning-run-output.png)

48 accounts created across four departmental OUs — Accounting, IT, Sales, and Executives — in a single run.

**Design features**

- Idempotent — existing accounts skipped, safe to re-run
- Per-row error handling — one bad record doesn't halt the batch
- Audit log — CSV of every CREATED / SKIPPED / FAILED result
- `-ChangePasswordAtLogon` — a shared known password is a finding; forced rotation is the control that addresses it

### Development notes

The script needed a rollback step after the first run left 48 half-created accounts behind. New-ADUser writes the account object before setting the password, so a failed password leaves an unusable account in the directory and the next run skips it as "already exists." Full write-up: FL-002.

---

## Problems encountered

- [FL-002 — Bulk provisioning failed, then said everything was fine when it wasn't](failure-log.md)

`New-ADUser` creates the account object before applying the password. An empty password failed complexity validation and threw an error, but 48 objects had already been written to the directory in an unusable state. The second run then reported all 48 as SKIPPED / "already exists" — technically accurate, and misleading enough that the actual state was only found by querying the directory rather than trusting the script's own log.

---

## Verification

| Check | Command | Result |
|---|---|---|
| OU structure created | `Get-ADOrganizationalUnit -SearchBase "OU=IS-Users,..."` | Four departmental OUs present |
| Default containers redirected | `redircmp`, `redirusr` | New objects land in IS- OUs |
| All accounts provisioned | `Get-ADUser -SearchBase "OU=IS-Users,..." \| Measure-Object` | 48 |
| Group membership applied | `Get-ADGroupMember -Identity "GG-Accounting"` | Members match CSV department |
| Script safe to re-run | Second execution of `New-LabUsers.ps1` | All rows SKIPPED, no duplicates |

---

## Notes

