options gen2
options max_infer_passes=128
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das

def batches() {
    return <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        for(i in range(3)) {
            var batch <- [i,i+10]
            task_delay_ms(5) |> bind
            yield <- batch
        }
    }
}
def sum_batches() {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = batches() |> use_resource
        var sum=0
        while(true) {
            var item & = async_sequence_next(stream) |> bind
            if(item is none) {break}
            // Borrow the payload while this bind owns its next-Task.
            for(value in item as some) {sum+=value}
        }
        return sum
    }
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>)
    let id=task_spawn(scheduler,sum_batches(),TaskTimeout(after_ms=100))
    for(now in range(30)) {task_tick(scheduler,now)}
    verify(task_status(scheduler,id)==TaskStatus.Succeeded && task_value(scheduler,id)==36)
    print("Async sequence move demo OK\n")
}
