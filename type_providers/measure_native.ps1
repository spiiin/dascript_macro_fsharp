param(
    [ValidateRange(2, 50000)][int]$Count = 10000,
    [string]$Daslang = $env:DASLANG_EXE
)
$ErrorActionPreference = 'Stop'
if (-not $Daslang) {
    $command = Get-Command daslang.exe -ErrorAction SilentlyContinue
    if ($command) { $Daslang = $command.Source }
    elseif (Test-Path -LiteralPath 'C:\src\daslang-0.6.4\daslang_bundle\bin\daslang.exe') {
        $Daslang = 'C:\src\daslang-0.6.4\daslang_bundle\bin\daslang.exe'
    } else { throw 'Specify -Daslang or DASLANG_EXE.' }
}
$Daslang = (Resolve-Path -LiteralPath $Daslang).Path
$scratch = Join-Path $PSScriptRoot ('.work/native-' + [guid]::NewGuid().ToString('N'))
$space = Join-Path $scratch 'space'
New-Item -ItemType Directory -Path $space -Force | Out-Null
try {
    foreach ($name in @('lazy_native_provider.das', 'native_runtime.das', 'provider_runtime.das')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $scratch
    }
    for ($i = 0; $i -lt $Count; $i++) {
        $schema = '{"fields":[{"name":"id","type":"int"}]}'
        if ($i -eq 0) {
            $schema = '{"fields":[{"name":"id","type":"int"},{"name":"child","type":"ref","target":"Node1"}]}'
        }
        [IO.File]::WriteAllText((Join-Path $space "Node$i.json"), $schema)
    }
    $program = @'
options gen2
require lazy_native_provider
typedef Root = provided_type("space", "Node0")
typedef Again = provided_type("space/../space", "Node0")
def read_child(value : Root) : int { return value.child.id }
[export]
def main() {
    var value = default<Again>
    var error : string
    let ok = try_load_native("\{\"id\":0,\"child\":\{\"id\":1\}\}", value, error)
    assert(ok)
    let child = read_child(value)
    assert(value.id == 0 && child == 1)
    print("native large-space OK\n")
}
'@
    [IO.File]::WriteAllText((Join-Path $scratch 'stress.das'), $program)
    Push-Location $scratch
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $lines = & $Daslang 'stress.das' -no-module-cache 2>&1
        $code = $LASTEXITCODE
        $watch.Stop()
    } finally { Pop-Location }
    $text = $lines -join "`n"
    $lines | ForEach-Object { Write-Host $_ }
    $generated = [regex]::Matches($text, '(?m)^\[native\.generate\] .+$')
    if ($code -ne 0 -or $text -notmatch 'native large-space OK' -or $generated.Count -ne 2) {
        throw "Lazy native generation failed: exit=$code, generated=$($generated.Count)."
    }
    Write-Host "Catalog: $Count types; generated: 2 (Node0 + dependency Node1)."
    Write-Host "Compile + run: $($watch.ElapsedMilliseconds) ms (not an accessor benchmark)."
} finally {
    $workRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')) + [IO.Path]::DirectorySeparatorChar
    $resolved = (Resolve-Path -LiteralPath $scratch).Path
    if (-not $resolved.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing cleanup outside $workRoot"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
