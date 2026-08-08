<#
.SYNOPSIS
    Bulk-provisions Active Directory users from a CSV file.

.DESCRIPTION
    Reads user records from CSV and creates corresponding AD accounts in
    department-based OUs. Adds each user to the appropriate global security
    group per the AGDLP model.

    The script is idempotent: existing accounts are skipped rather than
    causing an error, so it is safe to re-run.

    It also rolls back partial failures. New-ADUser writes the account object
    before applying the password, so a rejected password leaves an unusable
    account behind that a later run would then skip as "already exists". On
    failure this script removes the orphaned object so the directory does not
    accumulate broken accounts.

    A per-account result log is written to CSV for audit purposes.

.PARAMETER CsvPath
    Path to the source CSV. Required columns: FirstName, LastName, Department,
    Title. Department values must exactly match an existing OU name and an
    existing GG- group name.

.PARAMETER LogPath
    Path for the output log. Defaults to .\provisioning-log.csv

.EXAMPLE
    .\New-LabUsers.ps1

.EXAMPLE
    .\New-LabUsers.ps1 -CsvPath .\users.csv -LogPath .\run1.csv

.NOTES
    Author:   Angelos Isaac
    Version:  1.2
    Requires: ActiveDirectory module, rights to create users in the target OUs
#>

param(
    [string]$CsvPath = ".\users.csv",
    [string]$LogPath = ".\provisioning-log.csv"
)

$domain = "DC=corp,DC=isaacsolutions,DC=lab"
$defaultPassword = Read-Host -AsSecureString "Temporary password for new accounts"
$log = @()

Import-Csv $CsvPath | ForEach-Object {
    $first = $_.FirstName
    $last  = $_.LastName
    $dept  = $_.Department
    $title = $_.Title

    # SamAccountName has a hard 20-character limit in AD
    $sam = ($first.Substring(0,1) + $last).ToLower()
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }
    $upn    = "$sam@corp.isaacsolutions.lab"
    $ouPath = "OU=$dept,OU=IS-Users,$domain"

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $log += [PSCustomObject]@{User=$sam; Status="SKIPPED"; Detail="Already exists"}
        return
    }

    try {
        New-ADUser `
            -Name "$first $last" `
            -GivenName $first `
            -Surname $last `
            -SamAccountName $sam `
            -UserPrincipalName $upn `
            -DisplayName "$first $last" `
            -Title $title `
            -Department $dept `
            -Path $ouPath `
            -AccountPassword $defaultPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop

        Add-ADGroupMember -Identity "GG-$dept" -Members $sam -ErrorAction Stop
        $log += [PSCustomObject]@{User=$sam; Status="CREATED"; Detail=$ouPath}
    }
    catch {
        # Roll back a partially created object so the next run does not skip it
        $msg = $_.Exception.Message
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            Remove-ADUser -Identity $sam -Confirm:$false -ErrorAction SilentlyContinue
            $log += [PSCustomObject]@{User=$sam; Status="FAILED"; Detail="$msg [partial object rolled back]"}
        }
        else {
            $log += [PSCustomObject]@{User=$sam; Status="FAILED"; Detail=$msg}
        }
    }
}

$log | Format-Table -AutoSize
$log | Export-Csv $LogPath -NoTypeInformation

Write-Host "`\nSummary:" -ForegroundColor Cyan
$log | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize
