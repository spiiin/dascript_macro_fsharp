param([string]$Daslang=$env:DASLANG_EXE,[string]$OutputDirectory=(Join-Path $PSScriptRoot '.work'))
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.4/daslang_bundle/bin/daslang.exe'}
$destination=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('integration-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'export_library.ps1') -Destination $destination
$expected=@(Get-Content (Join-Path $PSScriptRoot 'public_modules.json') -Raw|ConvertFrom-Json)
$actual=@(Get-ChildItem (Join-Path $destination 'lib') -Filter '*.das'|Select-Object -ExpandProperty Name)
if(@(Compare-Object $expected $actual).Count){throw 'Export has unexpected modules'}
foreach($file in @('README.md','PUBLIC_API.md','TASKS.md','TASK_COMPOSITION.md','TASK_SCHEDULER.md','TASK_CANCELLATION.md','TASK_DELAY.md','TASK_ARRAY.md','TASK_AND_BIND.md','TASK_COMPLETION.md','TASK_TCP.md','TASK_HV.md','AOT_RUNTIME.md','aot_host/main.cpp','aot_host/CMakeLists.txt','aot_host/recover_064.h','main.das','identity_builder.das','manifest.json')){
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
require ./lib/task_builder.das
require ./lib/task_combinators.das
require ./lib/task_scheduler.das
require daslib/async_boost
[async]
def standard_value() : int {await_next_frame();yield 12}
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
    var inscope asyncTask <- computation(TaskResultBuilder(type<int>)) {
        let n=task_after_polls(1,result_ok(8)) |> bind
        return n+1
    }
    verify(task_poll(asyncTask)==TaskStatus.Waiting)
    verify(task_poll(asyncTask)==TaskStatus.Succeeded)
    let outcome=task_value(asyncTask)
    verify(outcome is ok && outcome as ok==9)
    var inscope adapted <- computation(TaskBuilder(type<int>)) {
        let n=task_from_async(standard_value()) |> bind
        return n+1
    }
    verify(task_poll(adapted)==TaskStatus.Waiting)
    verify(task_poll(adapted)==TaskStatus.Succeeded && task_value(adapted)==13)
    var inscope together <- computation(TaskBuilder(type<int>)) {
        let pair=task_from_async(standard_value()) |> and_bind(task_after_polls(1,5)) |> bind
        return pair.first+pair.second
    }
    verify(task_poll(together)==TaskStatus.Waiting)
    verify(task_poll(together)==TaskStatus.Succeeded && task_value(together)==17)
    var inscope scheduler <- task_scheduler(type<int>)
    let id=task_spawn(scheduler,task_after_polls(0,42))
    verify(task_tick(scheduler,0)==0 && task_value(scheduler,id)==42)
    verify(task_prune(scheduler)==1)
    let expired=task_spawn(scheduler,task_after_polls(10,7),TaskTimeout(after_ms=5))
    verify(task_tick(scheduler,5)==0 && task_timed_out(scheduler,expired))
    verify(task_status(scheduler,expired)==TaskStatus.Cancelled)
    var inscope group <- cancellation_token()
    var inscope guarded <- task_with_cancellation(task_after_polls(10,4),group)
    verify(task_poll(guarded)==TaskStatus.Waiting)
    verify(cancellation_cancel(group))
    verify(task_poll(guarded)==TaskStatus.Cancelled)
    var delayTask <- computation(TaskBuilder(type<int>)) {task_delay_ms(5) |> bind;return 3}
    let delayed=task_spawn(scheduler,delayTask)
    verify(task_tick(scheduler,10)==1)
    verify(task_tick(scheduler,15)==0 && task_value(scheduler,delayed)==3)
    var inscope arrays <- task_scheduler(type<array<int>>)
    var jobs:array<typedecl(task_after_polls(0,0))>
    jobs |> emplace(task_after_polls(1,3))
    jobs |> emplace(task_after_polls(0,4))
    let batch=task_spawn(arrays,task_when_all(jobs))
    verify(task_tick(arrays,0)==1 && task_tick(arrays,1)==0)
    var inscope values <- task_value(arrays,batch)
    verify(values[0]==3 && values[1]==4)
    print("Public module integration OK\n")
}
'@
$path=Join-Path $destination 'smoke.das'
[IO.File]::WriteAllText($path,$smoke)
& $Daslang $path -no-module-cache
if($LASTEXITCODE -ne 0){throw 'Public module smoke failed'}
Write-Host "Standalone export verified: $destination"

# Optional adapter is checked from the exported package, not the checkout.
$hvSmoke=@'
options gen2
require ./lib/task_hv.das
[export]
def main() {
    var inscope socket <- hv_websocket()
    var inscope job <- ws_connect(socket,"invalid-url")
    verify(task_poll(job)==TaskStatus.Succeeded && task_value(job) is error)
    print("Exported dasHV adapter OK\n")
}
'@
$hvPath=Join-Path $destination 'hv_smoke.das'
[IO.File]::WriteAllText($hvPath,$hvSmoke)
& $Daslang $hvPath -no-module-cache
if($LASTEXITCODE -ne 0){throw 'Exported dasHV adapter failed'}
