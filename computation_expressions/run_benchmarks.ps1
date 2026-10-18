param(
    [string]$Daslang = $env:DASLANG_EXE,
    [ValidateRange(100, 10000000)][int]$Iterations = 200000,
    [ValidateRange(3, 101)][int]$Samples = 9,
    [switch]$Jit,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'benchmark-results')
)
. (Join-Path $PSScriptRoot 'source_paths.ps1')
$ErrorActionPreference = 'Stop'
if (-not $Daslang) {
    $command = Get-Command daslang.exe -ErrorAction SilentlyContinue
    if ($command) { $Daslang = $command.Source }
    else { $Daslang = 'C:\src\daslang-0.6.5-RC2\sdk\daslang_bundle\bin\daslang.exe' }
}
$Daslang = (Resolve-Path -LiteralPath $Daslang).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$invocation = @((Join-Path $PSScriptRoot 'benchmarks/benchmark_ce.das'), '-no-module-cache')
if ($Jit) { $invocation += @('-jit','-jit-no-cache') }
$invocation += @('--', '--iterations', "$Iterations", '--samples', "$Samples")
$output = @(& $Daslang @invocation 2>&1 | ForEach-Object { "$_" })
$exitCode = $LASTEXITCODE
$output | Set-Content -LiteralPath (Join-Path $OutputDirectory 'raw.log') -Encoding UTF8
if ($exitCode -ne 0 -or $output -notcontains 'CE benchmarks OK') {
    throw "Benchmark failed (exit $exitCode). See $OutputDirectory/raw.log"
}
$rows = @($output | Where-Object { $_.StartsWith('BENCH,') } |
    ConvertFrom-Csv -Header 'marker','case','implementation','sample','iterations','elapsed_ns','checksum','heap_before','heap_after')
if ($rows.Count -ne 10 * $Samples) { throw 'Unexpected number of timing samples.' }
foreach ($row in $rows) {
    if ([int64]$row.elapsed_ns -le 0 -or [int]$row.iterations -ne $Iterations -or $row.heap_before -ne $row.heap_after) {
        throw 'Invalid timing or retained heap growth.'
    }
}
$rows | Select-Object case,implementation,sample,iterations,elapsed_ns,checksum,heap_before,heap_after |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'samples.csv') -NoTypeInformation -Encoding UTF8
function Median($values) {
    $sorted = @($values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$middle] }
    return ($sorted[$middle - 1] + $sorted[$middle]) / 2.0
}
$summary = foreach ($case in @('result_mixed','state_loop','state_variable','list_product','sequence_protected')) {
    $ce = @($rows | Where-Object { $_.case -eq $case -and $_.implementation -eq 'ce' } | Sort-Object {[int]$_.sample})
    $manual = @($rows | Where-Object { $_.case -eq $case -and $_.implementation -eq 'manual' } | Sort-Object {[int]$_.sample})
    $ratios = for ($i = 0; $i -lt $Samples; $i++) {
        if ($ce[$i].checksum -ne $manual[$i].checksum) { throw "Checksum mismatch: $case" }
        [double]$ce[$i].elapsed_ns / [double]$manual[$i].elapsed_ns
    }
    $ceTimes = @($ce | ForEach-Object { [double]$_.elapsed_ns / $Iterations })
    $manualTimes = @($manual | ForEach-Object { [double]$_.elapsed_ns / $Iterations })
    [pscustomobject]@{
        Case = $case
        CeNsPerOperation = [Math]::Round((Median $ceTimes), 2)
        ManualNsPerOperation = [Math]::Round((Median $manualTimes), 2)
        MedianPairedRatio = [Math]::Round((Median $ratios), 3)
        CeMinNs = [Math]::Round(($ceTimes | Measure-Object -Minimum).Minimum, 2)
        CeMaxNs = [Math]::Round(($ceTimes | Measure-Object -Maximum).Maximum, 2)
    }
}
$metadata = [ordered]@{
    RecordedAt = [DateTimeOffset]::Now.ToString('o')
    Mode = $(if ($Jit) { 'jit' } else { 'interpreter' })
    Iterations = $Iterations
    Samples = $Samples
    Compiler = $Daslang
    CompilerSha256 = (Get-FileHash -LiteralPath $Daslang).Hash
    Processor = $env:PROCESSOR_IDENTIFIER
    OperatingSystem = [Environment]::OSVersion.VersionString
    SourceHashes = @('benchmarks/benchmark_ce.das','benchmarks/benchmark_workloads.das','lib/computation_macro.das','lib/computation_builders.das','lib/computation_effects.das','lib/list_builder.das','lib/sequence_builder.das','lib/sequence_runtime.das','lib/builder_protocol.das','lib/computation_resources.das','lib/zip_runtime.das') |
        ForEach-Object { [pscustomobject]@{ File = $_; Sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_)).Hash } }
    Results = @($summary)
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json') -Encoding UTF8
$summary | Format-Table -AutoSize
Write-Host "Raw samples and metadata: $OutputDirectory"

