options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
require daslib/strings_boost
var effects=0
var recovered=0
var closed=0
var group:CancellationToken

def cancelled_child() {
    var task <- task_after_polls(1,7)
    verify(task_cancel(task))
    return <- task
}
def layer(var child:auto) {
    unsafe {
        return <- computation(TaskBuilder(type<int>)) {
            let n=child |> bind
            effects++
            return n+1
        }
    }
}
def checks() {
    let before=effects
    {
        var inscope task <- layer(layer(layer(cancelled_child())))
        verify(task_poll(task)==TaskStatus.Cancelled && effects==before)
        verify(empty(task_error(task)) && task_poll(task)==TaskStatus.Cancelled)
    }
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            try_with($ {
                let n=cancelled_child() |> bind
                effects++
                return n
            },$(message:string){recovered++;return 99})
        }
        verify(task_poll(task)==TaskStatus.Cancelled && recovered==0 && effects==before)
    }
    group <- cancellation_token()
    {
        // Request from a callback just before Ready: no surrounding bind
        // continuation may run, even with three layers of task_poll.
        var request <- task_from_poll(@(){cancellation_cancel(group);return task_ready(4)},@(){closed++})
        var inscope task <- task_with_cancellation(layer(layer(request)),group)
        verify(task_poll(task)==TaskStatus.Cancelled && effects==before && closed==1)
    }
    delete group
    group <- cancellation_token()
    {
        // A request made while the Ready child's cleanup runs is also observed
        // before exposing its value to a continuation.
        var request <- task_from_poll(@(){return task_ready(4)},@(){cancellation_cancel(group);closed++})
        var inscope task <- task_with_cancellation(layer(request),group)
        verify(task_poll(task)==TaskStatus.Cancelled && effects==before && closed==2)
    }
    delete group
    {
        var inscope token <- cancellation_token()
        verify(cancellation_cancel(token) && !cancellation_cancel(token))
        var inscope task <- task_with_cancellation(layer(task_after_polls(0,5)),token)
        verify(task_poll(task)==TaskStatus.Cancelled && effects==before)
    }
    {
        var inscope token <- cancellation_token()
        var source <- computation(TaskResultBuilder(type<int>)) {
            var child <- task_after_polls(1,result_ok(1))
            task_cancel(child)
            let n=child |> bind
            effects++
            return n
        }
        var inscope task <- task_with_cancellation(source,token)
        verify(task_poll(task)==TaskStatus.Cancelled && effects==before)
    }
    {
        var inscope token <- cancellation_token()
        var inscope task <- task_with_cancellation(task_after_polls(0,7),token)
        verify(task_poll(task)==TaskStatus.Succeeded)
        verify(cancellation_cancel(token))
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==7)
    }
    group <- cancellation_token()
    {
        var source <- task_from_poll(@(){cancellation_cancel(group);panic("native failure");return task_ready(4)},@(){})
        var inscope task <- task_with_cancellation(source,group)
        verify(task_poll(task)==TaskStatus.Failed)
        verify(starts_with(task_error(task),"native failure"))
    }
    delete group
    var inscope unrelated <- task_after_polls(0,17)
    verify(task_poll(unrelated)==TaskStatus.Succeeded && task_value(unrelated)==17)
    {
        var inscope outer <- cancellation_token()
        var inscope inner <- cancellation_token()
        var inscope task <- task_with_cancellation(task_with_cancellation(task_after_polls(10,4),inner),outer)
        verify(task_poll(task)==TaskStatus.Waiting)
        cancellation_cancel(outer)
        verify(task_poll(task)==TaskStatus.Cancelled && !cancellation_requested(inner))
    }
}
[export]
def main() {
    checks()
    var inscope all <- task_when_all(cancelled_child(),task_after_polls(20,4))
    verify(task_poll(all)==TaskStatus.Cancelled)
    var inscope race <- task_race(cancelled_child(),task_after_polls(0,4))
    verify(task_poll(race)==TaskStatus.Cancelled)
    print("Task cancellation checks OK\n")
}
