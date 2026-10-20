param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateSet('Interpreter','Jit','Aot','All')][string]$Mode='All',
    [string]$BaselineDirectory,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/extended-benchmarks'),
    [int]$Rounds=2,
    [int]$Processor=0,
    [switch]$BuildOnly,
    [switch]$RunOnly
)
$ErrorActionPreference='Stop'
if($BuildOnly -and $RunOnly){throw 'Choose BuildOnly or RunOnly'}
if($Rounds -lt 1){throw 'Rounds must be positive'}
if($Processor -lt -1 -or $Processor -ge [Environment]::ProcessorCount -or $Processor -ge [IntPtr]::Size*8){throw 'Processor must be -1 or an available logical CPU in the current processor group'}
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$sdk=Split-Path (Split-Path $Daslang -Parent) -Parent
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$variants=@([pscustomobject]@{Name='after';Root=$PSScriptRoot})
if($BaselineDirectory){$variants=@([pscustomobject]@{Name='before';Root=(Resolve-Path $BaselineDirectory).Path})+$variants}
if($BaselineDirectory){
    foreach($file in @('benchmark_extended.das','extended_workloads.das')){
        if((Get-FileHash (Join-Path $variants[0].Root "benchmarks/$file")).Hash -ne (Get-FileHash (Join-Path $PSScriptRoot "benchmarks/$file")).Hash){throw 'Before/after benchmark sources must match'}
    }
}
function Stamp($root) {
    $paths=@('lib/reactivex.das','lib/rx_scheduler.das','lib/rx_payload_checks.das','benchmarks/benchmark_extended.das','benchmarks/extended_workloads.das')
    return (($paths | ForEach-Object {$_+':'+(Get-FileHash (Join-Path $root $_)).Hash}) -join "`n")
}
$stamps=@($variants | ForEach-Object {[pscustomobject]@{Variant=$_.Name;Root=$_.Root;Stamp=(Stamp $_.Root)}})
$compilerHash=(Get-FileHash $Daslang).Hash
$stampFile=Join-Path $OutputDirectory 'build-stamp.json'
if($RunOnly) {
    $saved=Get-Content $stampFile | ConvertFrom-Json
    if($saved.CompilerSha256 -ne $compilerHash){throw 'Compiler changed since build'}
    foreach($stamp in $stamps){
        $old=@($saved.Sources | Where-Object {$_.Variant -eq $stamp.Variant})
        if($old.Count -ne 1 -or $old[0].Stamp -cne $stamp.Stamp){throw 'Sources changed since build'}
    }
} elseif($Mode -in @('All','Aot') -or $BuildOnly) {
    foreach($variant in $variants) {
        $build=Join-Path $OutputDirectory ($variant.Name+'-build')
        $log=Join-Path $OutputDirectory ($variant.Name+'-build.log')
        & cmake -S (Join-Path $PSScriptRoot 'benchmarks/aot_host') -B $build -G 'Visual Studio 17 2022' -A x64 "-DDAS_DIR=$sdk/lib/cmake/DAS" "-DRX_ROOT=$($variant.Root)" *> $log
        if($LASTEXITCODE -ne 0){throw "Configure failed: $log"}
        & cmake --build $build --config Release --parallel 2 *>> $log
        if($LASTEXITCODE -ne 0){throw "Build failed: $log"}
    }
}
foreach($stamp in $stamps){if((Stamp $stamp.Root) -cne $stamp.Stamp){throw 'Sources changed during build'}}
if(-not $RunOnly){[ordered]@{CompilerSha256=$compilerHash;Sources=$stamps} | ConvertTo-Json -Depth 5 | Set-Content $stampFile -Encoding UTF8}
if($BuildOnly){Write-Host 'Extended benchmark hosts built; no measurements performed.';exit 0}
function Number($value){if("$value".StartsWith('0x')){return [Convert]::ToInt64("$value".Substring(2),16)};return [int64]$value}
function Median($values){$sorted=@($values | Sort-Object);$middle=[int][Math]::Floor($sorted.Count/2);if($sorted.Count%2 -eq 0){return ($sorted[$middle-1]+$sorted[$middle])/2.0};return $sorted[$middle]}
function Run-BenchmarkProcess([string]$Executable,[string[]]$Arguments,[string]$Log) {
    if(-not (Test-Path -LiteralPath $Executable -PathType Leaf)){throw "Benchmark executable missing; run BuildOnly first: $Executable"}
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable
    foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
    $start.WorkingDirectory=$PSScriptRoot
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $child=[Diagnostics.Process]::new()
    $child.StartInfo=$start
    $started=$false
    try {
        $started=$child.Start()
        if(-not $started){throw "Cannot start benchmark: $Executable"}
        if($Processor -ge 0){$child.ProcessorAffinity=[IntPtr]([int64]1 -shl $Processor)}
        $stdout=$child.StandardOutput.ReadToEndAsync()
        $stderr=$child.StandardError.ReadToEndAsync()
        $child.WaitForExit()
        [IO.File]::WriteAllText($Log,$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        return $child.ExitCode
    } catch {
        if($started -and -not $child.HasExited){$child.Kill($true)}
        throw
    } finally {$child.Dispose()}
}
$modes=if($Mode -eq 'All'){@('Interpreter','Jit','Aot')}else{@($Mode)}
$allRows=[Collections.Generic.List[object]]::new()
$queueRows=[Collections.Generic.List[object]]::new()
# Every child is awaited: no overlapping benchmarks, compilation jobs or tests
# are started by this runner. BuildOnly/RunOnly allow external checks to finish first.
foreach($current in $modes){
    for($round=0;$round -lt $Rounds;$round++){
        $ordered=@($variants)
        if($round%2 -eq 1){[array]::Reverse($ordered)}
        foreach($variant in $ordered){
            $script=Join-Path $variant.Root 'benchmarks/benchmark_extended.das'
            $log=Join-Path $OutputDirectory "$current-$($variant.Name)-$round.log"
            if($current -eq 'Aot'){
                $exe=Join-Path $OutputDirectory "$($variant.Name)-build/Release/rx_extended.exe"
                $code=Run-BenchmarkProcess -Executable $exe -Arguments @($sdk,$script) -Log $log
            } else {
                $arguments=@($script,'-no-module-cache')
                if($current -eq 'Jit'){$arguments+=@('-jit','-jit-no-cache')}
                $code=Run-BenchmarkProcess -Executable $Daslang -Arguments $arguments -Log $log
            }
            if($code -ne 0){throw "Benchmark failed: $log"}
            $text=Get-Content $log
            if($text -notcontains 'ReactiveX extended benchmarks OK'){throw "Missing marker: $log"}
            if($current -eq 'Aot' -and !($text -join "`n").Contains('main->aot=yes, strict linking')){throw 'AOT main/strict linking not checked'}
            $rows=@($text | Where-Object {$_.StartsWith('RXEXT,')} | ConvertFrom-Csv -Header marker,case,implementation,size,sample,elapsed_ns,checksum,allocations,allocated_bytes,string_allocations,string_bytes,retained_bytes)
            if($rows.Count -ne 510){throw "Unexpected sample count: $log"}
            foreach($row in $rows){
                foreach($field in @('size','sample','elapsed_ns','checksum','allocations','allocated_bytes','string_allocations','string_bytes','retained_bytes')){$row.$field=Number $row.$field}
                if($row.retained_bytes -ne 0 -or $row.elapsed_ns -le 0){throw "Invalid sample: $log"}
                $row | Add-Member -NotePropertyName Mode -NotePropertyValue $current
                $row | Add-Member -NotePropertyName Variant -NotePropertyValue $variant.Name
                $row | Add-Member -NotePropertyName Round -NotePropertyValue $round
                $allRows.Add($row)
            }
            foreach($group in ($rows | Group-Object case,size,sample)){
                if($group.Count -ne 2 -or $group.Group[0].checksum -ne $group.Group[1].checksum){throw "Checksum mismatch: $log"}
            }
            $queues=@($text | Where-Object {$_.StartsWith('RXQUEUE,')} | ConvertFrom-Csv -Header marker,case,size,sample,fill_ns,fill_allocations,fill_bytes,fill_live,drain_ns,drain_allocations,drain_bytes,drain_live)
            if($queues.Count -ne 64){throw "Unexpected queue sample count: $log"}
            foreach($queue in $queues){
                foreach($field in @('size','sample','fill_ns','fill_allocations','fill_bytes','fill_live','drain_ns','drain_allocations','drain_bytes','drain_live')){$queue.$field=Number $queue.$field}
                if($queue.fill_ns -le 0 -or $queue.drain_ns -le 0){throw 'Invalid queue timing'}
                if($queue.sample -ge 0){
                    $queue | Add-Member -NotePropertyName Mode -NotePropertyValue $current
                    $queue | Add-Member -NotePropertyName Variant -NotePropertyValue $variant.Name
                    $queue | Add-Member -NotePropertyName Round -NotePropertyValue $round
                    $queueRows.Add($queue)
                }
            }
            Write-Host "$current round $round $($variant.Name): 510 samples OK"
        }
    }
}
foreach($stamp in $stamps){if((Stamp $stamp.Root) -cne $stamp.Stamp){throw 'Sources changed during measurements'}}
$allRows | Export-Csv (Join-Path $OutputDirectory 'samples.csv') -NoTypeInformation -Encoding UTF8
$queueRows | Export-Csv (Join-Path $OutputDirectory 'queue-samples.csv') -NoTypeInformation -Encoding UTF8
foreach($group in ($allRows | Group-Object Mode,Round,case,size,sample)){
    if(@($group.Group.checksum | Select-Object -Unique).Count -ne 1){throw 'Before/after checksum mismatch'}
}
$summary=@(foreach($group in ($allRows | Group-Object Mode,Variant,case,size,implementation)){
    $row=$group.Group[0];$units=4.0*$row.size
    [pscustomobject]@{
        Mode=$row.Mode;Variant=$row.Variant;Case=$row.case;Size=$row.size;Implementation=$row.implementation
        Unit=$(if($row.case -eq 'resubscribe'){'subscription'}elseif($row.case -eq 'zip_queue'){'matched pair'}else{'input event'})
        NsPerUnit=(Median @($group.Group | ForEach-Object {$_.elapsed_ns/$units}))
        MinNsPerUnit=(($group.Group | ForEach-Object {$_.elapsed_ns/$units}) | Measure-Object -Minimum).Minimum
        MaxNsPerUnit=(($group.Group | ForEach-Object {$_.elapsed_ns/$units}) | Measure-Object -Maximum).Maximum
        AllocationsPerUnit=(Median @($group.Group | ForEach-Object {$_.allocations/$units}))
        BytesPerUnit=(Median @($group.Group | ForEach-Object {$_.allocated_bytes/$units}))
        StringAllocationsPerUnit=(Median @($group.Group | ForEach-Object {$_.string_allocations/$units}))
        StringBytesPerUnit=(Median @($group.Group | ForEach-Object {$_.string_bytes/$units}))
    }
})
$queueSummary=@(foreach($group in ($queueRows | Group-Object Mode,Variant,case,size)){
    $row=$group.Group[0]
    [pscustomobject]@{
        Mode=$row.Mode;Variant=$row.Variant;Case=$row.case;Size=$row.size
        FillNsPerItem=(Median @($group.Group | ForEach-Object {$_.fill_ns/$_.size}))
        DrainNsPerItem=(Median @($group.Group | ForEach-Object {$_.drain_ns/$_.size}))
        FillAllocations=(Median @($group.Group.fill_allocations));FillBytes=(Median @($group.Group.fill_bytes))
        DrainAllocations=(Median @($group.Group.drain_allocations));DrainBytes=(Median @($group.Group.drain_bytes))
        LiveBytesAfterFill=(Median @($group.Group.fill_live))
    }
})
[ordered]@{RecordedAt=[DateTimeOffset]::Now.ToString('o');Compiler=$Daslang;CompilerSha256=$compilerHash;Sources=$stamps;Rounds=$Rounds;Sizes=@(32,256,1024);Batches=4;SamplesPerRound=5;Processor=$env:PROCESSOR_IDENTIFIER;ProcessorIndex=$Processor;Results=$summary;QueueResults=$queueSummary} | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $OutputDirectory 'summary.json') -Encoding UTF8
$summary | Where-Object {$_.Size -eq 1024 -and $_.Implementation -eq 'rx'} | Format-Table Mode,Variant,Case,NsPerUnit,AllocationsPerUnit,BytesPerUnit -AutoSize
Write-Host "Extended ReactiveX benchmark reports: $OutputDirectory"
