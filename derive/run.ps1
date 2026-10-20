param(
    [string]$Daslang=$env:DASLANG_EXE,
    [switch]$Test,[switch]$Jit,[switch]$AotGenerate,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/aot-generated')
)
$ErrorActionPreference='Stop'
if($Jit -and $AotGenerate){throw 'Choose Jit or AotGenerate'}
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$positive=@(Get-Content (Join-Path $PSScriptRoot 'scripts.json') -Raw|ConvertFrom-Json|Where-Object {$Test -or $_.file.StartsWith('examples/')})
function Check([string]$File,[bool]$Pass,[string]$Marker) {
    $arguments=@((Join-Path $PSScriptRoot $File),'-no-module-cache')
    if($Jit){$arguments+=@('-jit','-jit-no-cache')}
    $output=@(& $Daslang @arguments 2>&1 | ForEach-Object {"$_"})
    $code=$LASTEXITCODE
    if(($code -eq 0) -ne $Pass -or !($output -join "`n").Contains($Marker)) {
        $output | ForEach-Object {Write-Host $_}
        throw "Derive check failed: $File (exit $code)"
    }
    Write-Host "PASS $File"
}
if($AotGenerate) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
    foreach($case in $positive) {
        $cpp=Join-Path $OutputDirectory ([IO.Path]::GetFileNameWithoutExtension($case.file)+'.cpp')
        & $Daslang -aot (Join-Path $PSScriptRoot $case.file) $cpp
        if($LASTEXITCODE -ne 0){throw "Derive AOT generation failed: $($case.file)"}
    }
    Write-Host 'Derive AOT C++ generated; runtime not checked.'
    return
}
if($Test) {
    foreach($case in @(Get-Content (Join-Path $PSScriptRoot 'negative_tests.json') -Raw|ConvertFrom-Json)) {
        Check $case.file $false $case.message
    }
}
foreach($case in $positive){Check $case.file $true $case.marker}
Write-Host 'All derive checks passed.'
