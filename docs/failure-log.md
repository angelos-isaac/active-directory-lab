# Failure log

Problems encountered during the build, how they were diagnosed, and what they taught me.

---

## FL-001 — VM won't power on

**Phase:** Part 4 — VM creation  ·  **Systems:** Host, DC01  ·  **Time lost:** Around 5 Min

**Symptom**

DC01 failed to start immediately on power-on:

'Unable to find the VMX binary 'C:\VMware\vmware-vmx.exe''

The VM had been created successfully with no errors, and the settings summary showed everything configured correctly.

**Investigation**

- First thought it was a problem with the VM itself, but the error referenced a path on the C: drive rather than anything under the VM directory.
- Recalled that I had recently moved the VMware installation folder from C: to D:.
- Confirmed with `Test-Path "C:\VMware\vmware-vmx.exe"` — returned False, so the binary genuinely wasn't at the path VMware was looking for.
- Attempted Repair via Settings → Apps → VMware Workstation → Modify. This failed, because Repair itself needs the binary it's trying to restore.
- The failure message specified running the installer MSI directly. Ran `msiexec.exe /i C:\WINDOWS\Installer\aa9e6b.msi` from an elevated PowerShell session, completed the repair, and rebooted.

**Root cause**

I relocated the VMware Workstation installation directory by moving the folder
in Explorer. Windows applications store their install path in the registry at
install time, so moving the files leaves every registered path pointing at a
location that no longer exists. Workstation's UI continued to work because
creating and configuring a VM doesn't invoke `vmware-vmx.exe` — that binary is
only called at power-on, so the broken installation stayed invisible until the
first attempt to start a guest.

**Resolution**

Repaired the installation by invoking the MSI directly from an elevated prompt, then rebooted. DC01 powered on normally.

The correct way to relocate an installed application is to uninstall and
reinstall to the target path, not to move the directory.

**What I learned**

The layer an error surfaces at isn't necessarily the layer that's broken. This appeared on VM power-on and looked like a VM fault, but the path in the message pointed at the hypervisor installation — reading the error carefully was faster than troubleshooting DC01.

An application can also appear fully healthy while a component it only invokes conditionally is missing. Workstation looked fine right up until it needed the one binary it didn't have.

---

## FL-002 — Bulk provisioning failed, then said everything was fine when it wasn't

**Phase:** Part 7, User provisioning  ·  **Systems:** DC01  ·  **Time lost:** ~15 min

**Symptom**

First run of my provisioning script: all 48 accounts came back FAILED with "The password does not meet the length, complexity, or history requirement of the domain." I ran it again and this time all 48 said SKIPPED / "Already exists", which made it sound like the accounts were there and everything was fine.

**Investigation**

- At first I thought my temporary password just wasn't complex enough for the domain policy.
- Then I scrolled back through the console. On the first run there were no asterisks after the password prompt, but on the second run there were. So I had hit Enter without typing anything and sent an empty password.
- That explained the first run, but not the second one. If nothing got created, why did it say all 48 already existed?
- So I checked AD directly instead of trusting the script: Get-ADUser -Filter * -SearchBase "OU=IS-Users,..." -Properties Enabled 
- All 48 accounts were sitting there, disabled.

**Root cause**

`New-ADUser` doesn't do everything at once. It creates the account object first, then sets the password. My empty password failed the complexity check and threw an error, but the account object had already been written to AD. My catch block just logged FAILED and moved on, so I ended up with 48 half-created accounts that couldn't be used.

On the second run, the "does this user already exist?" check found those broken objects and skipped every single row. So the script said SKIPPED while AD was actually in a bad state. It was silent because my error handling assumed a step either worked completely or did nothing at all.

**Resolution**

Deleted the broken accounts: Get-ADUser -Filter * -SearchBase "OU=IS-Users,DC=corp,DC=isaacsolutions DC=lab" | Remove-ADUser -Confirm:$false

Then added rollback to my catch block. If creating a user fails, it now checks whether the object got made anyway and deletes it before logging. That way a failed row doesn't leave anything behind for the next run to trip over. Re-ran it with a real password and got 48 CREATED.

**What I learned**

A command can fail partway through and still leave stuff behind. I assumed "failed" meant "nothing happened," but the account was actually there, it just
didn't work. If a script creates things, it needs to clean up after itself when something goes wrong otherwise the next run inherits the mess.

The bigger thing though is that the second run wasn't wrong exactly, it was misleading. "Already exists" is technically true and it sounds like good news. I only found out what was really going on by querying AD myself instead of believing my own script's output. Check the actual system, not what your tool says about the system.

## FL-003 — LAPS returned nothing at all, with no error

**Phase:** Part 9, Group Policy  ·  **Systems:** DC01, WKS01  ·  **Time lost:** ~10 min

**Symptom**

Ran `Get-LapsADPassword -Identity "WKS01" -AsPlainText` and got nothing back. No password, no error message, no warning. Just an empty line and a new
prompt.

**Investigation**

- First thought the schema extension hadn't worked, since that was the step right before it and it's the one that can't be undone. Checked, and it had gone through fine.
- Then figured maybe the password just hadn't generated yet, so I ran `gpupdate /force` and `Invoke-LapsPolicyProcessing` on WKS01 to make it pull policy immediately instead of waiting for the next refresh. Still nothing.
- Went back further and checked whether the policy was even reaching the machine: Get-GPInheritance -Target "OU=IS-Computers,DC=corp,DC=isaacsolutions,DC=lab" `GpoLinks` came back as `{}`. Empty.

**Root cause**

I created the LAPS GPO and configured all the settings, but I never linked it to the OU. Creating a GPO and linking a GPO are two separate steps, and I
only did the first one. The GPO was sitting in the Group Policy Objects folder with everything set up correctly and doing absolutely nothing, because nothing was pointed at it.

So WKS01 never got the policy, never generated a password, and never wrote anything to its AD object. `Get-LapsADPassword` was correctly reporting that there was no password stored. There was nothing wrong for it to report.

**Resolution**

    New-GPLink -Name "LAPS - Workstations" `
      -Target "OU=IS-Computers,DC=corp,DC=isaacsolutions,DC=lab" `
      -LinkEnabled Yes

Then `gpupdate /force` and `Invoke-LapsPolicyProcessing` on WKS01 again, and
`Get-LapsADPassword` returned the password with `DecryptionStatus: Success`.

Afterwards I checked every other GPO for missing links, since if I did it once I could have done it twice.

**What I learned**

Configuring a GPO and applying a GPO are not the same thing. All the settings work I did felt like the actual task, but a GPO with perfect settings and no
link has zero effect on anything.

This is also the second time I've been caught by a command that returns nothing instead of an error. In FL-002 the script said SKIPPED when accounts were broken, and here LAPS returned blank when policy had never been applied. Both times I assumed no error meant no problem. Empty output isn't the same as success, it usually just means the thing you're asking about doesn't exist yet, and the useful question is why it doesn't exist rather than why the command didn't work.