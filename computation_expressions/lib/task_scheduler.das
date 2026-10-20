options gen2
module task_scheduler public
require ./task_builder.das public
require ./task_delay.das public
require ./task_combinators.das public
require daslib/rtti
require strings

// max_tick_usec: optional wall-clock budget per tick (0 = unlimited). At least one
// task is polled; the check runs between top-level polls and cannot preempt one.
struct TaskSchedulerConfig {max_polls_per_tick:int=64;max_tick_usec:int=0}
// Snapshot for diagnostics. Times are scheduler now_ms; -1 means unknown/none.
struct TaskInfo {
    id:TaskId
    name:string
    status:TaskStatus
    active:bool
    timed_out:bool
    spawned_ms:int64
    last_poll_ms:int64
    polls:int
    deadline_ms:int64
}
struct TaskTimeout {after_ms:int64}
struct TaskId {owner:uint64;slot:int;generation:uint64}
struct TaskSchedulerTag {_ce_marker:uint8}
// Private implementation records. Active queue links are 1-based; zero is null.
struct TaskSlot {
    generation:uint64
    occupied:bool
    active:bool
    previous:int
    next:int
    next_free:int
    timed_out:bool
    timer_queued:bool
    deadline_ms:uint64
    timer_previous:int
    timer_next:int
    name:string
    spawned_ms:int64
    last_poll_ms:int64=-1l
    polls:int
}
struct TaskSchedulerState {
    config:TaskSchedulerConfig=TaskSchedulerConfig()
    owner:uint64
    busy:bool
    closed:bool
    head:int
    tail:int
    cursor:int
    free_head:int
    count:int
    active_count:int
    now_ms:int64
    has_time:bool
    timer_head:int
    timer_tail:int
    // Earliest delay deadline seen in the last tick, or uint64(-1).
    wake_ms:uint64=uint64(-1)
    // The last tick stopped with active tasks left unpolled (poll/time budget).
    starved:bool
}
var private task_scheduler_last_owner:uint64=0

def private task_scheduler_new_owner() : uint64 {
    if(task_scheduler_last_owner==uint64(-1)) {panic("task scheduler: owner identities exhausted")}
    task_scheduler_last_owner++
    return task_scheduler_last_owner
}
def private task_scheduler_validate(config:TaskSchedulerConfig) {
    if(config.max_polls_per_tick<=0) {panic("task scheduler: max_polls_per_tick must be positive")}
    if(config.max_tick_usec<0) {panic("task scheduler: max_tick_usec must be non-negative")}
}
def private task_scheduler_dispose(var frame:auto) {
    frame.state.busy=true
    frame.state.closed=true
    for(record in frame.records) {
        if(record.slot.occupied && record.slot.active) {task_cancel(record.task)}
    }
}
def private task_scheduler_create(unused:type<auto(T)>; config:TaskSchedulerConfig; owner:uint64) {
    var placeholder:iterator<tuple<tag:TaskEventTag;ready:bool;value:T -const -&>>
    var records:array<tuple<task:typedecl(task_create(placeholder));slot:TaskSlot>>
    // One owning frame avoids exposing a raw pointer and survives owner moves.
    var inscope frames:array<tuple<state:TaskSchedulerState;records:typedecl(records)>>
    frames |> emplace((state=TaskSchedulerState(config=config,owner=owner),records <- records))
    return <- (kind=TaskSchedulerTag(),frames <- frames)
}
def task_scheduler(unused:type<auto(T)>; config:TaskSchedulerConfig) {
    static_assert(typeinfo ce_resumable_payload(default<T>))
    task_scheduler_validate(config)
    let owner=task_scheduler_new_owner()
    return <- task_scheduler_create(type<T>,config,owner)
}
def task_scheduler(unused:type<auto(T)>) {return <- task_scheduler(type<T>,TaskSchedulerConfig())}

def finalize(var scheduler:tuple<kind:TaskSchedulerTag;frames:array<auto(F)>>) {
    ce_sequence_finalize($ {
        if(!empty(scheduler.frames)) {task_scheduler_dispose(scheduler.frames[0])}
        delete scheduler.frames
    })
}
def private task_scheduler_live(scheduler:auto) {
    if(length(scheduler.frames)!=1) {panic("task scheduler: owner was moved or deleted")}
}
def private task_scheduler_idle(scheduler:auto) {
    task_scheduler_live(scheduler)
    if(scheduler.frames[0].state.busy) {panic("task scheduler: mutation during tick or cleanup is unsupported")}
}
def private task_scheduler_active(status:TaskStatus) : bool {return status==TaskStatus.Created || status==TaskStatus.Waiting}

def task_valid(scheduler:auto; id:TaskId) : bool {
    if(length(scheduler.frames)!=1) {return false}
    if(id.owner==uint64(0) || id.owner!=scheduler.frames[0].state.owner) {return false}
    if(id.slot<=0 || id.slot>length(scheduler.frames[0].records)) {return false}
    let slot=scheduler.frames[0].records[id.slot-1].slot
    return slot.occupied && slot.generation==id.generation
}
def private task_scheduler_check_id(scheduler:auto; id:TaskId) {
    task_scheduler_live(scheduler)
    if(!task_valid(scheduler,id)) {panic("task scheduler: invalid or stale task id")}
}
// A separate ordered timer queue skips ordinary tasks and terminal history.
// Before the first clock sample deadlines are durations; shifting all of them
// by the first now_ms preserves order. Unsigned sums avoid signed overflow.
def private task_scheduler_remove_timer(var frame:auto; index:int) {
    unsafe {
        var timer & = frame.records[index-1].slot
        if(!timer.timer_queued) {return}
        if(timer.timer_previous!=0) {frame.records[timer.timer_previous-1].slot.timer_next=timer.timer_next}
        else {frame.state.timer_head=timer.timer_next}
        if(timer.timer_next!=0) {frame.records[timer.timer_next-1].slot.timer_previous=timer.timer_previous}
        else {frame.state.timer_tail=timer.timer_previous}
        timer.timer_queued=false
        timer.timer_previous=0;timer.timer_next=0
    }
}
def private task_scheduler_add_timer(var frame:auto; index:int; after_ms:int64) {
    unsafe {
        var timer & = frame.records[index-1].slot
        timer.deadline_ms=uint64(after_ms)+(frame.state.has_time ? uint64(frame.state.now_ms) : uint64(0))
        var previous=frame.state.timer_tail
        while(previous!=0 && frame.records[previous-1].slot.deadline_ms>timer.deadline_ms) {
            previous=frame.records[previous-1].slot.timer_previous
        }
        let next=previous!=0 ? frame.records[previous-1].slot.timer_next : frame.state.timer_head
        timer.timer_previous=previous;timer.timer_next=next;timer.timer_queued=true
        if(previous!=0) {frame.records[previous-1].slot.timer_next=index}
        else {frame.state.timer_head=index}
        if(next!=0) {frame.records[next-1].slot.timer_previous=index}
        else {frame.state.timer_tail=index}
    }
}

def private task_scheduler_unlink(var frame:auto; slot:int) {
    unsafe {
        var record & = frame.records[slot-1].slot
        if(!record.active) {return}
        task_scheduler_remove_timer(frame,slot)
        if(record.previous!=0) {frame.records[record.previous-1].slot.next=record.next}
        else {frame.state.head=record.next}
        if(record.next!=0) {frame.records[record.next-1].slot.previous=record.previous}
        else {frame.state.tail=record.previous}
        if(frame.state.cursor==slot) {frame.state.cursor=record.next!=0 ? record.next : frame.state.head}
        record.active=false
        record.previous=0;record.next=0
        frame.state.active_count--
    }
}
def private task_scheduler_spawn(var scheduler:auto; var source:auto; timed:bool; after_ms:int64; name:string) : TaskId {
    unsafe {
        if(ce_task_is_polling(source)) {panic("task scheduler: cannot move a task being polled")}
        var inscope owned <- ce_task_source(source)
        var index=0
        try {
            task_scheduler_idle(scheduler)
            if(timed && after_ms<int64(0)) {panic("task scheduler: timeout must be non-negative")}
            var frame & = scheduler.frames[0]
            if(frame.state.closed) {panic("task scheduler: scheduler is closed")}
            if(frame.state.free_head!=0) {
                index=frame.state.free_head
                frame.state.free_head=frame.records[index-1].slot.next_free
                frame.records[index-1].task <- owned
                frame.records[index-1].slot=TaskSlot(generation=frame.records[index-1].slot.generation+uint64(1),occupied=true)
            } else {
                frame.records |> emplace((task <- owned,slot=TaskSlot(generation=uint64(1),occupied=true)))
                index=length(frame.records)
            }
            frame.records[index-1].slot.name=name
            frame.records[index-1].slot.spawned_ms=frame.state.has_time ? frame.state.now_ms : int64(-1)
            if(task_scheduler_active(task_status(frame.records[index-1].task))) {
                frame.records[index-1].slot.active=true
                frame.records[index-1].slot.previous=frame.state.tail
                if(frame.state.tail!=0) {frame.records[frame.state.tail-1].slot.next=index}
                else {frame.state.head=index}
                frame.state.tail=index
                frame.state.active_count++
                if(frame.state.cursor==0) {frame.state.cursor=index}
                if(timed) {task_scheduler_add_timer(frame,index,after_ms)}
            }
            frame.state.count++
        } recover {
            let message="{this_context().last_exception}"
            task_cancel(owned)
            delete owned
            panic(message)
        }
        return TaskId(owner=scheduler.frames[0].state.owner,slot=index,generation=scheduler.frames[0].records[index-1].slot.generation)
    }
}

def task_spawn(var scheduler:auto; var source:auto) : TaskId {
    return task_scheduler_spawn(scheduler,source,false,int64(0),"")
}
def task_spawn(var scheduler:auto; var source:auto; timeout:TaskTimeout) : TaskId {
    return task_scheduler_spawn(scheduler,source,true,timeout.after_ms,"")
}
// Named variants only add a diagnostic label; names need not be unique.
def task_spawn_named(var scheduler:auto; name:string; var source:auto) : TaskId {
    return task_scheduler_spawn(scheduler,source,false,int64(0),name)
}
def task_spawn_named(var scheduler:auto; name:string; var source:auto; timeout:TaskTimeout) : TaskId {
    return task_scheduler_spawn(scheduler,source,true,timeout.after_ms,name)
}
def task_name(scheduler:auto; id:TaskId) : string {
    task_scheduler_check_id(scheduler,id)
    return scheduler.frames[0].records[id.slot-1].slot.name
}
def task_set_name(var scheduler:auto; id:TaskId; name:string) {
    task_scheduler_check_id(scheduler,id)
    scheduler.frames[0].records[id.slot-1].slot.name=name
}
def task_timed_out(scheduler:auto; id:TaskId) : bool {
    task_scheduler_check_id(scheduler,id)
    return scheduler.frames[0].records[id.slot-1].slot.timed_out
}
def task_status(scheduler:auto; id:TaskId) : TaskStatus {
    task_scheduler_check_id(scheduler,id)
    return task_status(scheduler.frames[0].records[id.slot-1].task)
}
def task_value(scheduler:auto; id:TaskId) {
    task_scheduler_check_id(scheduler,id)
    static_if(typeinfo can_copy(type<typedecl(task_value(scheduler.frames[0].records[id.slot-1].task))>)) {
        return task_value(scheduler.frames[0].records[id.slot-1].task)
    } else {return <- task_value(scheduler.frames[0].records[id.slot-1].task)}
}

// Transfer an owned result without cloning, and retire its completed record.
def task_take(var scheduler:auto;id:TaskId) {
    task_scheduler_idle(scheduler);task_scheduler_check_id(scheduler,id)
    if(task_status(scheduler,id)!=TaskStatus.Succeeded) {panic("task_take: task has not succeeded")}
    var value <- scheduler.frames[0].records[id.slot-1].task.value
    task_scheduler_release(scheduler.frames[0],id.slot)
    return <- value
}
def task_error(scheduler:auto; id:TaskId) : string {
    task_scheduler_check_id(scheduler,id)
    return task_error(scheduler.frames[0].records[id.slot-1].task)
}
def task_cancel(var scheduler:auto; id:TaskId) : bool {
    task_scheduler_idle(scheduler)
    task_scheduler_check_id(scheduler,id)
    if(!scheduler.frames[0].records[id.slot-1].slot.active) {return false}
    scheduler.frames[0].state.busy=true
    let cancelled=task_cancel(scheduler.frames[0].records[id.slot-1].task)
    task_scheduler_unlink(scheduler.frames[0],id.slot)
    scheduler.frames[0].state.busy=false
    return cancelled
}
def task_configure(var scheduler:auto; config:TaskSchedulerConfig) {
    task_scheduler_idle(scheduler)
    task_scheduler_validate(config)
    if(scheduler.frames[0].state.closed) {panic("task scheduler: scheduler is closed")}
    scheduler.frames[0].state.config=config
}
def task_scheduler_config(scheduler:auto) {task_scheduler_live(scheduler);return scheduler.frames[0].state.config}
def task_scheduler_time(scheduler:auto) : int64 {task_scheduler_live(scheduler);return scheduler.frames[0].state.now_ms}
def task_count(scheduler:auto) : int {task_scheduler_live(scheduler);return scheduler.frames[0].state.count}
def task_active_count(scheduler:auto) : int {task_scheduler_live(scheduler);return scheduler.frames[0].state.active_count}
def task_slot_count(scheduler:auto) : int {task_scheduler_live(scheduler);return length(scheduler.frames[0].records)}

def task_tick(var scheduler:auto; now_ms:int64) : int {
    unsafe {
        task_scheduler_idle(scheduler)
        var frame & = scheduler.frames[0]
        if(frame.state.closed) {return 0}
        if(now_ms<int64(0) || (frame.state.has_time && now_ms<frame.state.now_ms)) {panic("task scheduler: time must be non-negative and monotonic")}
        frame.state.busy=true
        try {
            let started=ref_time_ticks()
            var starved=false
            let wake=ce_task_clock_scope(frame.state.owner,now_ms,$ {
                if(!frame.state.has_time) {
                    var timer=frame.state.timer_head
                    while(timer!=0) {
                        frame.records[timer-1].slot.deadline_ms+=uint64(now_ms)
                        timer=frame.records[timer-1].slot.timer_next
                    }
                    for(record in frame.records) {
                        if(record.slot.occupied && record.slot.spawned_ms<int64(0)) {record.slot.spawned_ms=now_ms}
                    }
                }
                frame.state.now_ms=now_ms;frame.state.has_time=true
                // All due timers close before any polling, independent of poll budget.
                while(frame.state.timer_head!=0 && frame.records[frame.state.timer_head-1].slot.deadline_ms<=uint64(now_ms)) {
                    let index=frame.state.timer_head
                    frame.records[index-1].slot.timed_out=true
                    task_cancel(frame.records[index-1].task)
                    task_scheduler_unlink(frame,index)
                }
                let active_at_start=frame.state.active_count
                let limit=frame.state.config.max_polls_per_tick<active_at_start ? frame.state.config.max_polls_per_tick : active_at_start
                var budget=limit
                let time_budget=frame.state.config.max_tick_usec
                while(budget>0 && frame.state.active_count>0) {
                    if(time_budget>0 && budget<limit && get_time_usec(started)>=time_budget) {break}
                    let index=frame.state.cursor
                    frame.state.cursor=frame.records[index-1].slot.next!=0 ? frame.records[index-1].slot.next : frame.state.head
                    frame.records[index-1].slot.polls++
                    frame.records[index-1].slot.last_poll_ms=now_ms
                    let status=task_poll(frame.records[index-1].task)
                    if(!task_scheduler_active(status)) {task_scheduler_unlink(frame,index)}
                    budget--
                }
                // Poll budget smaller than the active set or an exhausted time budget
                // leaves tasks that were not polled in this tick.
                starved=frame.state.active_count>0 && limit-budget<active_at_start
            })
            frame.state.wake_ms=wake
            frame.state.starved=starved
        } recover {frame.state.busy=false;panic("{this_context().last_exception}")}
        frame.state.busy=false
        return frame.state.active_count
    }
}
def task_scheduler_close(var scheduler:auto) {
    unsafe {
        task_scheduler_idle(scheduler)
        var frame & = scheduler.frames[0]
        if(frame.state.closed) {return}
        frame.state.closed=true;frame.state.busy=true
        var index=frame.state.head
        while(index!=0) {
            let next=frame.records[index-1].slot.next
            task_cancel(frame.records[index-1].task)
            task_scheduler_unlink(frame,index)
            index=next
        }
        frame.state.busy=false
    }
}
def private task_scheduler_release(var frame:auto; index:int) {
    delete frame.records[index-1].task
    frame.records[index-1].slot.occupied=false
    if(frame.records[index-1].slot.generation!=uint64(-1)) {
        frame.records[index-1].slot.next_free=frame.state.free_head
        frame.state.free_head=index
    }
    frame.state.count--
}
def task_forget(var scheduler:auto; id:TaskId) : bool {
    task_scheduler_idle(scheduler);task_scheduler_check_id(scheduler,id)
    if(scheduler.frames[0].records[id.slot-1].slot.active) {return false}
    scheduler.frames[0].state.busy=true
    task_scheduler_release(scheduler.frames[0],id.slot)
    scheduler.frames[0].state.busy=false
    return true
}
def task_prune(var scheduler:auto) : int {
    task_scheduler_idle(scheduler)
    scheduler.frames[0].state.busy=true
    var removed=0
    for(index in range(length(scheduler.frames[0].records))) {
        if(scheduler.frames[0].records[index].slot.occupied && !scheduler.frames[0].records[index].slot.active) {
            task_scheduler_release(scheduler.frames[0],index+1);removed++
        }
    }
    scheduler.frames[0].state.busy=false
    return removed
}
def task_scheduler_scope(var scheduler:auto(S); body:block<(var owner:S):void>) {
    var owned <- scheduler
    try {invoke(body,owned)} recover {
        let message="{this_context().last_exception}"
        delete owned
        panic(message)
    }
    delete owned
}

def task_tick(var scheduler:auto; now_ms:int) : int {return task_tick(scheduler,int64(now_ms))}

// Earliest scheduler time at which a tick can make progress on time-based waits:
// timeouts and task_delay_ms waits polled in the last tick. Returns now_ms when the
// last tick left active tasks unpolled or before the first tick, and -1 when no
// active task has a known deadline. Tasks waiting on events, channels, sockets or
// jobque results are not visible here: keep ticking while such waits can complete.
def task_next_deadline(scheduler:auto) : int64 {
    task_scheduler_live(scheduler)
    let state=scheduler.frames[0].state
    if(state.active_count==0) {return int64(-1)}
    if(!state.has_time || state.starved) {return state.now_ms}
    var best=state.wake_ms
    if(state.timer_head!=0) {
        let timer=scheduler.frames[0].records[state.timer_head-1].slot.deadline_ms
        if(timer<best) {best=timer}
    }
    if(best==uint64(-1)) {return int64(-1)}
    return best<uint64(state.now_ms) ? state.now_ms : int64(best)
}
def private task_scheduler_info(scheduler:auto; index:int) : TaskInfo {
    let slot=scheduler.frames[0].records[index-1].slot
    return TaskInfo(
        id=TaskId(owner=scheduler.frames[0].state.owner,slot=index,generation=slot.generation),
        name=slot.name,
        status=task_status(scheduler.frames[0].records[index-1].task),
        active=slot.active,
        timed_out=slot.timed_out,
        spawned_ms=slot.spawned_ms,
        last_poll_ms=slot.last_poll_ms,
        polls=slot.polls,
        deadline_ms=slot.timer_queued && scheduler.frames[0].state.has_time ? int64(slot.deadline_ms) : int64(-1))
}
// One entry per occupied slot (active and retained terminal records), slot order.
def task_dump(scheduler:auto) : array<TaskInfo> {
    task_scheduler_live(scheduler)
    var result:array<TaskInfo>
    for(index in range(length(scheduler.frames[0].records))) {
        if(scheduler.frames[0].records[index].slot.occupied) {result |> push(task_scheduler_info(scheduler,index+1))}
    }
    return <- result
}
// Active tasks spawned at least older_than_ms ago (scheduler time).
def task_stalled(scheduler:auto; older_than_ms:int64) : array<TaskInfo> {
    task_scheduler_live(scheduler)
    var result:array<TaskInfo>
    let now=scheduler.frames[0].state.now_ms
    if(!scheduler.frames[0].state.has_time) {return <- result}
    for(index in range(length(scheduler.frames[0].records))) {
        let slot=scheduler.frames[0].records[index].slot
        if(slot.occupied && slot.active && slot.spawned_ms>=int64(0) && now-slot.spawned_ms>=older_than_ms) {
            result |> push(task_scheduler_info(scheduler,index+1))
        }
    }
    return <- result
}
def task_stalled(scheduler:auto; older_than_ms:int) : array<TaskInfo> {return <- task_stalled(scheduler,int64(older_than_ms))}
def task_dump_text(scheduler:auto) : string {
    var inscope infos <- task_dump(scheduler)
    let now=task_scheduler_time(scheduler)
    return build_string() $(var writer) {
        writer |> write("tasks: {length(infos)}, active: {task_active_count(scheduler)}, now_ms: {now}\n")
        for(info in infos) {
            let title=empty(info.name) ? "<unnamed>" : info.name
            writer |> write("  #{info.id.slot} {title}: {info.status}")
            if(info.timed_out) {writer |> write(" (timed out)")}
            if(info.active && info.spawned_ms>=int64(0)) {writer |> write(", age {now-info.spawned_ms} ms")}
            writer |> write(", polls {info.polls}")
            if(info.deadline_ms>=int64(0)) {writer |> write(", timeout at {info.deadline_ms}")}
            writer |> write("\n")
        }
    }
}
