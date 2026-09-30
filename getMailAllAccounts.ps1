#Requires -Version 7.0
<#
    Syncs every account listed in accounts.json and reports the unread count.
    Passwords are never stored here: each account names an environment variable
    (passwordEnv); if it is not set you are prompted.
#>
[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot 'accounts.json'),
    [string]$MailRoot = $PSScriptRoot,
    [switch]$Console
)

Import-Module (Join-Path $PSScriptRoot 'mailFiles.psm1') -Force

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "No $ConfigFile. Copy accounts.example.json to accounts.json and edit it."
}

$ignoredFolders = 'Junk', 'Spam', 'Bulk', 'Bulk Mail', 'Trash', 'Deleted', 'Deleted Items', 'Notes'
$summary = [System.Collections.Generic.List[string]]::new()

foreach ($account in Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json) {
    $plain = if ($account.passwordEnv) { [Environment]::GetEnvironmentVariable($account.passwordEnv) }
    $password = if ($plain) { ConvertTo-SecureString $plain -AsPlainText -Force } else { Read-Host "Password for $($account.user)" -AsSecureString }

    $params = @{ UserName = $account.user; Password = $password; MailRoot = $MailRoot; DeleteFromServer = [bool]$account.deleteFromServer }
    if ($account.server) { $params.Server = $account.server }

    try { & (Join-Path $PSScriptRoot 'getMail.ps1') @params | Out-Null }
    catch { Write-Warning "$($account.user): $($_.Exception.Message)" }

    $folder = Join-Path $MailRoot (Get-SafeMailName $account.user)
    $unread = 0
    if (Test-Path -LiteralPath $folder) {
        $unread = @(Get-ChildItem -LiteralPath $folder -Filter '*.eml' -File -Recurse |
                Where-Object { $_.Name.Contains('[UNREAD]') -and $_.Directory.Name -notin $ignoredFolders }).Count
    }
    if ($unread -gt 0) { $summary.Add("$($account.user): $unread") }
}

if ($summary.Count -gt 0) {
    if (-not $Console -and $IsWindows -and (Get-Module -ListAvailable BurntToast)) {
        Import-Module BurntToast
        New-BurntToastNotification -Text 'Unread mail', ($summary -join "`n")
    }
    else {
        Write-Host "Unread mail`n$($summary -join "`n")"
    }
}
