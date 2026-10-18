param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateRange(1,600000)][int]$TimeoutMs=15000,
    [switch]$Jit,
    [switch]$SmokeTest
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$previousGlfwTimeout=[Environment]::GetEnvironmentVariable('CE_GLFW_TIMEOUT_MS','Process')
$previousGlfwSmoke=[Environment]::GetEnvironmentVariable('CE_GLFW_SMOKE','Process')
$arguments=@((Join-Path $PSScriptRoot 'examples/task_glfw_keyboard_demo.das'),'-no-module-cache')
if($Jit){$arguments+=@('-jit','-jit-no-cache')}
try {
    $env:CE_GLFW_TIMEOUT_MS="$TimeoutMs"
    $env:CE_GLFW_SMOKE=if($SmokeTest){'1'}else{'0'}
    & $Daslang @arguments
    if($LASTEXITCODE -ne 0){throw 'GLFW keyboard example failed'}
} finally {
    [Environment]::SetEnvironmentVariable('CE_GLFW_TIMEOUT_MS',$previousGlfwTimeout,'Process')
    [Environment]::SetEnvironmentVariable('CE_GLFW_SMOKE',$previousGlfwSmoke,'Process')
}
