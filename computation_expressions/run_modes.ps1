param(
    [ValidateSet('Interpreter','Jit','AotGenerate','All')][string]$Mode='All',
    [string]$Daslang=$env:DASLANG_EXE,
    [switch]$IncludeKnownIssues,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'mode-results')
)
. (Join-Path $PSScriptRoot 'source_paths.ps1')
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$rows=[Collections.Generic.List[object]]::new()
$modes=if($Mode -eq 'All'){@('Interpreter','Jit','AotGenerate')}else{@($Mode)}
# This is an explicit cross-mode subset, not the full interpreter regression.
$tests=@(Get-Content (Join-Path $PSScriptRoot 'mode_tests.json') -Raw | ConvertFrom-Json)
Push-Location $PSScriptRoot
try {
    foreach($currentMode in $modes) {
        $files=@($tests)
        if($IncludeKnownIssues){$files+=@('tests/repro/repro_jit_tuple_recover.das','tests/repro/repro_jit_state_recover.das')}
        foreach($file in $files) {
            $known=[IO.Path]::GetFileName($file).StartsWith('repro_')
            $stem="$currentMode-$([IO.Path]::GetFileNameWithoutExtension($file))"
            $log=Join-Path $OutputDirectory ($stem+'.log')
            $cpp=Join-Path $OutputDirectory ($stem+'.cpp')
             $arguments=@((Get-CeSource $file),'-no-module-cache')
            if($currentMode -eq 'Jit'){$arguments+=@('-jit','-jit-no-cache')}
            if($currentMode -eq 'AotGenerate'){$arguments=@('-aot',(Get-CeSource $file),$cpp)}
            $watch=[Diagnostics.Stopwatch]::StartNew()
            & $Daslang @arguments *> $log
            $code=$LASTEXITCODE
            $watch.Stop()
            $knownReturn=$false
            if($currentMode -eq 'Jit' -and $file -eq 'tests/repro/repro_jit_tuple_recover.das' -and $code -eq 1) {
                $diagnostic=[IO.File]::ReadAllText($log)
                $knownReturn=$diagnostic.Contains('LLVM JIT: return inside try/recover leaves the try arm, not the function.') -and
                    $diagnostic -match 'EXCEPTION: assert failed[^\r\n]*repro_jit_tuple_recover\.das:24:4'
            }
            $status=if($code -eq 0){if($currentMode -eq 'AotGenerate'){'generated_not_executed'}else{'passed'}}
                elseif($known -and $currentMode -eq 'Jit' -and $code -eq -1073741819){'known_access_violation'}
                elseif($knownReturn){'known_return_in_recover'}else{'failed'}
            $rows.Add([pscustomobject]@{Mode=$currentMode;File=$file;Status=$status;ExitCode=$code;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Log=$log})
            Write-Host "$currentMode $file : $status (exit $code)"
        }
    }
} finally {
    Pop-Location
    [ordered]@{Compiler=$Daslang;CompilerSha256=(Get-FileHash $Daslang).Hash;RecordedAt=[DateTimeOffset]::Now.ToString('o');
        Scope='explicit subset; AOT generation is NOT runtime execution';Results=@($rows.ToArray())} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json')
}
if(@($rows | Where-Object Status -eq 'failed').Count){throw 'Unexpected mode failure; see summary.json'}
if(@($rows | Where-Object Status -like 'known_*').Count){Write-Warning 'Known native JIT limitations reproduced; these repros are not counted as passing. See RELIABILITY.md.'}
if($modes -contains 'AotGenerate'){Write-Warning 'AOT C++ generated only. Compile/link into a host with strict AOT linking and run separately before claiming AOT runtime support.'}
