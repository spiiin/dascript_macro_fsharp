options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/strings_boost
require daslib/rtti
var opened=fixed_array(0,0)
var closed=fixed_array(0,0)
var polls=fixed_array(0,0)
var continued=0
var recovered=0
var order=""
var group:CancellationToken
struct Payload {remaining:int; data:array<int>}
def finalize(var state:Payload) {delete state.data}

def owned(id,waits:int; value:auto(T); fail:bool=false; badClose:bool=false; request:bool=false) {
    opened[id]++
    var state=new Payload(remaining=waits,data <- [1,2,3])
    return <- task_from_poll(@() {
        polls[id]++
        if(fail) {panic("poll {id} failed")}
        if(request) {cancellation_cancel(group)}
        if(state.remaining>0) {state.remaining--;return task_pending(type<T -const -&>)}
        return task_ready(value)
    },@() {
        closed[id]++;order+="{id};"
        unsafe {delete state}
        if(badClose) {panic("close {id} failed")}
    })
}
def factory_failure() {panic("factory failed");return <- task_after_polls(0,1)}
def empty_failure() {panic("");return <- task_after_polls(0,1)}
def cancelled_child() {
    var child <- owned(0,3,1)
    task_cancel(child)
    return <- child
}
def reset() {
    verify(opened[0]==closed[0] && opened[1]==closed[1])
    for(v in opened) {v=0};for(v in closed) {v=0};for(v in polls) {v=0}
    continued=0;recovered=0;order=""
}

def checks() {
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,1,10) |> and_bind(owned(1,2,20)) |> bind
            continued++;return p.first+p.second
        }
        verify(task_poll(task)==TaskStatus.Waiting && closed[0]==0 && closed[1]==0)
        verify(task_poll(task)==TaskStatus.Waiting && closed[0]==1 && closed[1]==0)
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==30 && continued==1)
        verify(order=="0;1;" && polls[0]==2 && polls[1]==3)
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(owned(1,3,2)) |> bind
            continued++;return p.first
        }
        verify(task_cancel(task) && opened[0]==0 && opened[1]==0 && continued==0)
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(owned(1,3,2)) |> bind
            continued++;return p.first
        }
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_cancel(task) && order=="0;1;" && continued==0)
        verify(!task_cancel(task))
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,0,1,fail=true) |> and_bind(owned(1,3,2,badClose=true)) |> bind
            continued++;return p.first
        }
        verify(task_poll(task)==TaskStatus.Failed && continued==0 && polls[1]==0 && order=="0;1;")
        verify(starts_with(task_error(task),"poll 0 failed"))
    }
    reset()
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let p=owned(0,3,result_ok(1)) |> and_bind(owned(1,0,result_error("denied",type<int>))) |> bind
            continued++;return p.first+p.second
        }
        verify(task_poll(task)==TaskStatus.Succeeded && continued==0 && order=="1;0;")
        let value=task_value(task)
        verify(value is err && value as err=="denied")
    }
    reset()
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let p=owned(0,0,result_error("denied",type<int>)) |> and_bind(owned(1,3,result_ok(2),badClose=true)) |> bind
            continued++;return p.first
        }
        verify(task_poll(task)==TaskStatus.Failed && continued==0 && polls[1]==0 && order=="0;1;")
        verify(starts_with(task_error(task),"close 1 failed"))
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            try_with($ {
                let p=cancelled_child() |> and_bind(owned(1,3,2)) |> bind
                continued++;return p.first
            },$(message:string){recovered++;return 99})
        }
        verify(task_poll(task)==TaskStatus.Cancelled && recovered==0 && continued==0 && polls[1]==0)
    }
    reset()
    group <- cancellation_token()
    {
        var source <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,0,1,request=true) |> and_bind(owned(1,3,2)) |> bind
            continued++;return p.first
        }
        var inscope task <- task_with_cancellation(source,group)
        verify(task_poll(task)==TaskStatus.Cancelled && continued==0 && polls[1]==0 && order=="0;1;")
    }
    delete group;reset()
    {
        var inscope token <- cancellation_token()
        var source <- computation(TaskResultBuilder(type<int>)) {
            let p=owned(0,3,result_ok(1)) |> and_bind(owned(1,3,result_ok(2))) |> bind
            continued++;return p.first
        }
        var inscope task <- task_with_cancellation(source,token)
        verify(task_poll(task)==TaskStatus.Waiting)
        cancellation_cancel(token)
        verify(task_poll(task)==TaskStatus.Cancelled && order=="0;1;" && continued==0)
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1,badClose=true) |> and_bind(owned(1,3,2,badClose=true)) |> bind
            return p.first
        }
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && order=="0;1;")
        verify(starts_with(task_error(task),"close 0 failed"))
    }
    reset()
    {
        // A later factory throws before a merged owner exists; preserve its
        // error even when releasing the first factory's owner reports a fault.
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1,badClose=true) |> and_bind(factory_failure()) |> bind
            continued++;return p.first
        }
        verify(task_poll(task)==TaskStatus.Failed && opened[0]==1 && closed[0]==1 && polls[0]==0)
        verify(starts_with(task_error(task),"factory failed"))
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(empty_failure()) |> bind
            continued++;return p.first
        }
        verify(task_poll(task)==TaskStatus.Failed && continued==0 && opened[0]==1 && closed[0]==1)
    }
    reset()
    {
        // The first nested product is owned while the third factory executes.
        var inscope task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(owned(1,3,2)) |> and_bind(factory_failure()) |> bind
            return p.second
        }
        verify(task_poll(task)==TaskStatus.Failed && order=="0;1;" && polls[0]==0 && polls[1]==0)
    }
    reset()
    {
        var inscope scheduler <- task_scheduler(type<int>)
        var source <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(owned(1,3,2)) |> bind
            continued++;return p.first
        }
        let id=task_spawn(scheduler,source,TaskTimeout(after_ms=5))
        verify(task_tick(scheduler,0)==1)
        verify(task_tick(scheduler,5)==0 && task_status(scheduler,id)==TaskStatus.Cancelled)
        verify(task_timed_out(scheduler,id) && continued==0 && order=="0;1;")
    }
    reset()
    {
        var task <- computation(TaskBuilder(type<int>)) {
            let p=owned(0,3,1) |> and_bind(owned(1,3,2)) |> bind
            return p.first
        }
        verify(task_poll(task)==TaskStatus.Waiting)
        delete task
    }
    reset()
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            var left <- owned(0,0,1)
            var right <- owned(1,0,2)
            let p=left |> and_bind(right) |> bind
            continued++;return p.first+p.second
        }
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==3 && continued==1 && order=="0;1;")
    }
    reset()
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task and_bind lifetime checks OK\n")
}
