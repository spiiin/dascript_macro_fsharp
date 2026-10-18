param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit,[switch]$Example,[switch]$AndBind)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$arguments=@((Join-Path $PSScriptRoot 'support/task_hv_fixture.py'),'--daslang',$Daslang)
if($Jit){$arguments+='--jit'}
if($Example -or $AndBind){
    $script=if($Example){
        if($AndBind){'examples/task_hv_and_bind_demo.das'}else{'examples/task_hv_demo.das'}
    }else{'tests/test_task_hv_and_bind.das'}
    $arguments+=@('--script',(Join-Path $PSScriptRoot $script))
}
& python @arguments
if($LASTEXITCODE -ne 0){throw 'dasHV WebSocket Task checks failed'}
