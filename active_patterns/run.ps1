param([string]$Daslang=$env:DASLANG_EXE,[switch]$Test,[switch]$Jit)
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$Daslang=(Resolve-Path -LiteralPath $Daslang).Path
function Check([string]$File,[bool]$Pass,[string]$Expected) {
    $arguments=@((Join-Path $PSScriptRoot $File),'-no-module-cache')
    if($Jit){$arguments+=@('-jit','-jit-no-cache')}
    $output=& $Daslang @arguments 2>&1
    $code=$LASTEXITCODE
    $text=$output -join "`n"
    $output | ForEach-Object {Write-Host $_}
    if(($code -eq 0) -ne $Pass -or $text -notmatch [regex]::Escape($Expected)) {
        throw "Unexpected result for $File (exit $code). SDK with PR #4259 is required."
    }
}
Check 'examples/active_patterns_demo.das' $true 'Active patterns demo OK'
if($Test){
    Check 'tests/failed_total_missing_case.das' $false 'Parity.odd'
    Check 'tests/failed_view_missing_fallback.das' $false 'match is not exhaustive'
    Check 'tests/failed_partial_missing_fallback.das' $false 'match is not exhaustive'
    Check 'tests/failed_parameter_type.das' $false 'does not compile'
    # GitHub Actions propagates LASTEXITCODE: end on a validated successful native call.
    Check 'tests/test_active_patterns.das' $true 'Active patterns checks OK'
}
Write-Host 'All active pattern checks passed.'
