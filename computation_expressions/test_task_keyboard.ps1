param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$arguments=@((Join-Path $PSScriptRoot 'support/task_keyboard_fixture.py'),'--daslang',$Daslang)
if($Jit){$arguments+='--jit'}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Task keyboard checks failed'}
