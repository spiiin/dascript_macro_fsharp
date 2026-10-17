options gen2
module task_delay public
require ./task_builder.das public
require daslib/rtti

struct TaskClockSample {owner:uint64;now_ms:int64}
// Value snapshots exist only across synchronous poll calls, never borrowed
// scheduler pointers. Nested schedulers restore the enclosing clock on return.
var private task_clock_samples:array<TaskClockSample>

def ce_task_clock_scope(owner:uint64; now_ms:int64; action:block<():void>) {
    let depth=length(task_clock_samples)
    task_clock_samples |> push(TaskClockSample(owner=owner,now_ms=now_ms))
    try {invoke(action)} recover {
        let message="{this_context().last_exception}"
        task_clock_samples.resize(depth)
        panic(message)
    }
    task_clock_samples.resize(depth)
}
def private task_delay_clock_owner() : uint64 {
    if(empty(task_clock_samples)) {panic("task_delay_ms: polling requires task_tick scheduler clock")}
    return task_clock_samples[length(task_clock_samples)-1].owner
}
def private task_delay_clock_now() : int64 {
    if(empty(task_clock_samples)) {panic("task_delay_ms: polling requires task_tick scheduler clock")}
    return task_clock_samples[length(task_clock_samples)-1].now_ms
}

// Cold Task<Unit>: the interval starts on its first poll, when the bind is
// reached, rather than at construction or registration of the containing Task.
def task_delay_ms(duration_ms:int64) {
    if(duration_ms<int64(0)) {panic("task_delay_ms: duration must be non-negative")}
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:CeUnit>> {
        let owner=task_delay_clock_owner()
        let deadline=uint64(task_delay_clock_now())+uint64(duration_ms)
        while(true) {
            if(task_delay_clock_owner()!=owner) {panic("task_delay_ms: scheduler changed while waiting")}
            if(uint64(task_delay_clock_now())>=deadline) {yield task_ready(CeUnit());return false}
            yield task_pending(type<CeUnit>)
        }
        return false
    }
    return <- task_create(events)
}
def task_delay_ms(duration_ms:int) {return <- task_delay_ms(int64(duration_ms))}
