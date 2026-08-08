# Phase 1 — Host and network setup

**Status:** Complete  ·  **Date completed:** 2026-08-06  ·  **Systems:** Host, VMnet8

> Build guide reference: Guide Parts 2-4

---

## Objective

Configure the hypervisor and virtual network so the domain controller can own DNS and DHCP for an isolated subnet that still has outbound internet access.

---

## Host configuration

| Setting | Value | Reason |
|---|---|---|
| Hypervisor | VMware Workstation Pro 17 | Uses its own VMM, so there is no permanent host performance cost the way enabling Hyper-V would impose |
| Memory reservation | Fit all VM memory in host RAM | Prevents guest memory paging to a `.vmem` file, which makes a domain controller behave like failing hardware |
| Defender exclusion | VM directory | Real-time scanning inspects every write to every virtual disk |

**On the Defender exclusion.** This is a real tradeoff rather than a free optimisation. Excluding a directory from real-time scanning means malware written there would not be caught on write. It is acceptable here because the lab runs on an isolated NAT network with no route to the host LAN, and because the exclusion is scoped to a single folder rather than disabling protection globally. It would be reckless applied to the host system drive, and the distinction is the point: the same action is defensible or negligent depending entirely on scope and what else is containing the risk.

---

## Virtual network

**VMnet8 (NAT)**, subnet `10.10.10.0/24`, with VMware's local DHCP service **disabled**.

Disabling VMware's DHCP is the single most important setting in this phase. Two DHCP servers answering on the same subnet is a race — whichever replies first wins — so clients would receive correct settings sometimes and wrong ones other times. Intermittent failures are considerably harder to diagnose than consistent ones, and a client that gets the NAT device as its DNS server has flawless internet access and cannot see the domain at all.

| Address | Role |
|---|---|
| `10.10.10.1` | Host virtual adapter |
| `10.10.10.2` | NAT gateway, and the DNS forwarder target |
| `10.10.10.10` | DC01 |
| `10.10.10.20` | FS01 |
| `10.10.10.100-200` | DHCP scope issued by DC01 |

---

## VM inventory

| VM | OS | Processors × cores | RAM | Disk |
|---|---|---|---|---|
| DC01 | Windows Server 2025 Standard (Desktop Experience) | 1 × 2 | 4 GB | 60 GB |
| FS01 | Windows Server 2025 Standard | 1 × 2 | 4 GB | 60 GB + 40 GB data volume |
| WKS01 | Windows 11 Enterprise | 1 × 2 | 4 GB | 64 GB |
| WKS02 | Windows 11 Enterprise | 1 × 2 | 4 GB | 64 GB |

**One socket with two cores rather than two single-core sockets.** Two sockets makes Windows treat the guest as a NUMA system and attempt memory placement optimisation across nodes that do not physically exist. Harmless, but pointless, and single-socket is how a small VM is actually provisioned.

**Windows 11 requires a TPM**, and VMware will not attach a virtual TPM to an unencrypted VM. Both workstations use partial VM encryption — only the files needed to support the vTPM — rather than full-disk encryption, which would cost performance for no benefit here. The check was satisfied properly rather than bypassed with a registry edit, because the reason it exists is worth understanding: the TPM provides a hardware root of trust that seals BitLocker keys to the boot state, so the disk will not decrypt if the boot chain has been tampered with.

---

## Problems encountered

- [FL-001 — VM won't power on](failure-log.md)

The VMware installation directory had been moved manually, which left registry-recorded paths pointing at a location that no longer existed. Workstation appeared healthy right up until it needed a binary it only invokes at VM power-on.

A follow-on effect surfaced later: repairing the installation reset VMnet8 to its default subnet, which broke connectivity inside DC01. The symptom appeared in the guest as an unreachable gateway while the actual cause was on the host, two layers down, and was a delayed side effect of a repair run for an unrelated problem.

---

## Verification

| Check | Command | Result |
|---|---|---|
| Host virtual adapter present on the correct subnet | `Get-NetIPAddress -InterfaceAlias "*VMnet8*"` | `10.10.10.1` |
| VMware DHCP disabled on VMnet8 | Virtual Network Editor | Unchecked |
| NAT gateway reachable from guest | `ping 10.10.10.2` | Pass |
| Outbound routing without DNS | `ping 8.8.8.8` | Pass |
