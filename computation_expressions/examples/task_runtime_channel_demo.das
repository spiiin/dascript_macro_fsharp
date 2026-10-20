options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_channel.das

var channel:typedecl(task_channel(type<int>,2))

// Channel capacity 2 applies backpressure; each item has one consumer.
def produce() {
    return <- computation(TaskResultBuilder(type<CeUnit>)) {
        for(n in range(1,6)) {task_channel_send(channel,n) |> bind}
        task_channel_close(channel)
        return CeUnit()
    }
}
def consume() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var sum=0
        while(true) {
            let item=task_channel_receive(channel) |> bind
            if(item is none) {break}
            sum+=item as some
            task_delay_ms(2) |> bind
        }
        return sum
    }
}
[export]
def main() {
    var inscope runtime <- task_runtime(TaskSchedulerConfig(max_polls_per_tick=8))
    channel <- task_channel(type<int>,2)
    var inscope producer <- task_spawn(runtime,produce())
    var inscope consumer <- task_spawn(runtime,consume(),TaskTimeout(after_ms=100))
    var inscope title <- task_spawn(runtime,task_after_polls(1,"assets ready"))
    // In a game call task_tick(runtime,now_ms) once per frame.
    for(now_ms in range(100)) {if(task_tick(runtime,now_ms)==0) {break}}
    verify(task_value(consumer) as ok==15 && task_value(title)=="assets ready")
    verify(task_value(producer) is ok && task_channel_waiters(channel)==0)
    delete channel
    print("Task runtime channel demo OK: sum=15, title={task_value(title)}\n")
}
