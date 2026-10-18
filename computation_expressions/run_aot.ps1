param(
    [string]$Daslang=$env:DASLANG_EXE,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/aot-runtime'),
    [string]$BuildDirectory=(Join-Path $PSScriptRoot '.work/aot-build'),
    [int]$Parallel=2
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$sdk=Split-Path (Split-Path $Daslang -Parent) -Parent
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$tests=@(Get-Content (Join-Path $PSScriptRoot 'mode_tests.json') -Raw | ConvertFrom-Json | Where-Object {$_ -like 'tests/test_task*'})
$files=@($tests | ForEach-Object {(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot $_)).Path.Replace('\','/')})
$manifest=Join-Path $OutputDirectory 'scripts.txt'
[IO.File]::WriteAllLines($manifest,$files)
& cmake -S (Join-Path $PSScriptRoot 'aot_host') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_PREFIX_PATH=$sdk" "-DSCRIPT_MANIFEST=$manifest"
if($LASTEXITCODE -ne 0){throw 'AOT host configuration failed'}
& cmake --build $BuildDirectory --config Release --parallel $Parallel
if($LASTEXITCODE -ne 0){throw 'AOT host build failed'}
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
