param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateRange(100,600000)][int]$TimeoutMs=15000,
    [switch]$Jit
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$arguments=@((Join-Path $PSScriptRoot 'support/task_keyboard_console.py'),
    '--daslang',$Daslang,'--script',(Join-Path $PSScriptRoot 'examples/task_keyboard_demo.das'),
    '--timeout-ms',"$TimeoutMs")
if($Jit){$arguments+='--jit'}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Interactive Task keyboard demo failed'}
