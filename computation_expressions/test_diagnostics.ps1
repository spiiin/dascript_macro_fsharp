param([string]$Daslang=$env:DASLANG_EXE)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'source_paths.ps1')
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$cases=@(
    @{File='test_and_bind_unsupported.das';Message='and_bind is unsupported for builder';Marker='and_bind';ExactErrors=1},
    @{File='test_and_bind_mixed.das';Message='and_bind is unsupported for builder';Marker='and_bind';ExactErrors=1},
    @{File='test_move_copy.das';Message="value must be moved; use 'return <- value'";Marker='return items';ExactErrors=0}
)
Push-Location $PSScriptRoot
try {
    foreach($case in $cases) {
        $file=Get-CeSource $case.File
        $source=@(Get-Content -LiteralPath $file)
        $line=1+(@(0..($source.Count-1) | Where-Object {$source[$_].Contains($case.Marker)})|Select-Object -Last 1)
        $lines=@(& $Daslang $file -no-module-cache 2>&1)
        $code=$LASTEXITCODE
        $text=$lines -join "`n"
        if($code -eq 0 -or -not $text.Contains($case.Message)){throw "Missing diagnostic: $($case.File)"}
        # Check the compiler's standalone source-location line, not a filename embedded in the message.
        if($text -notmatch ('(?m)^[^\r\n]*'+[regex]::Escape($case.File)+':'+$line+':\d+\s*$')){throw "Diagnostic not anchored to user line: $($case.File)"}
        if($case.ExactErrors -gt 0 -and [regex]::Matches($text,'(?m)^error\[').Count -ne $case.ExactErrors){throw "Cascading diagnostics: $($case.File)"}
        if($text -match 'macro caused exception|macro integration error'){throw "Internal macro failure: $($case.File)"}
        Write-Host "Diagnostic anchored: $($case.File):$line"
    }
} finally {Pop-Location}
