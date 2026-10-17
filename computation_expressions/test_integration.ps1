param([string]$Daslang=$env:DASLANG_EXE,[string]$OutputDirectory=(Join-Path $PSScriptRoot '.work'))
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$destination=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('integration-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'export_library.ps1') -Destination $destination
$expected=@(Get-Content (Join-Path $PSScriptRoot 'public_modules.json') -Raw|ConvertFrom-Json)
$actual=@(Get-ChildItem (Join-Path $destination 'lib') -Filter '*.das'|Select-Object -ExpandProperty Name)
if(@(Compare-Object $expected $actual).Count){throw 'Export has unexpected modules'}
foreach($file in @('README.md','PUBLIC_API.md','main.das','identity_builder.das','manifest.json')){
    if(-not(Test-Path -LiteralPath (Join-Path $destination $file))){throw "Incomplete export: $file"}
}
& $Daslang (Join-Path $destination 'main.das') -no-module-cache
if($LASTEXITCODE -ne 0){throw 'Minimal external builder failed'}
$smoke=@'
options gen2
require ./lib/computation.das
require ./lib/validation_builder.das
require ./lib/reader_result_builder.das
require ./lib/deferred_computation.das
[export]
def main() {
    let state=computation(StateBuilder(5)) {
        state_modify($(n:int){return n+2}) |> bind
        let value=state_gets($(n:int){return n*2}) |> bind
        return value
    }
    assert(state.state==7 && state.value==14)
    let reader=computation(ReaderResultBuilder(6)) {let n=reader_ask() |> bind;return n+1}
    assert(reader as ok==7)
    let check=computation(ValidationBuilder()) {
        let p=validation_ok(2) |> and_bind(validation_ok(3)) |> bind
        return p.first+p.second
    }
    assert(check as valid==5)
    var inscope owned <- computation(MoveResultBuilder()) {
        var items & = move_ok([1,2]) |> bind
        return <- items
    }
    assert(length(owned as ok)==2)
    var inscope task <- deferred(ListBuilder(),3) $(n) {
        for(i in range(n)){yield i}
    }
    var inscope first <- run_deferred(task)
    var inscope second <- run_deferred(task)
    assert(length(first)==3 && length(second)==3)
    print("Public module integration OK\n")
}
'@
$path=Join-Path $destination 'smoke.das'
[IO.File]::WriteAllText($path,$smoke)
& $Daslang $path -no-module-cache
if($LASTEXITCODE -ne 0){throw 'Public module smoke failed'}
Write-Host "Standalone export verified: $destination"
