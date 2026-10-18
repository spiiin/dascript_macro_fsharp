options gen2
options max_infer_passes=256
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
require ../lib/task_scheduler.das

def fetch_value(value:int;delay:int) {
    return <- computation(TaskBuilder(type<int>)) {
        task_delay_ms(delay) |> bind
        return value
    }
}

def updates() {
    return <- computation(AsyncSequenceBuilder(type<string>)) {
        for(turn in range(2)) {
            let pair=fetch_value(100+turn,3) |> and_bind(fetch_value(50+turn,5)) |> bind
            yield "health={pair.first}, mana={pair.second}"
        }
    }
}

[export]
def main() {
    var inscope stream <- updates()
    var inscope scheduler <- task_scheduler(type<variant<some:string;none:bool>>)
    var now:int64=0
    var count=0
    while(true) {
        let id=task_spawn(scheduler,async_sequence_next(stream))
        while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
            task_tick(scheduler,now)
            now++
        }
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        let value=task_take(scheduler,id)
        if(value is none) {break}
        print("{value as some}\n")
        count++
    }
    verify(count==2)
    print("Async sequence and_bind demo OK\n")
}
