param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit,[switch]$Example)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$arguments=@((Join-Path $PSScriptRoot 'support/task_tcp_fixture.py'),'--daslang',$Daslang)
if($Jit){$arguments+='--jit'}
if($Example){$arguments+=@('--script',(Join-Path $PSScriptRoot 'examples/task_tcp_demo.das'))}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'Real TCP Task checks failed'}
