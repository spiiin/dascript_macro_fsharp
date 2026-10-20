options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
require daslib/rtti
require daslib/strings_boost
var opened=fixed_array(0,0)
var closed=fixed_array(0,0)
var polls=fixed_array(0,0)
var order=""
var continued=0
struct PendingState {remaining:int;data:array<int>}
def finalize(var state:PendingState) {delete state.data}

def owned(id,waits:int; value:auto(T); failNative:bool=false; failClose:bool=false) {
    opened[id]++
    var state=new PendingState(remaining=waits,data <- [1,2,3])
    return <- task_from_poll(@() {
        polls[id]++
        if(failNative) {panic("child {id} failed")}
        if(state.remaining>0) {state.remaining--;return task_pending(type<T -const -&>)}
        return task_ready(value)
    },@() {
        closed[id]++
        order+="{id};"
        unsafe {delete state}
        if(failClose) {panic("close {id} failed")}
    })
}
def reset() {
    verify(opened[0]==closed[0] && opened[1]==closed[1])
    for(v in opened) {v=0};for(v in closed) {v=0};for(v in polls) {v=0}
    order="";continued=0
}
def balanced() {verify(opened[0]==closed[0] && opened[1]==closed[1])}
def checks() {
    reset()
    {
        var inscope task <- task_when_all(owned(0,1,10),owned(1,2,"text"))
        verify(task_poll(task)==TaskStatus.Waiting && closed[0]==0 && closed[1]==0)
        verify(task_poll(task)==TaskStatus.Waiting && closed[0]==1 && closed[1]==0)
        verify(task_poll(task)==TaskStatus.Succeeded && order=="0;1;")
        let result=task_value(task)
        verify(result.first==10 && result.second=="text" && polls[0]==2 && polls[1]==3)
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,3,10),owned(1,3,20))
        verify(task_cancel(task) && order=="0;1;" && polls[0]==0 && polls[1]==0)
        verify(!task_cancel(task))
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,3,10),owned(1,3,20))
        verify(task_poll(task)==TaskStatus.Waiting && polls[0]==1 && polls[1]==1)
        verify(task_cancel(task) && order=="0;1;")
    }
    balanced();reset()
    {
        var inscope task <- task_result_when_all(owned(0,0,result_ok(1),failNative=true),owned(1,3,result_ok(2)))
        verify(task_poll(task)==TaskStatus.Failed && polls[1]==0 && order=="0;1;")
        verify(starts_with(task_error(task),"child 0 failed"))
    }
    balanced();reset()
    {
        var inscope task <- task_result_when_all(owned(0,0,result_error("denied",type<int>)),owned(1,3,result_ok(2),failClose=true))
        verify(task_poll(task)==TaskStatus.Failed && order=="0;1;")
        verify(starts_with(task_error(task),"close 1 failed"))
    }
    balanced();reset()
    {
        var inscope task <- task_race(owned(0,3,10),owned(1,1,20))
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded && order=="1;0;")
        verify(task_value(task).index==1 && task_value(task).value==20)
    }
    balanced();reset()
    {
        var inscope task <- task_race(owned(0,0,10),owned(1,0,20))
        verify(task_poll(task)==TaskStatus.Succeeded && polls[1]==0 && order=="0;1;")
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,0,10,true),owned(1,0,20))
        verify(task_poll(task)==TaskStatus.Failed && polls[1]==0 && order=="0;1;")
        verify(starts_with(task_error(task),"child 0 failed"))
    }
    balanced();reset()
    {
        var inscope task <- task_race(owned(0,3,10),owned(1,0,20,true))
        verify(task_poll(task)==TaskStatus.Failed && order=="1;0;")
        verify(starts_with(task_error(task),"child 1 failed"))
    }
    balanced();reset()
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let pair=task_result_when_all(owned(0,0,result_error("denied",type<int>)),owned(1,3,result_ok("text"))) |> bind
            continued++
            return pair.first
        }
        verify(task_poll(task)==TaskStatus.Succeeded && continued==0 && polls[1]==0)
        let result=task_value(task)
        verify(result is err && result as err=="denied" && order=="0;1;")
    }
    balanced();reset()
    {
        var inscope task <- task_result_when_all(owned(0,3,result_ok(1)),owned(1,0,result_error("right",type<string>)))
        verify(task_poll(task)==TaskStatus.Succeeded && order=="1;0;")
        let result=task_value(task)
        verify(result is err && result as err=="right")
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,3,10),owned(1,3,20))
        verify(task_poll(task)==TaskStatus.Waiting)
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,3,10,failClose=true),owned(1,3,20,failClose=true))
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && order=="0;1;")
        verify(starts_with(task_error(task),"close 0 failed"))
    }
    balanced();reset()
    {
        var inscope task <- task_when_all(owned(0,0,10,true),owned(1,3,20,failClose=true))
        verify(task_poll(task)==TaskStatus.Failed && order=="0;1;")
        verify(starts_with(task_error(task),"child 0 failed"))
    }
    balanced();reset()
    {
        var inscope task <- task_race(owned(0,0,10),owned(1,3,20,failClose=true))
        verify(task_poll(task)==TaskStatus.Failed && order=="0;1;")
        verify(starts_with(task_error(task),"close 1 failed"))
    }
    balanced();reset()
    {
        var inscope task <- owned(0,1,10)
        var caught=false
        try {var inscope invalid <- task_when_all(task,task)} recover {caught=true}
        verify(caught && task_status(task)==TaskStatus.Created)
        caught=false
        try {var inscope invalid <- task_race(task,task)} recover {caught=true}
        verify(caught && task_status(task)==TaskStatus.Created)
        verify(task_cancel(task))
    }
    balanced();reset()
    {
        var inscope first <- owned(0,1,10)
        verify(task_cancel(first))
        var inscope task <- task_when_all(first,owned(1,3,20))
        verify(task_poll(task)==TaskStatus.Cancelled && polls[1]==0)
        verify(empty(task_error(task)))
    }
    balanced()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task composition lifetime checks OK\n")
}
