#Requires -Version 7.0
<#
    Helpers for the filesystem mail mirror. See getMail.ps1 for the naming convention.
#>

Set-StrictMode -Version Latest

function Import-MailKit {
    <# Loads MailKit from ./lib (see README for how to get the netstandard build). #>
    if ('MailKit.Net.Imap.ImapClient' -as [type]) { return }

    $lib = Join-Path $PSScriptRoot 'lib'
    foreach ($dll in 'BouncyCastle.Cryptography', 'MimeKit', 'MailKit') {
        $path = Join-Path $lib "$dll.dll"
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing $path. Run ./installMailKit.ps1 first."
        }
        Add-Type -Path $path
    }
}

function Get-ImapServer {
    param([Parameter(Mandatory)][string]$UserName)
    switch -Regex ($UserName) {
        '@(outlook|hotmail|live)\.com$' { return 'outlook.office365.com' }
        '@gmail\.com$' { return 'imap.gmail.com' }
        '@yahoo\.com$' { return 'imap.mail.yahoo.com' }
    }
    return $null
}

function Get-SafeMailName {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    $safe = ($Name -replace '[\\/:*?"<>|\x00-\x1f]', '-').Trim().TrimEnd('.')
    if (-not $safe) { return '_' }
    return $safe
}

function Get-LocalMailIndex {
    <#
        Returns @{ uid = FileInfo } for the messages already in a local folder.
        The folder remembers the server's UIDVALIDITY in a small marker file. If it changed, the
        uids in the file names no longer mean anything, so the existing files are moved into a
        _stale-uidvalidity-<old> subfolder (kept, never deleted) and the folder is downloaded afresh.
    #>
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][uint32]$UidValidity
    )

    $marker = Join-Path $Folder '.uidvalidity'
    $stored = if (Test-Path -LiteralPath $marker) { (Get-Content -LiteralPath $marker -Raw).Trim() } else { $null }

    if ($stored -and $stored -ne "$UidValidity") {
        $stale = Join-Path $Folder "_stale-uidvalidity-$stored"
        Write-Warning "UIDVALIDITY of '$Folder' changed ($stored -> $UidValidity); moving existing files to '$stale'."
        New-Item -ItemType Directory -Path $stale -Force | Out-Null
        Get-ChildItem -LiteralPath $Folder -Filter '*.eml' -File | Move-Item -Destination $stale
    }
    if ("$stored" -ne "$UidValidity") { Set-Content -LiteralPath $marker -Value $UidValidity }

    $index = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.eml' -File) {
        # ...Subject-123.eml  or, for trash-like folders, 123.eml. Anchoring avoids "5" matching "15".
        if ($file.Name -match '(?:^|-)(\d+)\.eml$') { $index[[uint32]$Matches[1]] = $file }
    }
    return $index
}

function New-MailFileName {
    param(
        [Parameter(Mandatory)][string]$FolderName,
        [Parameter(Mandatory)]$Message,
        [Parameter(Mandatory)]$Summary,
        [Parameter(Mandatory)][uint32]$Uid,
        [switch]$Unread
    )

    if ($FolderName -in 'Deleted', 'Notes', 'Trash') { return "$Uid.eml" }

    $date = $Message.Date
    if ($date.Year -lt 1990) { $date = $Summary.InternalDate ?? [datetimeoffset]::Now }

    $subject = Get-SafeMailName ($Message.Subject ?? '')
    if (-not $subject -or $subject -eq '_') { $subject = '(no subject)' }
    if ($subject.Length -gt 100) { $subject = $subject.Substring(0, 100).TrimEnd() }

    $tag = $Unread ? ' [UNREAD] ' : ' '
    return '{0}{1}{2}-{3}.eml' -f $date.ToString('yyyy-MM-dd'), $tag, $subject, $Uid
}

Export-ModuleMember -Function *
