param([string]$Daslang = $env:DASLANG_EXE, [switch]$Test)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'type_providers/run.ps1') -Daslang $Daslang -Test:$Test
& (Join-Path $PSScriptRoot 'computation_expressions/run_computation.ps1') -Daslang $Daslang -Test:$Test
Write-Host 'Both libraries passed.'