options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
var ready=false
var closed=0
var continued=0

// A real I/O adapter checks an operation's completion here without blocking.
def response() {
    return <- task_from_poll(@() {
        return ready ? task_ready("response body") : task_pending(type<string>)
    },@() {
        // Release/unregister the operation's handle, or cancel it if pending.
        closed++
    })
}
[export]
def main() {
    var inscope request <- computation(TaskBuilder(type<string>)) {
        let body=response() |> bind
        continued++
        return "received: {body}"
    }
    verify(task_poll(request)==TaskStatus.Waiting && continued==0 && closed==0)
    // Simulate the host receiving an actual completion event.
    ready=true
    verify(task_poll(request)==TaskStatus.Succeeded && continued==1 && closed==1)
    let value=task_value(request)
    print("{value}\n")
    var inscope cancelled <- response()
    verify(task_cancel(cancelled) && closed==2)
    print("External task demo OK\n")
}
