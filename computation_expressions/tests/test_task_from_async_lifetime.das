options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/async_boost
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
var parentOpened=0
var parentClosed=0
var after=0
var order=""
var callbackCount=0
struct Buffer {values:array<int>;id:int}
struct ParentResource {}
def finalize(var buffer:Buffer) {
    if(!empty(buffer.values)) {closed++;order+="child;";buffer.id=0}
    delete buffer.values
}
def acquire_parent() {parentOpened++;return ParentResource()}
def ce_dispose(value:ParentResource) {parentClosed++;order+="parent;"}

[async]
def borrowed_value(buffer:Buffer?; fail:bool) : int {
    await_next_frame()
    if(fail) {panic("owned async failed")}
    yield length(buffer.values)
    after++
}
[async]
def borrowed_error(buffer:Buffer?) : $Result<int;string> {
    await_next_frame()
    yield result_error("resource denied",type<int>)
    after++
}
[async]
def borrowed_void(buffer:Buffer?) : void {
    await_next_frame()
    after++
}
[async]
def borrowed_nested(buffer:Buffer?; fail:bool) : int {
    let n <- await(borrowed_value(buffer,fail))
    yield n+1
}
def owned_value(fail:bool) {
    opened++
    var buffer=new Buffer(values <- [1,2,3],id=opened)
    return <- task_from_async(borrowed_value(buffer,fail),@() {unsafe {delete buffer}})
}
def owned_error() {
    opened++
    var buffer=new Buffer(values <- [1,2,3],id=opened)
    return <- task_from_async(borrowed_error(buffer),@() {unsafe {delete buffer}})
}
def owned_void() {
    opened++
    var buffer=new Buffer(values <- [1,2,3],id=opened)
    return <- task_from_async(borrowed_void(buffer),@() {unsafe {delete buffer}})
}
def owned_nested(fail:bool) {
    opened++
    var buffer=new Buffer(values <- [1,2,3],id=opened)
    return <- task_from_async(borrowed_nested(buffer,fail),@() {unsafe {delete buffer}})
}
def parent(fail:bool) {
    return <- computation(TaskBuilder(type<int>)) {
        let handle=acquire_parent() |> use_resource
        let n=owned_value(fail) |> bind
        order+="continue;"
        return n+1
    }
}
def ownership_checks() {
    {
        let before=opened
        var inscope never <- owned_value(false)
        verify(opened==before+1 && opened==closed+1)
        verify(task_cancel(never) && opened==closed)
        verify(!task_cancel(never))
    }
    {
        let before=after
        var inscope waiting <- owned_value(false)
        verify(task_poll(waiting)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(waiting) && opened==closed && after==before)
        verify(task_poll(waiting)==TaskStatus.Cancelled)
    }
    {
        let before=after
        var inscope good <- owned_value(false)
        verify(task_poll(good)==TaskStatus.Waiting)
        verify(task_poll(good)==TaskStatus.Succeeded && opened==closed && after==before+1)
        verify(task_value(good)==3)
        verify(task_poll(good)==TaskStatus.Succeeded && after==before+1)
    }
    {
        var inscope failed <- owned_value(true)
        verify(task_poll(failed)==TaskStatus.Waiting)
        verify(task_poll(failed)==TaskStatus.Failed && opened==closed)
        verify(starts_with(task_error(failed),"owned async failed"))
    }
    {
        order=""
        var inscope task <- parent(false)
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==4)
        verify(order=="child;continue;parent;" && opened==closed && parentOpened==parentClosed)
    }
    {
        order=""
        var inscope task <- parent(false)
        verify(task_poll(task)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(task))
        verify(order=="child;parent;" && opened==closed && parentOpened==parentClosed)
    }
    {
        order=""
        var inscope task <- parent(true)
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Failed)
        verify(order=="child;parent;" && opened==closed && parentOpened==parentClosed)
    }
    {
        order=""
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let handle=acquire_parent() |> use_resource
            let n=owned_error() |> bind
            order+="unreachable;"
            return n
        }
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded)
        let result=task_value(task)
        verify(result is err && result as err=="resource denied")
        verify(order=="child;parent;" && opened==closed && parentOpened==parentClosed)
    }
    {
        var inscope task <- owned_void()
        verify(task_poll(task)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(task) && opened==closed)
    }
    {
        var inscope task <- owned_void()
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded && opened==closed)
    }
    {
        var inscope task <- owned_nested(false)
        verify(task_poll(task)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(task) && opened==closed)
    }
    {
        var inscope task <- owned_nested(false)
        var status=task_poll(task)
        while(status==TaskStatus.Waiting) {status=task_poll(task)}
        verify(status==TaskStatus.Succeeded && task_value(task)==4 && opened==closed)
    }
    {
        var inscope task <- owned_nested(true)
        var status=task_poll(task)
        while(status==TaskStatus.Waiting) {status=task_poll(task)}
        verify(status==TaskStatus.Failed && opened==closed)
    }
    {
        var inscope abandoned <- owned_value(false)
        verify(task_poll(abandoned)==TaskStatus.Waiting)
    }
    verify(opened==closed) // Normal scope exit closes a pending owner too.
    for(i in range(3)) {
        var inscope task <- owned_nested(false)
        verify(task_poll(task)==TaskStatus.Waiting)
        break
    }
    verify(opened==closed)
    {
        var task <- owned_nested(false)
        var caught=false
        try {
            task_scope(task,$(var owner) {
                verify(task_poll(owner)==TaskStatus.Waiting)
                panic("driver failed")
            })
        } recover {caught=starts_with("{this_context().last_exception}","driver failed")}
        verify(caught && opened==closed)
    }
}
[export]
def main() {
    ownership_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {ownership_checks()}
    verify(heap_bytes_allocated()==baseline)
    verify(opened==closed && parentOpened==parentClosed)
    {
        var inscope task <- task_from_async(borrowed_value(null,false),@() {callbackCount++;panic("close failed")})
        // Cancel before entering borrowed_value: the null handle is never read.
        verify(task_cancel(task) && task_status(task)==TaskStatus.Failed && callbackCount==1)
        verify(starts_with(task_error(task),"close failed"))
        verify(!task_cancel(task) && callbackCount==1)
    }
    print("Task async adapter lifetime checks OK\n")
}
