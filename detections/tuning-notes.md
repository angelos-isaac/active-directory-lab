# Tuning notes

Baselines established and false positives considered for each rule. A rule written without knowing what normal looks like is a rule that either alerts on everything or misses the thing it was built for.

---

## Rule 100100 — Local account creation via net.exe

**Status:** deployed, not yet tuned against sustained baseline traffic.

### What it matches

Any process creation where the image is `net.exe` or `net1.exe` and the command line contains `user` followed by `/add`.

### Known false positive source

**Legitimate administration matches this rule exactly.** An administrator creating a local account with `net user /add` produces telemetry identical to the attack at the process creation layer: same binary, same parent chain if run from a command prompt, same command structure.

This is unavoidable at the process level. The technique is not distinguishable from the operation, because it *is* the operation.

### What would distinguish them

Parent process is the best signal I have. When I ran the test the chain was powershell.exe → cmd.exe → net.exe, because that's how Atomic Red Team launches it. An admin typing the command themselves would have cmd.exe coming from explorer.exe. That's a real difference, but it's also the easiest thing for an attacker to change.

Frequency is what I'd actually build a rule on. Repeated create-then-delete pairs a few seconds apart means someone is testing password policy, and there's no normal reason for that to happen. It's harder to avoid than the parent process because it's just what the attacker is doing.

Time of day and account naming would help in a real environment, but I don't have a baseline for those. In a lab with four machines where I'm the only one creating accounts, I don't know what off-hours actually looks like.

### Options considered

| Option | Effect | Assessment |
|---|---|---|
| Narrow on parent process | Excludes known-good administration paths | Requires a stable baseline of who administers from where; not available in a lab this small |
| Lower severity from 12 to 6 | Reduces alert fatigue, keeps visibility | Understates a technique that matters |
| Add a frequency rule for create-delete pairs | Catches password policy probing specifically | Highest value addition; not yet implemented |
| Suppress entirely | Removes noise | Rejected — suppression hides the technique, not just the noise |

**Current disposition:** left at level 12 unnarrowed. In a lab with four endpoints and no routine administration, the false positive rate is effectively zero. In production this would need parent process narrowing before deployment.

### Observed behaviour worth alerting on separately

Failed account creation produces a create event followed by a delete event within the same second, because Windows writes the account object before applying the password and rolls it back on failure. Repeated pairs indicate an attacker probing password policy rather than an administrator working.

This is a stronger signal than successful creation and is not currently covered by any rule.

---

## LSASS access baseline

Established before executing T1003.001, so that any rule written would be specific rather than alerting on all access to LSASS.

### Normal access on WKS01

| Source | Via | GrantedAccess | Notes |
|---|---|---|---|
| `MsMpEng.exe` | — | `0x1000` | Defender, 12 occurrences in 30 seconds |
| `MsMpEng.exe` | — | `0x101000` | Defender, 1 occurrence |
| `svchost.exe` | `sysmain.dll` | `0x2000` | SysMain prefetch service |
| `svchost.exe` | `lsm.dll` | `0x1000` | Local Session Manager |

All sources run as `NT AUTHORITY\SYSTEM`. All access values are well below the `0x1010` and `0x1410` range that reading process memory requires.

**Three legitimate sources total.** This is a quiet lab workstation; a production endpoint would show considerably more, and the resulting rule would need correspondingly more care.

### Why GrantedAccess is the field that matters

Alerting on "a process accessed LSASS" would fire constantly — 13 times in 30 seconds on an idle machine. The signal is not the access, it is the access *rights*. Dumping memory requires `PROCESS_VM_READ` combined with `PROCESS_QUERY_INFORMATION`, which appears as `0x1010` or `0x1410`. Routine service checks use `0x1000` or `0x2000`.

### CallTrace as a second signal

Every Event 10 record includes the DLL chain that led to the access. Legitimate accesses trace through recognisable service DLLs — `sysmain.dll`, `lsm.dll`. A credential dump traces through `comsvcs.dll` or an unusual path.

A rule matching on both GrantedAccess and CallTrace is meaningfully harder to evade than one matching on process name, because an attacker renaming their binary changes neither field.

### No rule written

T1003.001 was blocked by Microsoft Defender before `rundll32.exe` opened a handle to LSASS, so no attack-generated Event 10 exists in this environment to test a rule against. Writing one against the baseline alone would mean deploying an untested detection.

I think it was the right call. I know what normal LSASS access looks like from my baseline, and I know from the docs that dumping needs 0x1010 or 0x1410. But I've never actually seen a dump in this environment, so any rule I wrote would be untested against the exact thing it's supposed to catch.

That matters here because of what happened with rule 100100. That rule loaded fine, validated fine, and matched nothing until I fixed the regex type. If I hadn't had a real event to test it against, I would have assumed it was working.

To do this properly I'd need to actually generate the telemetry. That means temporarily turning off Defender's real-time protection on WKS01, running the technique, capturing the Event 10, turning protection back on, then writing and testing the rule against the event I captured. Deliberately weakening a control on an isolated VM for one specific test is defensible, but I'd want to write it down as a decision instead of just leaving Defender off and forgetting about it.

---

## Configuration change required before any of this was possible

The SwiftOnSecurity Sysmon configuration ships with `ProcessAccess onmatch="include"` and no filter rules beneath it, which logs nothing. Event ID 10 was entirely absent from 2,000 sampled events before this was corrected.

```xml
<ProcessAccess onmatch="include">
  <TargetImage condition="image">lsass.exe</TargetImage>
</ProcessAccess>
```

Scoped to LSASS specifically rather than enabling all process access logging, because the volume of the latter is the reason the config authors disabled it in the first place.
