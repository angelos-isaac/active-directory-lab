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
---

## FL-004 — Sysmon GPO deployment: five failures, every one silent

**Phase:** Part 11, Logging and detection  ·  **Systems:** DC01, WKS01, WKS02  ·  **Time lost:** ~2 hours

**Symptom**

Created a GPO to deploy Sysmon via a startup script, linked it to both `IS-Computers` and `Domain Controllers`, verified both links, and rebooted. `Get-Service Sysmon64` returned nothing. No error anywhere, on any machine.

**Investigation**

- Confirmed the GPO was applying with `gpresult /r /scope:computer`. It was listed under Applied Group Policy Objects.
- Ran the install command manually with the same UNC path and it worked immediately, which ruled out the binary, the config file, and permissions.
- Checked `Get-ExecutionPolicy -List` on WKS01. Every scope showed `Undefined`, which reads as "no restriction" and is not. With nothing explicitly set, the effective policy falls back to the OS default, and on Windows 11 client that is `Restricted`. `Get-ExecutionPolicy` on its own confirmed it.
- Fixed that via GPO, rebooted, still nothing.
- Checked the script file itself. It was still the original 215-byte version without the logging I had added — the edit had never saved.
- Wrote the logging version, rebooted, still no log file.
- Checked what the GPO actually had attached:

      ([xml](Get-GPOReport -Name "Sysmon Deployment" -ReportType Xml)).GPO.Computer.ExtensionData.Extension.Script

  The Command field read `SYSMON DEPLOYMENT`. I had put the GPO's own name in the Script Name field instead of `powershell.exe`.
- Corrected that, rebooted, still nothing. The reboot had run cached policy from before the change.

**Root cause**

Five separate problems, none of which produced an error message:

1. Execution policy `Restricted` on Windows 11 clients blocked `.ps1` execution entirely.
2. The script file on SYSVOL was never updated with the logging version.
3. A diagnostic I ran — `Test-Path` to SYSVOL from WKS02 — failed for an unrelated reason. The machine was logged in as a local account with no domain identity, so it could not authenticate to SYSVOL. Startup scripts run as SYSTEM using the computer account and were never affected. This sent me down a false path.
4. The GPO's Script Name field contained the GPO's name rather than an executable, so Windows tried to run a program that does not exist.
5. Cached policy ran on reboot before the corrected version had been pulled.

**Resolution**

The diagnostic that finally worked was startup script duration in the Group Policy operational log:

    Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational" |
      Where-Object { $_.Id -in 4018,5018 }

A duration of 0 seconds means the executable never launched. Three to five seconds means it ran. That single number distinguished "did not execute" from "executed and failed" and was the only signal that reliably told me which problem I was looking at.

After correcting all five, the script still did not run. I stopped there and installed Sysmon manually on all four endpoints to unblock the detection work, which was the actual objective.

**What I learned**

Group Policy script deployment has an unusually long chain of things that must all be correct, and almost none of them report failure. The GPO can be linked and applying while the script never executes. The script can execute while doing nothing. The file can exist while being the wrong version.

Two things I would do differently. Put logging in the script from the first version rather than adding it after something breaks, because a script that writes a line before it does anything turns a silent failure into a visible one. And check the GPO's actual XML rather than the GUI, since the report shows what Windows will really execute.

The wider lesson is about timeboxing. Five failures in, the deployment mechanism was no longer the thing I was trying to build. Installing manually and writing this up was worth more than another hour of debugging, and knowing when to take the working path is a real decision rather than giving up.

---

## FL-005 — Custom Wazuh rule loaded cleanly and matched nothing

**Phase:** Part 11, Detection engineering  ·  **Systems:** SIEM01  ·  **Time lost:** ~45 min

**Symptom**

Wrote a custom rule to detect local account creation via `net.exe`, added it to `local_rules.xml`, and re-ran the technique. No alerts with that rule ID. No errors anywhere.

**Investigation**

- Searched the dashboard for `100100` and got nothing. Searching `rule.id:100100` also returned nothing, so it was not a query syntax problem.
- Checked the manager status. Uptime read 4 hours 18 minutes — from the original install. **The manager had never been restarted, so the rule file had never been read.**
- Restarted it. It failed to start:

      wazuh-analysisd: ERROR: (5107): Syntax error on tag 'win.eventdata.commandLine' in rule 100100

  The forward slash in `user.*\/add` was escaped in PCRE style, which Wazuh's default regex engine does not accept.
- Fixed that, validated with `wazuh-analysisd -t`, restarted successfully. Re-ran the technique. Still no alerts.
- Checked `local_rules.xml` again. It was the default file — my edit had never saved. Rewrote it programmatically rather than through the editor.
- Validated, restarted, re-ran. Still nothing, and this time everything checked out: rule present, ruleset validating, manager uptime in seconds.

**Root cause**

Four problems in sequence, of which the last is the interesting one:

1. The manager was never restarted, so the rule was never loaded.
2. A `nano` edit did not save, so the file was unchanged.
3. An escaped forward slash produced a syntax error under OS_Regex.
4. **The rule was syntactically valid and matched nothing, because Wazuh uses OS_Regex by default rather than PCRE2.** Patterns written with PCRE2 habits load without error and never fire.

**Resolution**

Read Wazuh's own shipped ruleset to see how its authors write the same kind of rule:

    sudo head -30 /var/ossec/ruleset/rules/0800-sysmon_id_1.xml

Every field in that file carries `type="pcre2"`. Adding that attribute to both fields made the rule work:

    <field name="win.eventdata.image" type="pcre2">(?i)\\net1?\.exe$</field>
    <field name="win.eventdata.commandLine" type="pcre2">(?i)user\s+/add</field>

Re-ran the technique and got two hits, 100 milliseconds apart — `net.exe` and `net1.exe`.

**What I learned**

The dangerous failure here is the fourth one. A rule that fails to parse tells you immediately, because the manager will not start. A rule that parses and matches nothing tells you nothing at all, and an empty dashboard looks exactly the same as an absence of malicious activity. In a real environment that is the difference between a detection you have and a detection you think you have.

What solved it was reading the shipped ruleset instead of guessing at syntax. Any rule engine ships with working examples, and those examples are version-accurate by definition in a way that documentation and blog posts are not.

The other thing worth recording is that three of these four failures were not about detection logic at all. The rule was correct fairly early; the manager had not restarted, and then the file had not saved. Config changes need the thing that reads them to actually re-read them, and "no alert" almost never means "the logic is wrong" on the first check.
