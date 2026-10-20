options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
var trace=""
var continued=0

def child(name:string; waits:int; value:auto(T)) {
    trace+="{name}:create;"
    return <- computation(TaskBuilder(type<T>)) {
        trace+="{name}:start;"
        let n=task_after_polls(waits,value) |> bind
        trace+="{name}:done;"
        return n
    }
}

// External resumable builders can override grouping through the same hook.
struct ReverseTasks {}
def ce_protocol(builder:ReverseTasks) {return ce_protocol(TaskBuilder(type<int>))}
def ce_sequence_run(builder:ReverseTasks; var source:auto) {return <- task_create(source)}
def ce_await_pending(builder:ReverseTasks) {return task_pending(type<int>)}
def ce_await_return(builder:ReverseTasks; value:int) {return task_ready(value)}
def ce_await_value(builder:ReverseTasks; event:auto) {return event.value}
def ce_await_failed(builder:ReverseTasks; event:auto) {return false}
def ce_await_failure(builder:ReverseTasks; event:auto) {return task_pending(type<int>)}
def ce_merge_sources(builder:ReverseTasks; var left,right:auto) {return <- task_when_all(right,left)}

[export]
def main() {
    var inscope task <- computation(TaskBuilder(type<int>)) {
        let p=child("a",1,10) |> and_bind(child("b",2,20)) |> bind
        trace+="continue;"
        return p.first+p.second
    }
    verify(trace=="")
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(trace=="a:create;b:create;a:start;b:start;")
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(trace=="a:create;b:create;a:start;b:start;a:done;")
    verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==30)
    verify(trace=="a:create;b:create;a:start;b:start;a:done;b:done;continue;")
    let saved=trace
    verify(task_poll(task)==TaskStatus.Succeeded && trace==saved)
    var inscope nested <- computation(TaskBuilder(type<int>)) {
        let p=task_after_polls(0,1) |> and_bind(task_after_polls(0,2)) |> and_bind(task_after_polls(0,3)) |> bind
        let q=task_after_polls(0,4) |> and_bind(task_after_polls(0,5) |> and_bind(task_after_polls(0,6))) |> bind
        return p.first.first+p.first.second+p.second+q.first+q.second.first+q.second.second
    }
    verify(task_poll(nested)==TaskStatus.Succeeded && task_value(nested)==21)
    var inscope success <- computation(TaskResultBuilder(type<int>)) {
        let p=task_after_polls(1,result_ok(3)) |> and_bind(task_after_polls(0,result_ok("abc"))) |> bind
        continued++
        return p.first+length(p.second)
    }
    verify(task_poll(success)==TaskStatus.Waiting && continued==0)
    verify(task_poll(success)==TaskStatus.Succeeded && continued==1)
    let ok=task_value(success)
    verify(ok is ok && ok as ok==6)
    trace=""
    var inscope failed <- computation(TaskResultBuilder(type<int>)) {
        let p=child("a",0,result_error("denied",type<int>)) |> and_bind(child("b",0,result_ok(2))) |> bind
        continued++
        return p.first+p.second
    }
    verify(task_poll(failed)==TaskStatus.Succeeded && continued==1)
    let error=task_value(failed)
    verify(error is err && error as err=="denied")
    verify(trace=="a:create;b:create;a:start;a:done;")
    var inscope data <- computation(TaskBuilder(type<int>)) {
        let p=task_after_polls(0,result_error("data",type<int>)) |> and_bind(task_after_polls(0,2)) |> bind
        return p.first is err ? p.second : 0
    }
    verify(task_poll(data)==TaskStatus.Succeeded && task_value(data)==2)
    var inscope custom <- computation(ReverseTasks()) {
        let p=task_after_polls(0,3) |> and_bind(task_after_polls(0,7)) |> bind
        return p.first*10+p.second
    }
    verify(task_poll(custom)==TaskStatus.Succeeded && task_value(custom)==73)
    var inscope groupedResult <- computation(TaskResultBuilder(type<int>)) {
        let p=task_after_polls(0,result_ok(1)) |> and_bind(task_after_polls(0,result_ok(2))) |> and_bind(task_after_polls(0,result_ok(3))) |> bind
        return p.first.first+p.first.second+p.second
    }
    verify(task_poll(groupedResult)==TaskStatus.Succeeded)
    let groupedValue=task_value(groupedResult)
    verify(groupedValue is ok && groupedValue as ok==6)
    var inscope unit <- computation(TaskBuilder(type<int>)) {
        for(i in range(2)) {
            task_after_polls(1,CeUnit()) |> and_bind(task_after_polls(0,CeUnit())) |> bind
            continued++
        }
        return 42
    }
    verify(task_poll(unit)==TaskStatus.Waiting && continued==1)
    verify(task_poll(unit)==TaskStatus.Waiting && continued==2)
    verify(task_poll(unit)==TaskStatus.Succeeded && continued==3 && task_value(unit)==42)
    print("Task and_bind checks OK\n")
}
