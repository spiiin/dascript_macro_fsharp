param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
$Destination=[IO.Path]::GetFullPath($Destination)
if(Test-Path -LiteralPath $Destination){throw 'Destination must be a new directory'}
New-Item -ItemType Directory -Path (Join-Path $Destination 'lib') -Force|Out-Null
foreach($name in @('derive.das','derive_runtime.das','derive_validation.das','derive_json_runtime.das','derive_types.das','derive_variant_macros.das','derive_diff.das','derive_patch.das','derive_builder.das','derive_schema.das','derive_optics.das','derive_optics_runtime.das')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "lib/$name") -Destination (Join-Path $Destination 'lib')
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VALIDATION.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'JSON.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CLONE.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'DIFF.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PATCH.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BUILDER.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SCHEMA.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'OPTICS.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PRISM.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'examples') -Destination $Destination -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'repros') -Destination $Destination -Recurse
[ordered]@{Name='derive';Modules=@('derive.das','derive_runtime.das','derive_validation.das','derive_json_runtime.das','derive_types.das','derive_variant_macros.das','derive_diff.das','derive_patch.das','derive_builder.das','derive_schema.das','derive_optics.das','derive_optics_runtime.das');NativeModules=@();Sdk='0.6.5-RC2'}|ConvertTo-Json|Set-Content (Join-Path $Destination 'manifest.json')
Write-Host "Exported standalone derive library: $Destination"
