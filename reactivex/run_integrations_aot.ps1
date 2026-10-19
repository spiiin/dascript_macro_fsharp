param(
 [string]$Daslang=$env:DASLANG_EXE,
 [string]$OutputDirectory=(Join-Path $PSScriptRoot '.work/integrations-aot-runtime'),
 [string]$BuildDirectory=(Join-Path $PSScriptRoot '.work/integrations-aot-build'),
 [int]$Parallel=2,
 [switch]$BuildOnly
)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
$sdk=Split-Path (Split-Path $Daslang -Parent) -Parent
$nativeHashes=@{
 'bin/daslang.exe'='1A2422177F0744EC892D237CFB7C07829F40A9466FA7222C273C3A17D15AF698'
 'modules/dasHV/dasModuleHV.shared_module'='0D5DAB3A10714D8B51AD3D68263374ECEC4B690DCC6E09DBA26E892235920D03'
 'modules/dasGlfw/dasModuleGlfw.shared_module'='739180D3556FAE42A1E63CDBE8D3151BBAEC8C006B892883A3224835E13D5F14'
}
foreach($name in $nativeHashes.Keys) {
 if((Get-FileHash (Join-Path $sdk $name)).Hash -ne $nativeHashes[$name]){throw "Native AOT bridge requires the pinned Windows 0.6.5-RC2 SDK: $name"}
}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$BuildDirectory=[IO.Path]::GetFullPath($BuildDirectory)
New-Item -ItemType Directory -Force $OutputDirectory,$BuildDirectory | Out-Null
$archive=Join-Path $BuildDirectory 'libhv.tar.gz'
$hash='43F425DAE61D060913C5CE280C9776DFB98C61BB965A38C5A38D4788A7295201'
if(-not(Test-Path $archive)) {
 Invoke-WebRequest -Uri 'https://codeload.github.com/ithewei/libhv/tar.gz/303f50c7b23f250c5b620d92c04b41060e1701c2' -OutFile $archive
}
if((Get-FileHash $archive).Hash -ne $hash){throw 'Pinned libhv archive hash mismatch'}
$hvRoot=Join-Path $BuildDirectory 'libhv-303f50c7b23f250c5b620d92c04b41060e1701c2'
if(-not(Test-Path (Join-Path $hvRoot 'CMakeLists.txt'))) {
 & tar -xf $archive -C $BuildDirectory --exclude=CLAUDE.md --exclude=AGENTS.md
 if($LASTEXITCODE -ne 0){throw 'libhv headers extraction failed'}
}
$files=@('tests/test_glfw_ui.das','examples/glfw_ui_demo.das','tests/test_websocket_echo.das','examples/websocket_echo_demo.das') | ForEach-Object {(Resolve-Path (Join-Path $PSScriptRoot $_)).Path.Replace('\','/')}
$manifest=Join-Path $OutputDirectory 'scripts.txt'
[IO.File]::WriteAllLines($manifest,$files)
function SourceStamp {
 $sources=@(Get-ChildItem (Join-Path $PSScriptRoot 'lib') -Filter '*.das')
 $sources+=@(Get-ChildItem (Join-Path $PSScriptRoot 'support') -Filter '*.das')
 $sources+=@(Get-ChildItem (Join-Path $PSScriptRoot '../computation_expressions/lib') -Filter '*.das')
 $sources+=@($files | ForEach-Object {Get-Item $_})
 $sources+=@(Get-Item (Join-Path $PSScriptRoot 'tests/failed_native_aot_unlinked.das'),(Join-Path $PSScriptRoot '../computation_expressions/support/task_hv_fixture.py'),$PSCommandPath)
 $sources+=@(Get-ChildItem (Join-Path $PSScriptRoot 'aot_host') -Recurse -File)
 return (($sources | Sort-Object FullName -Unique | ForEach-Object {"$($_.FullName):$((Get-FileHash $_.FullName).Hash)"}) -join "`n")
}
$stamp=SourceStamp
& cmake -S (Join-Path $PSScriptRoot 'aot_host') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 "-DDAS_DIR=$sdk/lib/cmake/DAS" "-DSCRIPT_MANIFEST=$manifest" '-DRX_NATIVE_INTEGRATIONS=ON' "-DLIBHV_SOURCE_DIR=$hvRoot"
if($LASTEXITCODE -ne 0){throw 'Native AOT configure failed'}
& cmake --build $BuildDirectory --config Release --parallel $Parallel
if($LASTEXITCODE -ne 0){throw 'Native AOT build failed'}
if((SourceStamp) -cne $stamp){throw 'Native AOT sources changed during build'}
$hostExe=Join-Path $BuildDirectory 'Release/reactivex_aot.exe'
if($BuildOnly){Write-Host "Built native AOT host: $hostExe";exit 0}
$rows=@()
$previousSmoke=[Environment]::GetEnvironmentVariable('RX_GLFW_SMOKE','Process')
$previousUrl=[Environment]::GetEnvironmentVariable('RX_WS_URL','Process')
$previousPath=[Environment]::GetEnvironmentVariable('PATH','Process')
$previousTemp=[Environment]::GetEnvironmentVariable('TEMP','Process')
$previousTmp=[Environment]::GetEnvironmentVariable('TMP','Process')
try {
 $env:RX_GLFW_SMOKE='1';$env:RX_WS_URL=$null
 $env:PATH="$sdk/bin;$sdk/modules/dasGlfw;$sdk/modules/dasHV;$previousPath"
 $tempDirectory=Join-Path $OutputDirectory 'temp'
 New-Item -ItemType Directory -Force $tempDirectory | Out-Null
 $env:TEMP=$tempDirectory;$env:TMP=$tempDirectory
 foreach($file in $files) {
  $stem=[IO.Path]::GetFileNameWithoutExtension($file)
  $log=Join-Path $OutputDirectory "$stem.runtime.log"
  $peerReport=Join-Path $OutputDirectory "$stem.peer.json"
  $network=$stem -like '*websocket*'
  if($network) {
   & python (Join-Path $PSScriptRoot '../computation_expressions/support/task_hv_fixture.py') --aot-host $hostExe --sdk-root $sdk --script $file --report $peerReport *> $log
  } else { & $hostExe $sdk $file *> $log }
  $code=$LASTEXITCODE
  $output=Get-Content $log -Raw
  $passed=$code -eq 0 -and $output.Contains('AOT RUNTIME PASS:') -and $output.Contains('main->aot=yes, strict linking') -and $output.Contains('ReactiveX')
  $peer=$null
  if($network -and $passed) {
   $peer=Get-Content $peerReport -Raw | ConvertFrom-Json
   $passed=$peer.peer_closure_verified -and $peer.strict_aot -and $peer.accepted -eq $peer.closed
  }
  $rows += [pscustomobject]@{File=$file;ExitCode=$code;AotRuntimePassed=$passed;Log=$log;Peer=$peer}
  Write-Host "Native AOT runtime $file : $passed (exit $code)"
 }
 $negativeLog=Join-Path $OutputDirectory 'unlinked.runtime.log'
 & $hostExe $sdk (Join-Path $PSScriptRoot 'tests/failed_native_aot_unlinked.das') *> $negativeLog
 $negativeCode=$LASTEXITCODE
 $negativeText=Get-Content $negativeLog -Raw
 $fallbackRejected=$negativeCode -ne 0 -and $negativeText -match 'AOT|aot' -and !($negativeText -match '(?m)^UNLINKED SCRIPT RAN\r?$')
} finally {
 [Environment]::SetEnvironmentVariable('RX_GLFW_SMOKE',$previousSmoke,'Process')
 [Environment]::SetEnvironmentVariable('RX_WS_URL',$previousUrl,'Process')
 [Environment]::SetEnvironmentVariable('PATH',$previousPath,'Process')
 [Environment]::SetEnvironmentVariable('TEMP',$previousTemp,'Process')
 [Environment]::SetEnvironmentVariable('TMP',$previousTmp,'Process')
}
if((SourceStamp) -cne $stamp){throw 'Native AOT sources changed during runtime checks'}
[ordered]@{Compiler=$Daslang;CompilerSha256=(Get-FileHash $Daslang).Hash;Host=$hostExe;HostSha256=(Get-FileHash $hostExe).Hash;StrictLinking=$true;MainAotChecked=$true;FallbackRejected=$fallbackRejected;LibhvSha256=$hash;SourceStamp=$stamp;Results=$rows} |
 ConvertTo-Json -Depth 7 | Set-Content (Join-Path $OutputDirectory 'runtime-summary.json') -Encoding UTF8
if(@($rows | Where-Object {!$_.AotRuntimePassed}).Count -or !$fallbackRejected){throw 'Native AOT checks failed; see runtime-summary.json'}
Write-Host 'All ReactiveX native AOT integration checks passed.'
# The expected-failure unlinked check leaves a nonzero LASTEXITCODE; the GitHub pwsh wrapper would exit with it.
exit 0
