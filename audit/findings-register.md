# Access control review — findings register

Control review of the `corp.isaacsolutions.lab` Active Directory environment and the FS01 file server, tested against CIS Controls v8.

**Scope:** Active Directory identity and access management (user accounts, privileged group membership, credential settings) and NTFS/share permissions on FS01.
**Environment:** Single-domain forest, 1 domain controller, 1 file server, 2 workstations, 51 user accounts.
**Review date:** 2026-08-06  ·  **Remediation date:** 2026-08-06  ·  **Retest date:** 2026-08-06
**Reviewer:** Angelos Isaac

---

## Methodology

Testing was performed using PowerShell queries run directly against Active Directory (DC01) and the file system (FS01). Each finding below references the query that produced it, and evidence is captured before and after remediation in [`evidence/`](evidence/).

**Known limitation.** Account dormancy was determined using `LastLogonDate`, which is derived from the `lastLogonTimestamp` attribute. By design this attribute only replicates when the new value is roughly 9–14 days newer than the stored value, so results may be up to two weeks stale. It was chosen over `lastLogon` because `lastLogon` is not replicated between domain controllers and would require querying each DC separately and taking the maximum. For a 90-day dormancy threshold the replication lag is not material.

---

## Summary of findings

| ID | Finding | Severity | CIS Control | Status |
|---|---|---|---|---|
| AD-2026-001 | Accounts configured with non-expiring passwords | Medium | 5.2 | Remediated, retested |
| AD-2026-002 | Service account holds unnecessary Domain Admin membership | High | 5.4 | Remediated, retested |
| AD-2026-003 | Enabled accounts with no logon activity | Low | 5.3 | Scoped — see finding |
| AD-2026-004 | Share grants Full Control to Everyone | High | 3.3 | Remediated, retested |
| AD-2026-005 | Direct user assignments on file share ACLs | — | 6.8 | No exceptions noted |

---

## AD-2026-001 — Accounts configured with non-expiring passwords

| Field | Detail |
|---|---|
| **Severity** | Medium |
| **Control reference** | CIS Control 5.2 — Use Unique Passwords |
| **Testing procedure** | Query 1: enumerate enabled accounts where `PasswordNeverExpires` is true |
| **Condition** | Three enabled accounts are configured so their passwords never expire: `svc-backup`, `kmalone` (Kevin Malone, Accounting), and the built-in `Administrator`. |
| **Criteria** | Domain password policy sets a maximum password age of 365 days. Accounts exempted from that policy should be limited to those with a documented operational reason and a compensating control. |
| **Cause** | The exemption is a single checkbox that removes an operational inconvenience — the account never prompts for a change and never interrupts a running process. Nothing in the provisioning process requires a justification to be recorded, and no recurring review exists that would surface the exemption after the fact. It is set once and never revisited. |
| **Effect** | A credential that never rotates remains valid indefinitely. If it is captured, the exposure window does not close on its own; it persists until someone notices and acts. This extends the useful life of a stolen credential from months to years. |
| **Recommendation** | Clear `PasswordNeverExpires` on `svc-backup` and `kmalone`. For service accounts requiring non-interactive authentication, migrate to a Group Managed Service Account (gMSA) so the password rotates automatically without application impact. Establish a quarterly review of accounts holding this exemption. |
| **Remediation** | `Set-ADUser -Identity "kmalone" -PasswordNeverExpires $false` and the same for `svc-backup`. |
| **Retest result** | Verified — both accounts now subject to domain password policy. Evidence: `evidence/finding-001-retest.png` |

### Sub-item — built-in Administrator account (risk accepted)

The built-in `Administrator` account also carries this setting, applied by default at domain creation rather than by configuration.

**This was deliberately not remediated.** Allowing the built-in Administrator password to expire creates a lockout risk: if it expires while no other Domain Admin account is usable, there is no supported path back into the domain. The standard practice is to keep the account disabled or its credential vaulted rather than to subject it to rotation.

**Compensating controls:** the account is not used for routine administration — a separate named account (`a-angelos`) exists for that purpose — and `Audit Credential Validation` is enabled domain-wide, so authentication attempts using it are logged.

**Disposition:** risk accepted. Revisit if the account is ever used for interactive logon.

**Evidence:** `evidence/finding-001-before.png`

---

## AD-2026-002 — Service account holds unnecessary Domain Admin membership

| Field | Detail |
|---|---|
| **Severity** | High |
| **Control reference** | CIS Control 5.4 — Restrict Administrator Privileges to Dedicated Administrator Accounts |
| **Testing procedure** | Query 2: recursive enumeration of Domain Admins, Enterprise Admins, Schema Admins, and Account Operators |
| **Condition** | `svc-backup`, a non-interactive service account, is a member of Domain Admins. Combined with AD-2026-001, the account also has a non-expiring password. |
| **Criteria** | Service accounts should hold only the privileges required to perform their function. Backup operations require the ability to read files irrespective of NTFS permissions, which is granted by the built-in Backup Operators group. They do not require the ability to modify the directory, alter group membership, or authenticate to domain controllers. |
| **Cause** | Domain Admin was granted because it was faster than determining which specific rights a backup process actually needs. Working out the minimum set requires understanding both the application and the privilege model; adding the account to Domain Admins takes one command and is guaranteed to work. No entitlement review process existed that would have surfaced the over-grant afterwards, so a decision made once for convenience became permanent by default. |
| **Effect** | Compromise of this single credential yields full control of the domain — every account, every policy, every domain-joined system. Because the account is non-interactive, its credential is likely stored in a configuration file or scheduled task rather than typed by a person, which increases the chance of it being recoverable from disk. The non-expiring password means the exposure does not close on its own. |
| **Recommendation** | Remove from Domain Admins and add to Backup Operators. Migrate to a Group Managed Service Account so the credential rotates automatically. Implement a quarterly privileged access review covering all four groups tested here. |
| **Remediation** | `Remove-ADGroupMember -Identity "Domain Admins" -Members "svc-backup" -Confirm:$false` followed by `Add-ADGroupMember -Identity "Backup Operators" -Members "svc-backup"` |
| **Retest result** | Verified — Domain Admins membership reduced to `Administrator` and `a-angelos`, and `svc-backup` confirmed present in Backup Operators, so the account retains the rights required to perform its function. Evidence: `evidence/finding-002-retest.png` |

**Positive observations from the same test.** Enterprise Admins and Schema Admins contain only the built-in `Administrator`, which is appropriate for a single-domain forest. Account Operators is empty — notable because that group can modify most user and group objects and is frequently populated without the delegation implications being understood.

Account Operators remained empty through remediation, confirming no delegation was inadvertently introduced while adjusting group membership.

**Evidence:** `evidence/finding-002-before.png`

---

## AD-2026-003 — Enabled accounts with no logon activity

| Field | Detail |
|---|---|
| **Severity** | Low |
| **Control reference** | CIS Control 5.3 — Disable Dormant Accounts |
| **Testing procedure** | Query 3: enabled accounts with `LastLogonDate` older than 90 days or null |
| **Condition** | 49 of 51 enabled accounts returned no logon history. The two exclusions were `Administrator` and `jhalpert`, both of which have authenticated within the 90-day threshold. The population comprises 48 provisioned user accounts, the built-in `Administrator`, the administrative account `a-angelos`, and the service account `svc-backup`. |
| **Criteria** | Accounts with no authentication activity beyond a defined threshold should be disabled, as they represent access that is granted but not in use. |
| **Cause** | The accounts were bulk-provisioned during environment build and have not yet been issued to users, so the absence of logon history reflects a newly constructed environment rather than abandoned access. The underlying control gap is that no process exists to distinguish "provisioned but not yet issued" from "issued and subsequently abandoned" — both present identically in the directory, and only the second is a finding. |
| **Effect** | In a production environment, dormant enabled accounts expand the attack surface without providing value, and are attractive targets for password spraying precisely because nobody is using them and a lockout would go unnoticed. |
| **Recommendation** | Scope the exception to accounts that have been issued and subsequently gone unused. Record a provisioning date on new accounts so that "never used" can be distinguished from "no longer used." Implement automated disablement at 90 days of inactivity measured from issuance rather than creation. |
| **Retest result** | Account population unchanged from the original test, as expected — dormancy itself was not remediated. The exception identified (`kmalone`, non-expiring password on an account with no logon history) was remediated under AD-2026-001. Bulk-provisioned accounts remain enabled pending issuance and are recorded as expected condition rather than exception. Evidence: `evidence/finding-003-retest.png` |

**Methodology note.** The query correctly excluded the two accounts with recent authentication, which confirms the test logic functions as intended rather than returning all accounts indiscriminately. This distinction matters: a query that returns everything is usually broken, and a query that returns everything *except* the accounts you expect it to exclude is working.

**Evidence:** `evidence/finding-003-before.png`

---

## AD-2026-004 — Share grants Full Control to Everyone

| Field | Detail |
|---|---|
| **Severity** | High |
| **Control reference** | CIS Control 3.3 — Configure Data Access Control Lists |
| **Testing procedure** | Query 4: enumerate NTFS ACLs on all shares under `D:\Shares` for entries granting access to Everyone, Authenticated Users, or BUILTIN\Users |
| **Condition** | `D:\Shares\Public` grants `Everyone: Full Control`, with inheritance flags applying the entry to all subfolders and files. `BUILTIN\Users` additionally holds ReadAndExecute, AppendData, and CreateFiles inherited from the volume root. |
| **Criteria** | Access to file shares should be granted through domain local groups under the AGDLP model, with permissions scoped to the minimum required. Full Control additionally permits modification of the ACL itself, allowing a holder to grant further access. |
| **Cause** | Broad permissions were applied to make a general-use share immediately accessible without first determining who needed access. This is the path of least resistance whenever access requirements are unclear: granting everything works for everyone and generates no support tickets, whereas a scoped grant requires knowing the answer up front. The absence of inheritance breaking meant the volume root's default permissions also flowed down unnoticed, so part of the exposure was never an explicit decision at all. |
| **Effect** | Every authenticated domain user can read, modify, and delete any content in the share. Full Control further permits changing the ACL, so a user could grant themselves or others persistent access without administrative involvement. In a production environment this defeats data classification entirely, since any file placed in the share becomes universally accessible regardless of its sensitivity. |
| **Recommendation** | Break inheritance on the share root, remove the Everyone and BUILTIN\Users entries, and apply access through `DL-Public-Share-Modify` consistent with the model used on the Accounting and HR shares. Enable object access auditing on the share. |
| **Remediation** | Inheritance protected, broad principals removed, `DL-Public-Share-Modify` (Modify) and Domain Admins (Full Control) applied. |
| **Retest result** | Verified — query returns no results for `D:\Shares\Public`. Evidence: `evidence/finding-004-retest.png` |

**Note on share versus NTFS permissions.** All three shares grant Full Control to Authenticated Users at the *share* level by design. Windows evaluates share and NTFS permissions independently and applies the more restrictive result, so leaving share permissions open and enforcing entirely at NTFS gives a single layer to audit and change rather than two that must be kept reconciled. An open share permission is therefore not itself a finding until the NTFS layer has been examined.

**Evidence:** `evidence/finding-004-before.png`

---

## AD-2026-005 — Direct user assignments on file share ACLs

| Field | Detail |
|---|---|
| **Severity** | — (no exceptions noted) |
| **Control reference** | CIS Control 6.8 — Define and Maintain Role-Based Access Control |
| **Testing procedure** | Query 5: recursive enumeration of all ACL entries under `D:\Shares` for domain principals that are neither domain local (`DL-`) groups nor Domain Admins |
| **Condition** | No exceptions identified. All domain principals appearing on share ACLs are domain local groups or Domain Admins. No individual user accounts and no global (`GG-`) groups hold direct permissions. |
| **Criteria** | Under the AGDLP model, permissions are assigned only to domain local groups. User accounts are placed in global groups by role, and global groups are nested into domain local groups by access requirement. |
| **Effect if violated** | Direct user assignments do not scale and are difficult to review. Answering "who can modify financial records" would require enumerating every ACL on every share rather than examining a single group, and access would persist through role changes because it is attached to the person rather than the position. |
| **Conclusion** | Control operating effectively. No remediation required. |
| **Retest result** | Re-tested post-remediation to confirm no direct assignments were introduced during the fixes applied above. Evidence: `evidence/finding-005-retest.png` |

**Why a null result is recorded rather than omitted.** A test performed with no exceptions found is evidence that a control was examined and operating, which is materially different from a control that was never tested. Omitting passed tests leaves a reader unable to distinguish between the two.

---

## Observations not rising to findings

**Unmanaged local administrator accounts.** Windows LAPS manages the built-in local Administrator account on all domain-joined systems, verified on FS01 and WKS01. However, the separate local accounts created during Windows 11 setup (`localadmin` on WKS01, `localadmin2` on WKS02) fall outside LAPS scope. Their passwords were manually set and do not rotate. These accounts exist as a recovery path for domain authentication failure, which is a legitimate purpose, but in a production environment they would warrant either inclusion in a credential management process or removal.

**Preventive control confirmed operating.** During testing, an attempt to create a service account with a weak password (`Backup123!`) was rejected by the domain password policy. This confirms the 14-character minimum and complexity requirement configured in the Default Domain Policy are enforced at account creation. Weak passwords are therefore prevented at the point of entry and cannot appear as a finding — the condition cannot exist. This illustrates the division of labour between preventive controls, which make a bad state impossible, and detective controls such as this review, which identify bad states that policy permits.

---

## Evidence index

| File | Contents |
|---|---|
| `evidence/finding-001-before.png` | Query 1 — non-expiring passwords, pre-remediation |
| `evidence/finding-001-retest.png` | Query 1 — post-remediation |
| `evidence/finding-002-before.png` | Query 2 — privileged group membership, pre-remediation |
| `evidence/finding-002-retest.png` | Query 2 — post-remediation |
| `evidence/finding-003-before.png` | Query 3 — dormant accounts, pre-remediation |
| `evidence/finding-003-retest.png` | Query 3 — post-remediation |
| `evidence/finding-004-before.png` | Query 4 — permissive share ACLs, pre-remediation |
| `evidence/finding-004-retest.png` | Query 4 — post-remediation |
| `evidence/finding-005-before.png` | Query 5 — direct ACL assignments, no exceptions |
| `evidence/finding-005-retest.png` | Query 5 — post-remediation confirmation |
