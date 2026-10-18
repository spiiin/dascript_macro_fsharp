options gen2
options max_infer_passes=256
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das

def source() {
    return <- computation(AsyncSequenceBuilder()) {
        for(i in range(4)) {
            let value=task_after_polls(1,i) |> bind
            yield value
        }
    }
}
def mapped() {
    return <- computation(AsyncSequenceBuilder()) {
        for(value in source()) {yield value+1}
    }
}
[export]
def main() {
    var inscope stream <- mapped()
    var inscope request <- async_sequence_next(stream)
    while(task_poll(request)==TaskStatus.Waiting) {}
    verify(task_value(request) is some)
}
