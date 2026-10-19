param(
    [string]$Daslang=$env:DASLANG_EXE,
    [switch]$Test,
    [switch]$Jit,
    [switch]$AotGenerate,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/aot-generated')
)
$ErrorActionPreference='Stop'
if($Jit -and $AotGenerate){throw 'Choose Jit or AotGenerate'}
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
function Check([string]$File,[bool]$Pass,[string]$Expected) {
    $arguments=@((Join-Path $PSScriptRoot $File),'-no-module-cache')
    if($Jit){$arguments+=@('-jit','-jit-no-cache')}
    $output=@(& $Daslang @arguments 2>&1 | ForEach-Object {"$_"})
    $code=$LASTEXITCODE
    if(($code -eq 0) -ne $Pass -or !($output -join "`n").Contains($Expected)){
        $output | ForEach-Object {Write-Host $_}
        throw "ReactiveX check failed: $File (exit $code)"
    }
    Write-Host "PASS $File"
}
$positive=@(& (Join-Path $PSScriptRoot 'scripts.ps1') -IncludeTests:$Test)
if($AotGenerate){
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    foreach($file in $positive){
        $target=Join-Path $OutputDirectory (([IO.Path]::GetFileNameWithoutExtension($file))+'.cpp')
        $output=& $Daslang -aot (Join-Path $PSScriptRoot $file) $target 2>&1
        if($LASTEXITCODE -ne 0){$output;throw "AOT generation failed: $file"}
        Write-Host "GENERATED $file"
    }
    Write-Host 'ReactiveX AOT C++ generation passed (runtime not checked).'
    exit 0
}
if($Test){
    Check 'tests/failed_move_payload.das' $false 'broadcast elements must be copyable'
    Check 'tests/failed_borrowed_payload.das' $false 'payload must own its data'
    Check 'tests/failed_merge_payload_type.das' $false 'no matching functions or generics'
    Check 'tests/failed_concat_payload_type.das' $false 'no matching functions or generics'
    Check 'tests/failed_task_move_payload.das' $false 'broadcast elements must be copyable'
    Check 'tests/failed_catch_payload_type.das' $false 'no matching functions or generics'
    Check 'tests/failed_window_retention.das' $false 'payload must own its data'
    Check 'tests/failed_group_by_key.das' $false 'payload must own its data'
    Check 'tests/failed_dematerialize_type.das' $false 'no matching functions or generics'
    Check 'tests/failed_materialize_payload.das' $false 'payload must own its data'
    Check 'tests/failed_pairwise_buffer.das' $false 'map borrowed buffer batches to a copyable value'
    Check 'tests/failed_buffer_retention.das' $false 'map borrowed buffer batches to a copyable value'
    Check 'tests/failed_async_sequence_move_payload.das' $false 'broadcast elements must be copyable'
}
# End on a successful native call so CI does not inherit a negative-test exit.
foreach($file in $positive){Check $file $true 'ReactiveX'}
Write-Host 'All ReactiveX checks passed.'
