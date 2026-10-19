param([string]$Daslang=$env:DASLANG_EXE,[string]$Url,[switch]$Jit)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$example=Join-Path $PSScriptRoot 'examples/websocket_echo_demo.das'
$previousUrl=[Environment]::GetEnvironmentVariable('RX_WS_URL','Process')
$previousTemp=[Environment]::GetEnvironmentVariable('TEMP','Process')
$previousTmp=[Environment]::GetEnvironmentVariable('TMP','Process')
try {
    $env:RX_WS_URL=$Url
    if($Url){
        $arguments=@($example,'-no-module-cache')
        if($Jit){$arguments+=@('-jit','-jit-no-cache')}
        & $Daslang @arguments
    } else {
        # Only the test server uses Python; the client and event loop are daScript.
        $tempDirectory=Join-Path $PSScriptRoot '.work/integration-temp'
        New-Item -ItemType Directory -Force $tempDirectory | Out-Null
        $env:TEMP=[IO.Path]::GetFullPath($tempDirectory);$env:TMP=$env:TEMP
        $arguments=@((Join-Path $PSScriptRoot '../computation_expressions/support/task_hv_fixture.py'),'--daslang',$Daslang,'--script',$example)
        if($Jit){$arguments+='--jit'}
        & python @arguments
    }
    if($LASTEXITCODE -ne 0){throw 'ReactiveX WebSocket example failed'}
} finally {
    [Environment]::SetEnvironmentVariable('RX_WS_URL',$previousUrl,'Process')
    [Environment]::SetEnvironmentVariable('TEMP',$previousTemp,'Process')
    [Environment]::SetEnvironmentVariable('TMP',$previousTmp,'Process')
}
