# Architecture and design

**Status:** Complete  ·  **Date completed:** 2026-08-06  ·  **Systems:** All

> Build guide reference: Guide Parts 1-3

---

## Objective

Design decisions made before any system was built: addressing, naming, isolation model, and the rationale behind each.

---

## Network design

| Address | Role |
|---|---|
| `10.10.10.0/24` | Lab subnet |
| `10.10.10.2` | NAT gateway |
| `10.10.10.10` | DC01 — domain controller, DNS, DHCP |
| `10.10.10.20` | FS01 — file server |
| `10.10.10.30` | SIEM01 — log aggregation |
| `10.10.10.100-200` | DHCP scope |

Servers are statically addressed and endpoints use DHCP. DC01's address is written into every client's DNS configuration through DHCP option 006, so if it changed on a lease renewal every machine in the domain would lose the ability to authenticate at the same moment. Infrastructure gets fixed addresses; endpoints get assigned ones.

**Isolation model**

The lab runs on a NAT network rather than a bridged one. Bridged would place every lab machine directly on the home LAN, which means a second DHCP server answering on a network other people use, and eventually attack simulation traffic on the same segment as real devices. NAT keeps the domain isolated while still allowing outbound access for updates and package downloads.

---

## Naming decisions

**Domain:** `corp.isaacsolutions.lab`

Used a fictional company name so the environment reads like a real deployment rather than a lab exercise.

The TLD choice mattered more. I avoided `.local` because it's reserved for multicast DNS  any Apple or Linux device on the network would break name
resolution, and it's a common mistake in older AD tutorials. I also avoided using a domain I actually own, since matching a public domain internally
creates split-brain DNS: internal clients resolve to internal servers while external clients get the public site, leaving two zones to keep in sync permanently. `.lab` is reserved and avoids both problems.

`CORP` as the NetBIOS name short, generic, and what a real organization would typically use for the legacy logon prefix.

**Host naming:** role prefix plus a number — `DC01` domain controller, `FS01` file server, `WKS01` and `WKS02` workstations. The role is readable from the name in event logs and ACLs without needing to look the machine up.

**Group naming:** `GG-` global (identity), `DL-` domain local (access)

The prefixes encode the AGDLP layer, so anyone reading a permissions report can tell immediately whether a group represents an identity or an access grant. `GG-Accounting` describes who someone is; `DL-Accounting-Share-Modify` describes what access is being given. Seeing a `GG-` group on a file ACL would itself be an exception.

---

## Architecture diagram

![Lab architecture](../images/architecture-diagram.png)

---

## Problems encountered

No blocking issues. This phase is design rather than implementation; problems encountered while building against these decisions are recorded in the relevant phase documents and in the [failure log](failure-log.md).
