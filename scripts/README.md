# Scripts

PowerShell used to build and audit the lab. All scripts include comment-based
help — run `Get-Help .\ScriptName.ps1 -Full`.

| Script | Purpose | Guide reference |
|---|---|---|
| `provisioning/New-LabUsers.ps1` | Bulk user creation from CSV | Part 7 |
| `auditing/Get-PrivilegedGroupMembers.ps1` | Privileged group membership, recursive | Part 10, Query 2 |
| `auditing/Get-StaleAccounts.ps1` | Dormant enabled accounts | Part 10, Query 3 |
| `auditing/Get-PermissiveShareACLs.ps1` | Shares granting broad principals | Part 10, Query 4 |
| `auditing/Invoke-FullAudit.ps1` | Runs all checks, consolidated report | Part 10 |

## Never commit credentials

Use `Read-Host -AsSecureString` or a parameter — never a hardcoded password,
not even a lab one. Git history is permanent: removing a secret in a later
commit does **not** remove it from history. If it happens, rotate the
credential and rewrite history, or start the repo over.
