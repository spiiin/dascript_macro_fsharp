options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/strings_boost
var reached=0
var closed=0
struct Handle {id:int}
def ce_dispose(handle:Handle) {closed++}

def request(fail:bool) {
    return <- computation(TaskResultBuilder(type<int>)) {
        let resource=Handle(id=1) |> use_resource
        let first=task_after_polls(1,result_ok(10)) |> bind
        reached++
        let second=task_after_polls(1,fail ? result_error("denied",type<int>) : result_ok(5)) |> bind
        reached++
        return first+second
    }
}
[export]
def main() {
    var inscope good <- request(false)
    verify(task_poll(good)==TaskStatus.Waiting)
    verify(task_poll(good)==TaskStatus.Waiting && reached==1 && closed==0)
    verify(task_poll(good)==TaskStatus.Succeeded && reached==2 && closed==1)
    let value=task_value(good)
    verify(value is ok && value as ok==15)
    reached=0
    var inscope bad <- request(true)
    verify(task_poll(bad)==TaskStatus.Waiting)
    verify(task_poll(bad)==TaskStatus.Waiting && reached==1)
    verify(task_poll(bad)==TaskStatus.Succeeded && reached==1 && closed==2)
    let failure=task_value(bad)
    verify(failure is error && failure as error=="denied")
    verify(task_poll(bad)==TaskStatus.Succeeded && reached==1 && closed==2)
    var inscope thrown <- computation(TaskResultBuilder(type<int>)) {
        let n=task_after_polls(1,result_ok(1)) |> bind
        panic("native failure")
        return n
    }
    verify(task_poll(thrown)==TaskStatus.Waiting)
    verify(task_poll(thrown)==TaskStatus.Failed)
    verify(starts_with(task_error(thrown),"native failure"))
    reached=0
    var inscope loop <- computation(TaskResultBuilder(type<int>)) {
        for(i in range(5)) {
            task_after_polls(1,i==2 ? result_error("stop loop",type<CeUnit>) : result_ok(CeUnit())) |> bind
            reached++
        }
        reached+=100
        return reached
    }
    var state=task_poll(loop)
    while(state==TaskStatus.Waiting) {state=task_poll(loop)}
    verify(state==TaskStatus.Succeeded && reached==2)
    let loopError=task_value(loop)
    verify(loopError is error && loopError as error=="stop loop")
    print("TaskResult checks OK\n")
}
