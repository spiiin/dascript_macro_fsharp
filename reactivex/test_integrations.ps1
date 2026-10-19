param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$arguments=@((Join-Path $PSScriptRoot 'tests/test_glfw_ui.das'),'-no-module-cache')
if($Jit){$arguments+=@('-jit','-jit-no-cache')}
& $Daslang @arguments
if($LASTEXITCODE -ne 0){throw 'ReactiveX GLFW checks failed'}
& (Join-Path $PSScriptRoot 'run_glfw_ui.ps1') -Daslang $Daslang -Jit:$Jit -SmokeTest
$previousTemp=[Environment]::GetEnvironmentVariable('TEMP','Process')
$previousTmp=[Environment]::GetEnvironmentVariable('TMP','Process')
try {
    $tempDirectory=Join-Path $PSScriptRoot '.work/integration-temp'
    New-Item -ItemType Directory -Force $tempDirectory | Out-Null
    $env:TEMP=[IO.Path]::GetFullPath($tempDirectory);$env:TMP=$env:TEMP
    $arguments=@((Join-Path $PSScriptRoot '../computation_expressions/support/task_hv_fixture.py'),'--daslang',$Daslang,'--script',(Join-Path $PSScriptRoot 'tests/test_websocket_echo.das'))
    if($Jit){$arguments+='--jit'}
    & python @arguments
    if($LASTEXITCODE -ne 0){throw 'ReactiveX WebSocket checks failed'}
} finally {
    [Environment]::SetEnvironmentVariable('TEMP',$previousTemp,'Process')
    [Environment]::SetEnvironmentVariable('TMP',$previousTmp,'Process')
}
& (Join-Path $PSScriptRoot 'run_websocket_echo.ps1') -Daslang $Daslang -Jit:$Jit
Write-Host 'All ReactiveX integration checks passed.'
