param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateRange(1,1000000)][int]$Elements=512,
    [ValidateRange(1,10000)][int]$Batches=4,
    [ValidateRange(3,101)][int]$Samples=7,
    [ValidateRange(1,100000)][int]$Work=32,
    [switch]$Jit,
    [string]$SourceRoot=$PSScriptRoot,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/async-benchmarks')
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$SourceRoot=(Resolve-Path -LiteralPath $SourceRoot).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$arguments=@((Join-Path $SourceRoot 'benchmarks/benchmark_async_sequence.das'),'-no-module-cache')
if($Jit){$arguments+=@('-jit','-jit-no-cache')}
$arguments+=@('--','--elements',"$Elements",'--batches',"$Batches",'--samples',"$Samples",'--work',"$Work")
$watch=[Diagnostics.Stopwatch]::StartNew()
$output=@(& $Daslang @arguments 2>&1 | ForEach-Object {"$_"})
$code=$LASTEXITCODE
$watch.Stop()
$output | Set-Content -LiteralPath (Join-Path $OutputDirectory 'raw.log') -Encoding UTF8
if($code -ne 0 -or $output -notcontains 'Async sequence benchmarks OK'){throw "Benchmark failed; see $OutputDirectory/raw.log"}
$rows=@($output | Where-Object {$_.StartsWith('ASYNC,')} | ConvertFrom-Csv -Header marker,case,implementation,sample,elements,batches,work,pending,elapsed_ns,checksum,allocations,allocated_bytes,retained_bytes)
if($rows.Count -ne 5*2*2*2*$Samples){throw 'Unexpected sample count'}
foreach($row in $rows) {
    if([int64]$row.retained_bytes -ne 0 -or [int64]$row.elapsed_ns -le 0 -or [int]$row.elements -ne $Elements -or [int]$row.batches -ne $Batches){throw 'Invalid sample or retained heap growth'}
}
$rows | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'samples.csv') -NoTypeInformation -Encoding UTF8
function Median($values) {
    $sorted=@($values | Sort-Object)
    $middle=[int][Math]::Floor($sorted.Count/2)
    if($sorted.Count%2){return $sorted[$middle]}
    return ($sorted[$middle-1]+$sorted[$middle])/2.0
}
$items=[double]$Elements*$Batches
$summary=foreach($workSize in @(0,$Work)) {
    foreach($pending in @(0,1)) {
        foreach($name in @('next','for','zip','and_bind','move')) {
            $ce=@($rows | Where-Object {$_.case -eq $name -and [int]$_.work -eq $workSize -and [int]$_.pending -eq $pending -and $_.implementation -eq 'ce'} | Sort-Object {[int]$_.sample})
            $manual=@($rows | Where-Object {$_.case -eq $name -and [int]$_.work -eq $workSize -and [int]$_.pending -eq $pending -and $_.implementation -eq 'manual'} | Sort-Object {[int]$_.sample})
            $ratios=for($i=0;$i -lt $Samples;$i++) {
                if($ce[$i].checksum -ne $manual[$i].checksum){throw 'Checksum mismatch'}
                [double]$ce[$i].elapsed_ns/[double]$manual[$i].elapsed_ns
            }
            foreach($pair in @(@('ce',$ce),@('manual',$manual))) {
                $data=$pair[1]
                $times=@($data | ForEach-Object {[double]$_.elapsed_ns/$items})
                [pscustomobject]@{
                    Case=$name;Implementation=$pair[0];Work=$workSize;Pending=$pending
                    NsPerItem=[Math]::Round((Median $times),2)
                    MinNsPerItem=[Math]::Round(($times | Measure-Object -Minimum).Minimum,2)
                    MaxNsPerItem=[Math]::Round(($times | Measure-Object -Maximum).Maximum,2)
                    AllocationsPerItem=[Math]::Round((Median @($data | ForEach-Object {[double]$_.allocations/$items})),4)
                    BytesPerItem=[Math]::Round((Median @($data | ForEach-Object {[double]$_.allocated_bytes/$items})),2)
                    RetainedBytes=0
                    CeManualPairedRatio=[Math]::Round((Median $ratios),3)
                }
            }
        }
    }
}
$paths=@('benchmarks/benchmark_async_sequence.das','benchmarks/async_sequence_workloads.das')
$paths+=@(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'lib') -Filter '*.das' | ForEach-Object {'lib/'+$_.Name})
$metadata=[ordered]@{
    RecordedAt=[DateTimeOffset]::Now.ToString('o');Mode=$(if($Jit){'jit'}else{'interpreter'})
    Elements=$Elements;Batches=$Batches;Samples=$Samples;WorkSizes=@(0,$Work);PendingPolls=@(0,1)
    Compiler=$Daslang;CompilerSha256=(Get-FileHash -LiteralPath $Daslang).Hash
    Processor=$env:PROCESSOR_IDENTIFIER;OperatingSystem=[Environment]::OSVersion.VersionString
    SourceRoot=$SourceRoot;CompilationAndProcessMs=$watch.Elapsed.TotalMilliseconds
    AllocationScope='cumulative daScript heap allocations/bytes; excludes string heap, LLVM and native/OS allocations'
    SourceHashes=@($paths | ForEach-Object {[pscustomobject]@{File=$_;Sha256=(Get-FileHash -LiteralPath (Join-Path $SourceRoot $_)).Hash}})
    Results=@($summary)
}
$metadata | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json') -Encoding UTF8
$summary | Where-Object {$_.Work -eq 0 -and $_.Pending -eq 0} | Format-Table -AutoSize
Write-Host "Raw samples and metadata: $OutputDirectory"
