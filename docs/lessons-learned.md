# Lessons learned


## What surprised me

**LAPS took over an account I had set myself.** When I built FS01 I set the Administrator password during Windows Server setup. After joining the domain, that password stopped working and I had to look up the real one with `Get-LapsADPassword`. I had configured LAPS a phase earlier and understood what it did, but seeing it silently replace a password I chose was different
from reading about it. Windows then wouldn't let me change it back, which also makes sense once you think about it — if I set it manually, the machine and AD would be holding different values and anyone querying the directory would get a password that doesn't work. The account isn't mine anymore.

**My own password policy blocked me from planting a finding.** For the audit exercise I tried to create a service account with a deliberately weak password, and the domain rejected it. The 14-character minimum I set in the Group Policy phase was doing exactly what it was supposed to do, which meant "weak service account password" couldn't be one of my findings — the condition can't exist. That made the difference between preventive and detective controls concrete in a way I hadn't really thought about before. Policy stops the bad state from happening at all; the access review only finds bad states that policy allows, like excessive group membership or a non-expiring password.

**`New-SmbShare` said it worked when it hadn't.** 
Before I added a data disk to FS01, `D:` was still the CD-ROM drive with the Windows ISO mounted. Creating the share folders failed with access denied, which is correct because an ISO is read-only. But then `New-SmbShare` ran anyway and returned a formatted table showing the share names and paths as though everything was fine. `Test-Path` returned False for all three. I had three shares registered against folders that didn't exist. This was the third time in the build that a command's own output told me something different from what the system actually looked like.