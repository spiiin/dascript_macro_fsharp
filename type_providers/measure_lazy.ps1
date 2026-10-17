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
# A fresh, uniquely named test directory; never alter the user's example schemas.
$scratch = Join-Path $PSScriptRoot ('.work/lazy-' + [guid]::NewGuid().ToString('N'))
$space = Join-Path $scratch 'space'
New-Item -ItemType Directory -Path $space -Force | Out-Null
try {
    foreach ($name in @('erased_provider.das', 'erased_runtime.das', 'provider_runtime.das')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $scratch
    }
    for ($i = 0; $i -lt $Count; $i++) {
        $next = ($i + 1) % $Count
        $schema = '{"fields":[{"name":"id","type":"int"},{"name":"next","type":"ref","target":"Node' + $next + '"}]}'
        [IO.File]::WriteAllText((Join-Path $space "Node$i.json"), $schema)
    }
    $program = @'
options gen2
require erased_provider
[export]
def main() {
    var error : string
    var node = read_json("\{\"id\":0,\"next\":\{\"id\":1\}\}", error)
    {
        let first : int = erased(node, "space", "Node0", _.id)
        let next : int = erased(node, "space", "Node0", _.next.id)
        let repeated : int = erased(node, "space", "Node0", _.next.id)
        assert(first == 0 && next == 1 && repeated == 1)
        print("large-space OK\n")
    } finally { delete_json(node) }
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
    $loads = [regex]::Matches($text, '(?m)^\[erased\.load\] .+$')
    if ($code -ne 0 -or $text -notmatch 'large-space OK' -or $loads.Count -ne 2) {
        throw "Lazy expansion failed: exit=$code, loaded=$($loads.Count)."
    }
    Write-Host "Catalog: $Count types; loaded: 2; emitted nominal types: 0."
    Write-Host "Compile + run: $($watch.ElapsedMilliseconds) ms (includes compiler startup; not an accessor benchmark)."
} finally {
    # Check the resolved absolute target before recursive deletion.
    $workRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')) + [IO.Path]::DirectorySeparatorChar
    $resolved = (Resolve-Path -LiteralPath $scratch).Path
    if (-not $resolved.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing cleanup outside $workRoot"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
