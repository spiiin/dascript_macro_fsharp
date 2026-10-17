param(
    [string]$Daslang=$env:DASLANG_EXE,
    [ValidateRange(3,31)][int]$Samples=3,
    [switch]$Jit,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'compilation-metrics')
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path $Daslang).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
function Median($values){$v=@($values|Sort-Object);$middle=[int][Math]::Floor($v.Count/2);if($v.Count%2){return $v[$middle]};return ($v[$middle-1]+$v[$middle])/2}
$rows=[Collections.Generic.List[object]]::new()
$expansions=[Collections.Generic.List[object]]::new()
$checksums=@{}
foreach($case in @('result','state','list')) {
    foreach($implementation in @('ce','manual')) {
        $name="$case-$implementation"
        $file=Join-Path $PSScriptRoot "benchmarks/metrics/$name.das"
        $log=Join-Path $OutputDirectory "$name-run.log"
        # Also verify semantic equivalence; dry-run alone cannot do so.
        $arguments=@($file,'-no-module-cache')
        if($Jit){$arguments+=@('-jit','-jit-no-cache')}
        & $Daslang @arguments *> $log
        if($LASTEXITCODE -ne 0){throw "Metric case failed: $name"}
        $match=[regex]::Match([IO.File]::ReadAllText($log),'(?m)^CHECKSUM,(-?\d+)\s*$')
        if(-not $match.Success){throw "Missing checksum: $name"}
        $checksums[$name]=$match.Groups[1].Value
        $dump=Join-Path $OutputDirectory "$name-expansion.txt"
        & $Daslang $file -no-module-cache -compile-only -log *> $dump
        if($LASTEXITCODE -ne 0){throw "Expansion failed: $name"}
        $text=[IO.File]::ReadAllText($dump)
        $expansions.Add([pscustomobject]@{Case=$case;Implementation=$implementation;Bytes=(Get-Item $dump).Length;
            Lines=($text -split "`n").Count;Functions=[regex]::Matches($text,'(?m)^def ').Count;Dump=[IO.Path]::GetFileName($dump)})
    }
    if($checksums["$case-ce"] -ne $checksums["$case-manual"]){throw "Checksum mismatch: $case"}
    foreach($sample in 0..($Samples-1)) {
        # Alternate order; compile each implementation in a fresh process.
        $order=if($sample%2){@('manual','ce')}else{@('ce','manual')}
        foreach($implementation in $order) {
            $name="$case-$implementation"
            $file=Join-Path $PSScriptRoot "benchmarks/metrics/$name.das"
            $log=Join-Path $OutputDirectory "$name-compile-$sample.log"
            $arguments=@($file,'-no-module-cache','-dry-run','-log-compile-time')
            if($Jit){$arguments+=@('-jit','-jit-no-cache')}
            $watch=[Diagnostics.Stopwatch]::StartNew()
            & $Daslang @arguments *> $log
            $code=$LASTEXITCODE;$watch.Stop()
            if($code -ne 0){throw "Compilation failed: $name"}
            $rows.Add([pscustomobject]@{Case=$case;Implementation=$implementation;Sample=$sample;Milliseconds=$watch.Elapsed.TotalMilliseconds})
        }
    }
}
$comparison=foreach($case in @('result','state','list')) {
    $ce=Median @($rows|Where-Object {$_.Case -eq $case -and $_.Implementation -eq 'ce'}|ForEach-Object Milliseconds)
    $manual=Median @($rows|Where-Object {$_.Case -eq $case -and $_.Implementation -eq 'manual'}|ForEach-Object Milliseconds)
    $ceExpansion=$expansions|Where-Object {$_.Case -eq $case -and $_.Implementation -eq 'ce'}
    $manualExpansion=$expansions|Where-Object {$_.Case -eq $case -and $_.Implementation -eq 'manual'}
    [pscustomobject]@{Case=$case;CeCompileAndSimulateMs=$ce;ManualCompileAndSimulateMs=$manual;CompileRatio=$ce/$manual;
        CeExpansionBytes=$ceExpansion.Bytes;ManualExpansionBytes=$manualExpansion.Bytes;ExpansionRatio=$ceExpansion.Bytes/$manualExpansion.Bytes}
}
$rows.ToArray()|Export-Csv (Join-Path $OutputDirectory 'compile-samples.csv') -NoTypeInformation
$result=[ordered]@{Mode=$(if($Jit){'jit'}else{'interpreter'});Samples=$Samples;Compiler=$Daslang;CompilerSha256=(Get-FileHash $Daslang).Hash;
    CompileScope='fresh process, no AST cache; startup + compile + simulate; JIT cache disabled; no workload execution in timed samples';
    ExpansionScope='entry-program textual compiler log, not machine code or complete imported-module AST';
    Comparison=@($comparison);Expansions=@($expansions.ToArray());Checksums=$checksums;
    SourceHashes=@(Get-ChildItem (Join-Path $PSScriptRoot 'lib') -Filter '*.das';Get-ChildItem (Join-Path $PSScriptRoot 'benchmarks/metrics') -Filter '*.das')|
        ForEach-Object {[pscustomobject]@{File=[IO.Path]::GetRelativePath($PSScriptRoot,$_.FullName).Replace('\','/');Sha256=(Get-FileHash $_.FullName).Hash}}}
$result|ConvertTo-Json -Depth 7|Set-Content (Join-Path $OutputDirectory 'compilation.json')
$comparison|Format-Table -AutoSize
