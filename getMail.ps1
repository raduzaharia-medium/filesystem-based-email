#Requires -Version 7.0
<#
    Mirrors an IMAP account into folders of .eml files:

        <MailRoot>/<account>/<folder>/YYYY-MM-DD [UNREAD] Subject-<uid>.eml

    The file name is the state: [UNREAD] is dropped from the name once the message has been read
    on the server, and the uid at the end says which server message the file is.
    Returns the number of newly downloaded messages.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserName,
    [Parameter(Mandatory)][securestring]$Password,
    [string]$Server,
    [int]$Port = 993,
    [switch]$DeleteFromServer,
    [string]$MailRoot = $PSScriptRoot
)

Import-Module (Join-Path $PSScriptRoot 'mailFiles.psm1') -Force
Import-MailKit

if (-not $Server) { $Server = Get-ImapServer $UserName }
if (-not $Server) { throw "Unknown mail provider for '$UserName'; pass -Server." }

$accountFolder = Join-Path $MailRoot (Get-SafeMailName $UserName)
New-Item -ItemType Directory -Path $accountFolder -Force | Out-Null

$newMailCount = 0
$client = [MailKit.Net.Imap.ImapClient]::new()

try {
    $client.Connect($Server, $Port, [MailKit.Security.SecureSocketOptions]::SslOnConnect)
    $client.Authenticate($UserName, [System.Net.NetworkCredential]::new('', $Password).Password)

    foreach ($folder in $client.GetFolders($client.PersonalNamespaces[0])) {
        if ($folder.Name -eq '[Gmail]') { continue }

        $localFolder = Join-Path $accountFolder (Get-SafeMailName $folder.Name)
        New-Item -ItemType Directory -Path $localFolder -Force | Out-Null

        $access = $DeleteFromServer ? [MailKit.FolderAccess]::ReadWrite : [MailKit.FolderAccess]::ReadOnly
        try { [void]$folder.Open($access) } catch { Write-Warning "Cannot open '$($folder.Name)': $($_.Exception.Message)"; continue }

        # If the server renumbered the folder, the uids in the file names no longer mean anything.
        $known = Get-LocalMailIndex -Folder $localFolder -UidValidity $folder.UidValidity

        $items = [MailKit.MessageSummaryItems]::UniqueId -bor [MailKit.MessageSummaryItems]::Flags -bor [MailKit.MessageSummaryItems]::InternalDate
        $summaries = @($folder.Fetch(0, -1, $items))
        $flaggedForDeletion = 0

        for ($i = 0; $i -lt $summaries.Count; $i++) {
            $summary = $summaries[$i]
            $uid = [uint32]$summary.UniqueId.Id
            $path = $null
            $isRead = ($summary.Flags -band [MailKit.MessageFlags]::Seen) -ne 0
            Write-Progress -Activity $UserName -Status $folder.Name -PercentComplete (100 * ($i + 1) / $summaries.Count)

            if ($known.ContainsKey($uid)) {
                $existing = $known[$uid]
                if ($isRead -and $existing.Name.Contains('[UNREAD]')) {
                    # Read elsewhere since the last run: the file name follows the server.
                    Rename-Item -LiteralPath $existing.FullName -NewName $existing.Name.Replace(' [UNREAD]', '')
                }
                if ($DeleteFromServer -and $existing.Length -gt 0) {
                    [void]$folder.AddFlags($summary.UniqueId, [MailKit.MessageFlags]::Deleted, $true)
                    $flaggedForDeletion++
                }
                continue
            }

            try {
                $message = $folder.GetMessage($summary.UniqueId)
                $name = New-MailFileName -FolderName $folder.Name -Message $message -Summary $summary -Uid $uid -Unread:(-not $isRead)
                $path = Join-Path $localFolder $name
                $message.WriteTo($path)

                if ((Get-Item -LiteralPath $path).Length -eq 0) { throw 'Written file is empty.' }
                $newMailCount++

                if ($DeleteFromServer) {
                    [void]$folder.AddFlags($summary.UniqueId, [MailKit.MessageFlags]::Deleted, $true)
                    $flaggedForDeletion++
                }
            }
            catch {
                # Nothing is deleted from the server unless the copy on disk is complete.
                Write-Warning "Skipping uid $uid in '$($folder.Name)': $($_.Exception.Message)"
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            }
        }

        if ($flaggedForDeletion -gt 0) { $folder.Expunge() }
        $folder.Close()
    }
}
finally {
    Write-Progress -Activity $UserName -Completed
    if ($client.IsConnected) { $client.Disconnect($true) }
    $client.Dispose()
}

return $newMailCount
