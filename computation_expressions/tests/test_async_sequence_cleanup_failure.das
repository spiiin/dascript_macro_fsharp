options gen2
options max_infer_passes=512
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
require daslib/rtti
var allocated=0
var freed=0
var order=""
struct Resource {id:int;data:array<int>;fail:bool}
def acquire(id:int;fail:bool) {allocated++;return <- Resource(id=id,data <- [42],fail=fail)}
def ce_dispose(var value:Resource) {
    order+="{value.id};";freed++
    let fail=value.fail;delete value
    if(fail) {panic("resource cleanup failed")}
}
def producer() {
    return <- computation(AsyncSequenceBuilder()) {
        var outer & = acquire(1,false) |> use_resource
        var inner & = acquire(2,true) |> use_resource
        task_after_polls(3,0) |> bind
        yield 10
    }
}
def work(wait:int) {
    return <- computation(TaskBuilder(type<int>)) {
        var outer & = acquire(1,false) |> use_resource
        var inner & = acquire(2,true) |> use_resource
        let n=task_after_polls(wait,7) |> bind
        return n
    }
}
def checks() {
    order=""
    {
        var stream <- producer()
        var request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Waiting)
        verify(task_cancel(request) && task_status(request)==TaskStatus.Failed)
        delete request;ce_dispose(stream)
        verify(order=="2;1;" && allocated==freed)
    }
    for(mode in range(2)) {
        order=""
        var task <- work(mode==0 ? 0 : 10)
        if(mode==0) {verify(task_poll(task)==TaskStatus.Failed)}
        else {verify(task_poll(task)==TaskStatus.Waiting);verify(task_cancel(task) && task_status(task)==TaskStatus.Failed)}
        delete task
        verify(order=="2;1;" && allocated==freed)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(8)) {checks()}
    verify(heap_bytes_allocated()==baseline && allocated==freed)
    print("Async sequence cleanup failure checks OK\n")
}
