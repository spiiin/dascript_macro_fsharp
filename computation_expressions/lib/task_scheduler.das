options gen2
module task_scheduler public
require ./task_builder.das public
require ./task_delay.das public
require ./task_combinators.das public
require daslib/rtti

struct TaskSchedulerConfig {max_polls_per_tick:int=64}
struct TaskTimeout {after_ms:int64}
struct TaskId {owner:uint64;slot:int;generation:uint64}
struct TaskSchedulerTag {}
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
}
var private task_scheduler_last_owner:uint64=0

def private task_scheduler_new_owner() : uint64 {
    if(task_scheduler_last_owner==uint64(-1)) {panic("task scheduler: owner identities exhausted")}
    task_scheduler_last_owner++
    return task_scheduler_last_owner
}
def private task_scheduler_validate(config:TaskSchedulerConfig) {
    if(config.max_polls_per_tick<=0) {panic("task scheduler: max_polls_per_tick must be positive")}
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
    concept_assert(typeinfo can_copy(type<T>),"task scheduler: payload must be copyable")
    task_scheduler_validate(config)
    let owner=task_scheduler_new_owner()
    return <- task_scheduler_create(type<T>,config,owner)
}
def task_scheduler(unused:type<auto(T)>) {return <- task_scheduler(type<T>,TaskSchedulerConfig())}

// Collection results have an owning array Task, not a copyable Task<Array<T>>.
def task_scheduler(unused:type<array<auto(Item)>>; config:TaskSchedulerConfig) {
    concept_assert(typeinfo can_copy(type<Item>),"task scheduler: array elements must be copyable")
    static_assert(typeinfo ce_resumable_payload(default<Item>))
    task_scheduler_validate(config)
    let owner=task_scheduler_new_owner()
    var placeholder:iterator<tuple<tag:TaskEventTag;ready:bool;value:Item>>
    var children:array<typedecl(task_create(placeholder))>
    var records:array<tuple<task:typedecl(task_when_all(children));slot:TaskSlot>>
    var inscope frames:array<tuple<state:TaskSchedulerState;records:typedecl(records)>>
    frames |> emplace((state=TaskSchedulerState(config=config,owner=owner),records <- records))
    return <- (kind=TaskSchedulerTag(),frames <- frames)
}

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
def private task_scheduler_spawn(var scheduler:auto; var source:auto; timed:bool; after_ms:int64) : TaskId {
    unsafe {
        if(ce_task_is_polling(source)) {panic("task scheduler: cannot move a task being polled")}
        var inscope owned <- source
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
    return task_scheduler_spawn(scheduler,source,false,int64(0))
}
def task_spawn(var scheduler:auto; var source:auto; timeout:TaskTimeout) : TaskId {
    return task_scheduler_spawn(scheduler,source,true,timeout.after_ms)
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
            ce_task_clock_scope(frame.state.owner,now_ms,$ {
                if(!frame.state.has_time) {
                    var timer=frame.state.timer_head
                    while(timer!=0) {
                        frame.records[timer-1].slot.deadline_ms+=uint64(now_ms)
                        timer=frame.records[timer-1].slot.timer_next
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
                var budget=frame.state.config.max_polls_per_tick<frame.state.active_count ? frame.state.config.max_polls_per_tick : frame.state.active_count
                while(budget>0 && frame.state.active_count>0) {
                    let index=frame.state.cursor
                    frame.state.cursor=frame.records[index-1].slot.next!=0 ? frame.records[index-1].slot.next : frame.state.head
                    let status=task_poll(frame.records[index-1].task)
                    if(!task_scheduler_active(status)) {task_scheduler_unlink(frame,index)}
                    budget--
                }
            })
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
