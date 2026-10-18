param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateRange(100,10000000)][int]$Iterations=10000,
    [ValidateRange(3,101)][int]$Samples=5,
    [switch]$Jit,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'performance-metrics')
)
. (Join-Path $PSScriptRoot 'source_paths.ps1')
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
& (Join-Path $PSScriptRoot 'run_benchmarks.ps1') -Daslang $Daslang -Iterations $Iterations -Samples $Samples -Jit:$Jit -OutputDirectory $OutputDirectory
$raw=Get-Content (Join-Path $OutputDirectory 'raw.log')
$alloc=@($raw | Where-Object {$_.StartsWith('ALLOC,')} | ConvertFrom-Csv -Header 'marker','case','implementation','sample','iterations','allocations','allocated_bytes','string_allocations','string_allocated_bytes')
if($alloc.Count -ne 10*$Samples){throw 'Missing allocation metrics'}
$alloc | Select-Object * -ExcludeProperty marker | Export-Csv (Join-Path $OutputDirectory 'allocations.csv') -NoTypeInformation
function Median($values){$s=@($values|Sort-Object);$n=$s.Count;$middle=[int][Math]::Floor($n/2);if($n%2){return $s[$middle]};return ($s[$middle-1]+$s[$middle])/2}
$allocationSummary=@($alloc | Group-Object case,implementation | ForEach-Object {
    $first=$_.Group[0]
    [pscustomobject]@{Case=$first.case;Implementation=$first.implementation;
        AllocationsPerOperation=(Median @($_.Group|ForEach-Object {[double]$_.allocations/[double]$_.iterations}));
        AllocatedBytesPerOperation=(Median @($_.Group|ForEach-Object {[double]$_.allocated_bytes/[double]$_.iterations}));
        StringAllocationsPerOperation=(Median @($_.Group|ForEach-Object {[double]$_.string_allocations/[double]$_.iterations}));
        StringBytesPerOperation=(Median @($_.Group|ForEach-Object {[double]$_.string_allocated_bytes/[double]$_.iterations}))}
})
& (Join-Path $PSScriptRoot 'measure_compilation.ps1') -Daslang $Daslang -Samples 3 -Jit:$Jit -OutputDirectory (Join-Path $OutputDirectory 'compilation')
$compilation=Get-Content (Join-Path $OutputDirectory 'compilation/compilation.json') -Raw|ConvertFrom-Json
$runtime=Get-Content (Join-Path $OutputDirectory 'summary.json') -Raw|ConvertFrom-Json
foreach($row in $alloc) {
    if([int]$row.iterations -ne $Iterations){throw 'Allocation sample iteration mismatch'}
    foreach($field in @('allocations','allocated_bytes','string_allocations','string_allocated_bytes')) {
        if([double]$row.$field -lt 0){throw "Invalid allocation counter: $field"}
    }
}
$result=[ordered]@{SchemaVersion=2;RecordedAt=[DateTimeOffset]::Now.ToString('o');Mode=$runtime.Mode;
    Compiler=$Daslang;CompilerSha256=$runtime.CompilerSha256;Iterations=$Iterations;Samples=$Samples;
    RuntimeResults=$runtime.Results;AllocationResults=$allocationSummary;
    AllocationScope='cumulative context heap deltas; excludes native/OS allocations';
    Compilation=$compilation;SourceHashes=$runtime.SourceHashes}
$result|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutputDirectory 'metrics.json')
$allocationSummary|Format-Table -AutoSize
Write-Host "Runtime, allocations and separate CE/manual compilation metrics: $OutputDirectory/metrics.json"