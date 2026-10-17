options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
require daslib/strings_boost
var trace=""
var reached=0

def child(name:string; waits,value:int; fail:bool=false) {
    return <- computation(TaskBuilder(type<int>)) {
        trace+="{name}:start;"
        let n=task_after_polls(waits,value) |> bind
        trace+="{name}:done;"
        if(fail) {panic("child failed")}
        return n
    }
}
[export]
def main() {
    var inscope both <- task_when_all(child("a",1,10),child("b",2,20))
    verify(trace=="")
    verify(task_poll(both)==TaskStatus.Waiting && trace=="a:start;b:start;")
    verify(task_poll(both)==TaskStatus.Waiting && trace=="a:start;b:start;a:done;")
    verify(task_poll(both)==TaskStatus.Succeeded && trace=="a:start;b:start;a:done;b:done;")
    let pair=task_value(both)
    verify(pair.first==10 && pair.second==20)
    verify(task_poll(both)==TaskStatus.Succeeded && trace=="a:start;b:start;a:done;b:done;")
    trace=""
    var inscope race <- task_race(child("a",2,10),child("b",0,20))
    verify(task_poll(race)==TaskStatus.Succeeded && trace=="a:start;b:start;b:done;")
    let winner=task_value(race)
    verify(winner.index==1 && winner.value==20)
    trace=""
    var inscope tie <- task_race(child("a",0,1),child("b",0,2))
    verify(task_poll(tie)==TaskStatus.Succeeded && trace=="a:start;a:done;")
    verify(task_value(tie).index==0)
    var inscope mixed <- task_when_all(task_after_polls(0,7),task_after_polls(0,"text"))
    verify(task_poll(mixed)==TaskStatus.Succeeded)
    verify(task_value(mixed).first==7 && task_value(mixed).second=="text")
    var inscope good <- computation(TaskResultBuilder(type<int>)) {
        let values=task_result_when_all(task_after_polls(1,result_ok(3)),task_after_polls(0,result_ok(4))) |> bind
        reached++
        return values.first+values.second
    }
    verify(task_poll(good)==TaskStatus.Waiting)
    verify(task_poll(good)==TaskStatus.Succeeded && reached==1)
    let success=task_value(good)
    verify(success is ok && success as ok==7)
    trace=""
    var inscope failed <- task_when_all(child("a",0,1,true),child("b",0,2))
    verify(task_poll(failed)==TaskStatus.Failed && trace=="a:start;a:done;")
    verify(starts_with(task_error(failed),"child failed"))
    print("Task composition checks OK\n")
}
