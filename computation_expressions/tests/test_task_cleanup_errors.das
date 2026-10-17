options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/async_boost
require daslib/rtti
require daslib/strings_boost
var closed=0

def failing_close(wait:bool) {
    return <- task_from_poll(@() {return wait ? task_pending(type<int>) : task_ready(7)},@() {closed++;panic("close failed")})
}
[async]
def standard_source() : int {await_next_frame();yield 9}
def failing_async() {
    return <- task_from_async(standard_source(),@() {closed++;panic("async close failed")})
}
def checks() {
    let before=closed
    {
        var inscope task <- failing_close(false)
        verify(task_poll(task)==TaskStatus.Failed && closed==before+1)
        verify(starts_with(task_error(task),"close failed"))
    }
    {
        var inscope task <- failing_close(true)
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && closed==before+2)
    }
    {
        var inscope parent <- computation(TaskBuilder(type<int>)) {
            let n=failing_close(true) |> bind
            return n
        }
        verify(task_poll(parent)==TaskStatus.Waiting)
        verify(task_cancel(parent) && task_status(parent)==TaskStatus.Failed && closed==before+3)
        verify(starts_with(task_error(parent),"close failed"))
    }
    {
        var inscope task <- failing_async()
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Failed && closed==before+4)
        verify(starts_with(task_error(task),"async close failed"))
    }
    {
        var inscope task <- failing_async()
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && closed==before+5)
    }
    {
        var task <- failing_close(true)
        var caught=false
        try {task_scope(task,$(var owner) {verify(task_poll(owner)==TaskStatus.Waiting)})} recover {caught=starts_with("{this_context().last_exception}","close failed")}
        verify(caught && closed==before+6)
    }
    {
        var task <- failing_close(true)
        var caught=false
        try {task_scope(task,$(var owner) {verify(task_poll(owner)==TaskStatus.Waiting);panic("driver failed")})} recover {caught=starts_with("{this_context().last_exception}","driver failed")}
        verify(caught && closed==before+7)
    }
    // A raw destructor has no surviving Task to report an error to. Its callback
    // is still released without throwing out of a native generator finalizer.
    {var inscope task <- failing_close(true)}
    verify(closed==before+8)
    var inscope clean <- task_after_polls(0,10)
    verify(task_poll(clean)==TaskStatus.Succeeded && task_value(clean)==10)
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task cleanup error checks OK\n")
}
