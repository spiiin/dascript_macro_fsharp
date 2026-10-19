param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateSet('Interpreter','Jit','Aot','All')][string]$Mode='All',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/benchmarks'),
    [int]$Parallel=2
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
function Number($value) {
    if("$value".StartsWith('0x')){return [Convert]::ToInt64("$value".Substring(2),16)}
    return [int64]$value
}
function Median($values) {
    $sorted=@($values | Sort-Object)
    return $sorted[[int][Math]::Floor($sorted.Count/2)]
}
$modes=if($Mode -eq 'All'){@('Interpreter','Jit','Aot')}else{@($Mode)}
foreach($current in $modes) {
    $directory=Join-Path $OutputDirectory $current.ToLowerInvariant()
    New-Item -ItemType Directory -Force $directory | Out-Null
    $watch=[Diagnostics.Stopwatch]::StartNew()
    if($current -eq 'Aot') {
        # Reuse the strict runtime host; this manifest contains only the benchmark.
        & (Join-Path $PSScriptRoot 'run_aot.ps1') -Daslang $Daslang -Scripts @('benchmarks/benchmark_reactivex.das') -OutputDirectory (Join-Path $directory 'runtime') -Parallel $Parallel *> (Join-Path $directory 'build.log')
        if($LASTEXITCODE -ne 0){throw "AOT benchmark build/runtime failed: $directory/build.log"}
        $raw=@(Get-Content -LiteralPath (Join-Path $directory 'runtime/benchmark_reactivex.runtime.log'))
    } else {
        $arguments=@((Join-Path $PSScriptRoot 'benchmarks/benchmark_reactivex.das'),'-no-module-cache')
        if($current -eq 'Jit'){$arguments+=@('-jit','-jit-no-cache')}
        $raw=@(& $Daslang @arguments 2>&1 | ForEach-Object {"$_"})
        if($LASTEXITCODE -ne 0){$raw | Set-Content (Join-Path $directory 'raw.log');throw "$current benchmark failed"}
    }
    $watch.Stop()
    $raw | Set-Content -LiteralPath (Join-Path $directory 'raw.log') -Encoding UTF8
    if($raw -notcontains 'ReactiveX benchmarks OK'){throw 'Missing benchmark success marker'}
    $rows=@($raw | Where-Object {$_.StartsWith('RXBENCH,')} | ConvertFrom-Csv -Header marker,case,implementation,size,sample,elapsed_ns,checksum,allocations,allocated_bytes,string_allocations,string_bytes,retained_bytes)
    if($rows.Count -ne 690){throw 'Unexpected benchmark sample count'}
    foreach($row in $rows){
        foreach($field in @('size','sample','elapsed_ns','checksum','allocations','allocated_bytes','string_allocations','string_bytes','retained_bytes')){$row.$field=Number $row.$field}
        if($row.retained_bytes -ne 0 -or $row.elapsed_ns -le 0){throw 'Invalid timing or retained heap growth'}
    }
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $directory 'samples.csv')
    $summary=foreach($group in ($rows | Group-Object case,size,implementation)) {
        $first=$group.Group[0]
        $units=4.0*$first.size*$(if($first.case -eq 'reentrant_burst'){9}else{1})
        $counterpart=@($rows | Where-Object {$_.case -eq $first.case -and $_.size -eq $first.size -and $_.implementation -ne $first.implementation})
        foreach($row in $group.Group){if($row.checksum -ne ($counterpart | Where-Object {$_.sample -eq $row.sample}).checksum){throw 'Checksum mismatch'}}
        [pscustomobject]@{
            Case=$first.case;Size=$first.size;Implementation=$first.implementation
            Unit=$(if($first.case -eq 'construct'){'chain'}elseif($first.case.StartsWith('subscribe') -or $first.case.EndsWith('_subscribe')){'subscription'}else{'input event'})
            NsPerUnit=Median @($group.Group | ForEach-Object {$_.elapsed_ns/$units})
            MinNsPerUnit=($group.Group | ForEach-Object {$_.elapsed_ns/$units} | Measure-Object -Minimum).Minimum
            MaxNsPerUnit=($group.Group | ForEach-Object {$_.elapsed_ns/$units} | Measure-Object -Maximum).Maximum
            AllocationsPerUnit=Median @($group.Group | ForEach-Object {$_.allocations/$units})
            BytesPerUnit=Median @($group.Group | ForEach-Object {$_.allocated_bytes/$units})
            StringAllocationsPerUnit=Median @($group.Group | ForEach-Object {$_.string_allocations/$units})
            StringBytesPerUnit=Median @($group.Group | ForEach-Object {$_.string_bytes/$units})
            RetainedBytes=0
        }
    }
    $sources=@(Get-ChildItem (Join-Path $PSScriptRoot 'benchmarks') -Filter '*.das')+@(Get-ChildItem (Join-Path $PSScriptRoot 'lib') -Filter '*.das')
    [ordered]@{
        RecordedAt=[DateTimeOffset]::Now.ToString('o');Mode=$current;Compiler=$Daslang
        CompilerSha256=(Get-FileHash -LiteralPath $Daslang).Hash
        Processor=$env:PROCESSOR_IDENTIFIER;OperatingSystem=[Environment]::OSVersion.VersionString
        Sizes=@(32,512,4096);Batches=4;Samples=5;Warmup='one pair of size=7,batches=2 per case'
        ProcessAndBuildMs=$watch.Elapsed.TotalMilliseconds
        AllocationScope='Cumulative daScript heap and string heap counters; excludes native allocator, OS, LLVM and compilation. RetainedBytes is net live daScript heap, not allocated bytes.'
        SourceHashes=@($sources | ForEach-Object {[pscustomobject]@{File=$_.FullName;Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
        Results=@($summary)
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $directory 'summary.json') -Encoding UTF8
    $summary | Where-Object {$_.Size -eq 4096} | Format-Table Case,Implementation,NsPerUnit,AllocationsPerUnit,BytesPerUnit -AutoSize
}
Write-Host "ReactiveX benchmark reports: $OutputDirectory"
