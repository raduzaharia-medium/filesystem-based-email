#Requires -Version 7.0
<#
    Downloads the .NET (netstandard) builds of MailKit, MimeKit and BouncyCastle from nuget.org into ./lib.
    The DLLs that used to be checked in were .NET Framework builds, which PowerShell 7 cannot load.
#>
[CmdletBinding()]
param(
    [string]$MailKitVersion = '4.9.0'
)

$lib = Join-Path $PSScriptRoot 'lib'
New-Item -ItemType Directory -Path $lib -Force | Out-Null
$temp = Join-Path ([IO.Path]::GetTempPath()) "mailkit-$([guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Path $temp | Out-Null

    # Resolve exact dependency versions from each package's own nuspec, so they always match.
    function Get-Dependencies($id, $version) {
        $url = "https://api.nuget.org/v3-flatcontainer/$($id.ToLower())/$version/$($id.ToLower()).nuspec"
        [xml]$nuspec = (Invoke-WebRequest $url).Content -replace '^\uFEFF', ''
        $group = $nuspec.package.metadata.dependencies.group | Where-Object { $_.targetFramework -eq '.NETStandard2.1' }
        $result = @{}
        foreach ($d in $group.dependency) { $result[$d.id] = $d.version -replace '[\[\]\(\),]', '' }
        return $result
    }

    $versions = @{ MailKit = $MailKitVersion }
    (Get-Dependencies 'MailKit' $MailKitVersion).GetEnumerator() | ForEach-Object { $versions[$_.Key] = $_.Value }
    if ($versions['MimeKit']) { (Get-Dependencies 'MimeKit' $versions['MimeKit']).GetEnumerator() | ForEach-Object { $versions[$_.Key] = $_.Value } }

    foreach ($id in 'MailKit', 'MimeKit', 'BouncyCastle.Cryptography') {
        if (-not $versions[$id]) { throw "Could not work out which version of $id MailKit $MailKitVersion needs." }
        $version = $versions[$id]
        $package = Join-Path $temp "$id.zip"
        Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$($id.ToLower())/$version/$($id.ToLower()).$version.nupkg" -OutFile $package
        Expand-Archive $package -DestinationPath (Join-Path $temp $id)
        $dll = 'netstandard2.1', 'netstandard2.0', 'net6.0' |
            ForEach-Object { Join-Path $temp $id 'lib' $_ "$id.dll" } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $dll) { throw "$id $version has no netstandard build." }
        Copy-Item $dll $lib -Force
        Write-Host "$id $version"
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
