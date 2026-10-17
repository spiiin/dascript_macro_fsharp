options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/async_boost
var closed=0
struct Request {bytes:array<int>}

// The standard async function borrows a stable heap handle. The adapter owns it.
[async]
def standard_read(request:Request?) : int {
    await_next_frame()
    yield length(request.bytes)
}
def read_request() {
    var request=new Request(bytes <- [10,20,30])
    return <- task_from_async(standard_read(request),@() {
        unsafe {delete request}
        closed++
    })
}
[export]
def main() {
    var inscope completed <- computation(TaskBuilder(type<int>)) {
        let count=read_request() |> bind
        verify(closed==1) // Child cleanup precedes the continuation.
        return count
    }
    verify(task_poll(completed)==TaskStatus.Waiting && closed==0)
    verify(task_poll(completed)==TaskStatus.Succeeded && task_value(completed)==3 && closed==1)
    var inscope cancelled <- read_request()
    verify(task_poll(cancelled)==TaskStatus.Waiting)
    verify(task_cancel(cancelled) && closed==2)
    var inscope neverStarted <- read_request()
    verify(task_cancel(neverStarted) && closed==3)
    print("Task async resources demo OK\n")
}
