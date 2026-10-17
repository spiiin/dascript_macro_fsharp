options gen2
require ../support/move_resource_support.das
require ../lib/deferred_computation.das
[export]
def main() {
    let uploaded=computation(ResultBuilder()) {
        var buffer & = acquire_buffer(1) |> use_resource
        buffer.data |> push(99)
        return length(buffer.data)
    }
    assert(uploaded as ok==4 && resources_opened==resources_closed)
    var inscope task <- deferred(SequenceBuilder(),[2,3]) $(snapshot) {
        var buffer & = acquire_buffer(snapshot[0]) |> use_resource
        for(value in buffer.data) {yield value}
    }
    var inscope first <- run_deferred(task)
    var inscope second <- run_deferred(task)
    delete task
    for(value in first) {assert(value==2);break}
    sequence_each(second) $(value:int) {print("{value}\n")}
    assert(resources_opened==resources_closed)
    print("move-only resources demo OK\n")
}
