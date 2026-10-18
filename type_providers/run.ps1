param(
    [string]$Daslang = $env:DASLANG_EXE,
    [switch]$Test
)
$ErrorActionPreference = 'Stop'
if (-not $Daslang) {
    $command = Get-Command daslang.exe -ErrorAction SilentlyContinue
    if ($command) { $Daslang = $command.Source }
    elseif (Test-Path -LiteralPath 'C:\src\daslang-0.6.5-RC2\sdk\daslang_bundle\bin\daslang.exe') {
        $Daslang = 'C:\src\daslang-0.6.5-RC2\sdk\daslang_bundle\bin\daslang.exe'
    } else { throw 'Specify -Daslang <path to daslang.exe> or set DASLANG_EXE.' }
}
$Daslang = (Resolve-Path -LiteralPath $Daslang).Path
function Invoke-DasCheck([string]$File, [bool]$ShouldPass, [string]$Expected) {
    $lines = & $Daslang $File -no-module-cache 2>&1
    $code = $LASTEXITCODE
    $text = $lines -join "`n"
    $lines | ForEach-Object { Write-Host $_ }
    if (($code -eq 0) -ne $ShouldPass) { throw "Unexpected exit code $code from $File" }
    if ($text -notmatch [regex]::Escape($Expected)) { throw "Missing expected diagnostic '$Expected' from $File" }
}
Push-Location $PSScriptRoot
try {
    Invoke-DasCheck 'main.das' $true 'OK'
    Invoke-DasCheck 'erased_demo.das' $true 'erased demo OK'
    Invoke-DasCheck 'native_demo.das' $true 'native demo OK'
    if ($Test) {
        Invoke-DasCheck 'test_runtime.das' $true 'runtime checks OK'
        Invoke-DasCheck 'test_typo.das' $false 'healt'
        Invoke-DasCheck 'test_wrong_type.das' $false 'can only copy compatible type'
        Invoke-DasCheck 'test_bad_schema.das' $false "unsupported type 'float'"
        Invoke-DasCheck 'test_erased_leaf.das' $true 'lazy ref leaf OK'
        Invoke-DasCheck 'test_erased_typo.das' $false "has no field 'naem'"
        Invoke-DasCheck 'test_erased_type.das' $false 'initialization type mismatch'
        Invoke-DasCheck 'test_erased_scalar.das' $false 'cannot navigate through scalar'
        Invoke-DasCheck 'test_erased_broken.das' $false 'Broken.json'
        Invoke-DasCheck 'test_erased_missing.das' $false 'cannot read schema'
        Invoke-DasCheck 'test_erased_future.das' $false "unsupported type 'unsupported_until_accessed'"
        Invoke-DasCheck 'test_erased_runtime.das' $false "expected integer"
        Invoke-DasCheck 'test_erased_object.das' $false 'Player.team: expected object'
        Invoke-DasCheck 'test_native_runtime.das' $true 'native runtime OK'
        Invoke-DasCheck 'test_native_wrong_type.das' $false 'no matching functions or generics: apply_damage'
        Invoke-DasCheck 'test_native_cycle.das' $false 'by-value dependency cycle'
        Invoke-DasCheck 'test_native_missing.das' $false 'cannot read dependency'
        Invoke-DasCheck 'test_native_typo.das' $false "field 'titel' not found"

        $native = (& $Daslang 'native_demo.das' -no-module-cache -log 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'Native expansion check failed.' }
        $generated = [regex]::Matches($native, '(?m)^\[native\.generate\] .+$')
        if ($generated.Count -ne 2) { throw 'Expected exactly Player and Team, each generated once.' }
        if ($native -notmatch 'player\.health -= damage') { throw 'Missing direct native field access.' }
        Write-Host 'Native types verified: exactly 2 generated types; direct field access between functions.'

        # Verify the output of the real compiler, not just the macro's own claims.
        $expansion = (& $Daslang 'erased_demo.das' -no-module-cache -log 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw 'Expansion check failed to compile.' }
        $loads = [regex]::Matches($expansion, '(?m)^\[erased\.load\] .+$')
        if ($loads.Count -ne 2) { throw "Expected two schema loads; got $($loads.Count)." }
        if ($expansion -notmatch 'ep_string\(ep_object\(') { throw 'Missing erased accessor expansion.' }
        if ($expansion -match '(?m)^\s*struct (Player|Team)\b') { throw 'Virtual types unexpectedly materialized.' }
        Write-Host 'Erasure verified: native typed accessors, no Player/Team structs, exactly 2 schema loads.'
        Write-Host 'All checks passed (including expected compile failures).'
    }
} finally { Pop-Location }
