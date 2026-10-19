param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit,[switch]$SmokeTest)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$previous=[Environment]::GetEnvironmentVariable('RX_GLFW_SMOKE','Process')
$arguments=@((Join-Path $PSScriptRoot 'examples/glfw_ui_demo.das'),'-no-module-cache')
if($Jit){$arguments+=@('-jit','-jit-no-cache')}
try {
    $env:RX_GLFW_SMOKE=if($SmokeTest){'1'}else{'0'}
    & $Daslang @arguments
    if($LASTEXITCODE -ne 0){throw 'ReactiveX GLFW UI example failed'}
} finally {[Environment]::SetEnvironmentVariable('RX_GLFW_SMOKE',$previous,'Process')}
