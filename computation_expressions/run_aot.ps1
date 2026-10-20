param(
    [string]$Daslang=$env:DASLANG_EXE,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/aot-runtime'),
    [string]$BuildDirectory=(Join-Path $PSScriptRoot '.work/aot-build'),
    [int]$Parallel=2,
    [string[]]$Scripts=@()
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$sdk=Split-Path (Split-Path $Daslang -Parent) -Parent
$dasPackage=Join-Path $sdk 'lib/cmake/DAS'
if(-not(Test-Path -LiteralPath (Join-Path $dasPackage 'DASConfig.cmake'))){throw 'Selected compiler has no matching SDK CMake package'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$tests=if($Scripts.Count){$Scripts}else{@(Get-Content (Join-Path $PSScriptRoot 'mode_tests.json') -Raw | ConvertFrom-Json | Where-Object {$_ -match '^tests/test_(task|async_sequence|parser|search|query|domain_deferred)' -or $_ -eq 'tests/test_standard_outcomes.das' -or $_ -eq 'tests/test_move_ce.das' -or $_ -eq 'examples/query_full_demo.das' -or $_ -eq 'examples/task_runtime_channel_demo.das' -or $_ -eq 'examples/task_parallel_jobque_demo.das'})}
$files=@($tests | ForEach-Object {(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $_)).Path.Replace('\','/')})
$manifest=Join-Path $OutputDirectory 'scripts.txt'
[IO.File]::WriteAllLines($manifest,$files)
# Reject a build whose sources changed while CMake generated/compiled the stubs.
function Get-AotSourceStamp {
    $sources=@(Get-ChildItem (Join-Path $PSScriptRoot 'lib') -Filter '*.das' -File)
    $sources+=@(Get-ChildItem (Join-Path $PSScriptRoot 'support') -Filter '*.das' -File -Recurse)
    $sources+=@($files | ForEach-Object {Get-Item -LiteralPath $_})
    return (($sources | Sort-Object FullName -Unique | ForEach-Object {
        "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }) -join "`n")
}
$sourceStamp=Get-AotSourceStamp
# DAS_DIR is cached by find_package; CMAKE_PREFIX_PATH alone does not switch SDKs.
& cmake -S (Join-Path $PSScriptRoot 'aot_host') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 "-DDAS_DIR=$dasPackage" "-DCMAKE_PREFIX_PATH=$sdk" "-DSCRIPT_MANIFEST=$manifest"
if($LASTEXITCODE -ne 0){throw 'AOT host configuration failed'}
& cmake --build $BuildDirectory --config Release --parallel $Parallel
if($LASTEXITCODE -ne 0){throw 'AOT host build failed'}
if((Get-AotSourceStamp) -cne $sourceStamp){throw 'AOT sources changed during the build; rerun after editing stops.'}
$hostExe=Join-Path $BuildDirectory 'Release/ce_task_aot.exe'
$rows=@()
foreach($file in $files) {
    $log=Join-Path $OutputDirectory ([IO.Path]::GetFileNameWithoutExtension($file)+'.runtime.log')
    & $hostExe $sdk $file *> $log
    $code=$LASTEXITCODE
    $text=[IO.File]::ReadAllText($log)
    $passed=$code -eq 0 -and $text.Contains('AOT RUNTIME PASS:')
    $rows += [pscustomobject]@{File=$file;ExitCode=$code;AotRuntimePassed=$passed;Log=$log}
    Write-Host "AOT runtime $file : $passed (exit $code)"
}
[ordered]@{Compiler=$Daslang;CompilerSha256=(Get-FileHash $Daslang).Hash;StrictLinking=$true;MainAotChecked=$true;Results=$rows} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'runtime-summary.json')
if(@($rows | Where-Object {-not $_.AotRuntimePassed}).Count){throw 'AOT runtime tests failed; see runtime-summary.json'}
