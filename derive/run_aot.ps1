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
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
$cases=@(Get-Content (Join-Path $PSScriptRoot 'scripts.json') -Raw|ConvertFrom-Json)
$files=@($cases|ForEach-Object {(Resolve-Path (Join-Path $PSScriptRoot $_.file)).Path.Replace('\','/')})
$manifest=Join-Path $OutputDirectory 'scripts.txt'
[IO.File]::WriteAllLines($manifest,$files)
function SourceStamp {
    return ((Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.das'|Where-Object {$_.FullName -notlike '*\.work\*'}|Sort-Object FullName|ForEach-Object {"$($_.FullName):$((Get-FileHash $_.FullName).Hash)"}) -join "`n")
}
$stamp=SourceStamp
& cmake -S (Join-Path $PSScriptRoot 'aot_host') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 "-DDAS_DIR=$sdk/lib/cmake/DAS" "-DCMAKE_PREFIX_PATH=$sdk" "-DSCRIPT_MANIFEST=$manifest"
if($LASTEXITCODE -ne 0){throw 'Derive AOT configure failed'}
& cmake --build $BuildDirectory --config Release --parallel $Parallel
if($LASTEXITCODE -ne 0){throw 'Derive AOT build failed'}
if((SourceStamp) -cne $stamp){throw 'Derive sources changed during AOT build; rerun'}
$exe=Join-Path $BuildDirectory 'Release/derive_aot.exe'
$results=@()
foreach($file in $files) {
    $log=Join-Path $OutputDirectory ([IO.Path]::GetFileNameWithoutExtension($file)+'.runtime.log')
    & $exe $sdk $file *> $log
    $code=$LASTEXITCODE
    $passed=$code -eq 0 -and [IO.File]::ReadAllText($log).Contains('AOT RUNTIME PASS:')
    $results+=[pscustomobject]@{File=$file;ExitCode=$code;AotRuntimePassed=$passed;Log=$log}
    Write-Host "AOT $file : $passed (exit $code)"
}
[ordered]@{CompilerSha256=(Get-FileHash $Daslang).Hash;StrictLinking=$true;MainAotChecked=$true;Results=$results}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutputDirectory 'runtime-summary.json')
if(@($results|Where-Object {-not $_.AotRuntimePassed}).Count){throw 'Derive AOT runtime failed'}
