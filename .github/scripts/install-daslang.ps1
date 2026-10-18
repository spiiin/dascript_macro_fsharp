param([Parameter(Mandatory)][string]$Destination)

$ErrorActionPreference = 'Stop'
$version = '0.6.5-RC2'
# This release contains merge 34cb1e7def64418dd447c117671812692619cdf4 (PR #4259).
$sha256 = '519dccb27822f6d43196d5e48e9432549a5825f3782de09c368dadb5b1568070'
$url = "https://github.com/GaijinEntertainment/daScript/releases/download/v$version/daslang-bundle-windows-x86_64.zip"
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$archive = Join-Path $Destination 'sdk.zip'
$sdk = Join-Path $Destination 'sdk'

# Verify the pinned release before extracting or executing anything from it.
Invoke-WebRequest -Uri $url -OutFile $archive
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $sha256) {
    throw 'Daslang SDK checksum mismatch.'
}
Expand-Archive -LiteralPath $archive -DestinationPath $sdk -Force
$executable = Join-Path $sdk 'daslang_bundle/bin/daslang.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Daslang SDK has an unexpected layout: $executable is missing."
}
# The caller chooses whether to persist this path in GITHUB_ENV.
Write-Output $executable
