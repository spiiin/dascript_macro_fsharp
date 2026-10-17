options gen2
module coroutine_scheduler public
require ./coroutine_builder.das public
require daslib/rtti

enum CoroutineStatus {
    Running
    Completed
    Cancelled
    Failed
}

// A handle is valid only in its owning scheduler and slot generation.
struct CoroutineTaskId {owner:uint64; slot:int; generation:uint64}

// Context-local, single-threaded identity allocator. Never wrap and revive IDs.
var private coroutine_last_owner:uint64=0
def private coroutine_new_owner() : uint64 {
    if (coroutine_last_owner==uint64(-1)) {panic("coroutine scheduler: owner identities exhausted")}
    coroutine_last_owner++
    return coroutine_last_owner
}

struct CoroutineTaskRecord {
    source:iterator<CoroutineFrame>
    status:CoroutineStatus
    error:string
    generation:uint64
    occupied:bool
    previous:int
    next:int
    next_free:int
}

def private coroutine_stop_record(var record:CoroutineTaskRecord) {
    if (!record.occupied || record.status!=CoroutineStatus.Running) {return}
    record.status=CoroutineStatus.Cancelled
    try {coroutine_cancel(record.source)} recover {
        record.error="{this_context().last_exception}"
        record.status=CoroutineStatus.Failed
    }
}
def private coroutine_dispose_records(var records:array<CoroutineTaskRecord>; head:int) {
    ce_sequence_finalize($ {
        var slot=head
        while (slot!=0) {
            coroutine_stop_record(records[slot-1])
            slot=records[slot-1].next
        }
        delete records
    })
}

struct CoroutineScheduler {
    tasks:array<CoroutineTaskRecord>
    owner:uint64
    busy:bool
    closed:bool
    free_head:int
    head:int
    tail:int
    count:int
    def finalize {
        busy=true
        closed=true
        coroutine_dispose_records(tasks,head)
    }
}

def private coroutine_check_idle(scheduler:CoroutineScheduler) {
    if (scheduler.busy) {panic("coroutine scheduler: mutation during tick or cleanup is unsupported")}
}
def coroutine_valid(scheduler:CoroutineScheduler; id:CoroutineTaskId) : bool {
    if (id.owner==uint64(0) || id.owner!=scheduler.owner) {return false}
    if (id.slot<=0 || id.slot>length(scheduler.tasks)) {return false}
    return scheduler.tasks[id.slot-1].occupied && scheduler.tasks[id.slot-1].generation==id.generation
}
def private coroutine_check_id(scheduler:CoroutineScheduler; id:CoroutineTaskId) {
    if (!coroutine_valid(scheduler,id)) {panic("coroutine scheduler: invalid or stale task id")}
}

// Consumes source even if registration is rejected. IDs are local to a scheduler.
def coroutine_spawn(var scheduler:CoroutineScheduler; var source:iterator<CoroutineFrame>) : CoroutineTaskId {
    var inscope record <- CoroutineTaskRecord(source <- source,status=CoroutineStatus.Running,error="",
        generation=uint64(1),occupied=true)
    var slot=0
    try {
        coroutine_check_idle(scheduler)
        if (scheduler.closed) {panic("coroutine scheduler: scheduler is closed")}
        if (scheduler.owner==uint64(0)) {scheduler.owner=coroutine_new_owner()}
        if (scheduler.free_head!=0) {
            slot=scheduler.free_head
            scheduler.free_head=scheduler.tasks[slot-1].next_free
            record.generation=scheduler.tasks[slot-1].generation+uint64(1)
            scheduler.tasks[slot-1] <- record
        } else {
            scheduler.tasks |> emplace(record)
            slot=length(scheduler.tasks)
        }
        scheduler.tasks[slot-1].previous=scheduler.tail
        if (scheduler.tail!=0) {scheduler.tasks[scheduler.tail-1].next=slot}
        else {scheduler.head=slot}
        scheduler.tail=slot
        scheduler.count++
    } recover {
        let message="{this_context().last_exception}"
        coroutine_cancel(record.source)
        panic(message)
    }
    return CoroutineTaskId(owner=scheduler.owner,slot=slot,generation=scheduler.tasks[slot-1].generation)
}
def coroutine_status(scheduler:CoroutineScheduler; id:CoroutineTaskId) : CoroutineStatus {
    coroutine_check_id(scheduler,id)
    return scheduler.tasks[id.slot-1].status
}
def coroutine_error(scheduler:CoroutineScheduler; id:CoroutineTaskId) : string {
    coroutine_check_id(scheduler,id)
    return scheduler.tasks[id.slot-1].error
}
def coroutine_cancel(var scheduler:CoroutineScheduler; id:CoroutineTaskId) : bool {
    coroutine_check_idle(scheduler)
    coroutine_check_id(scheduler,id)
    if (scheduler.tasks[id.slot-1].status!=CoroutineStatus.Running) {return false}
    scheduler.busy=true
    coroutine_stop_record(scheduler.tasks[id.slot-1])
    scheduler.busy=false
    return true
}

// One resume per running task, in registration order. Failures are isolated.
def coroutine_tick(var scheduler:CoroutineScheduler) : int {
    coroutine_check_idle(scheduler)
    if (scheduler.closed) {return 0}
    scheduler.busy=true
    var active=0
    var slot=scheduler.head
    while (slot!=0) {
        // busy forbids mutations that could reallocate tasks during resume.
        unsafe {
            var record & = scheduler.tasks[slot-1]
            if (record.status==CoroutineStatus.Running) {
                try {
                    if (coroutine_resume(record.source)) {active++}
                    else {record.status=CoroutineStatus.Completed}
                } recover {
                    record.error="{this_context().last_exception}"
                    record.status=CoroutineStatus.Failed
                }
            }
            slot=record.next
        }
    }
    scheduler.busy=false
    return active
}

// Keep terminal records queryable until deletion; refuse new registrations.
def coroutine_close(var scheduler:CoroutineScheduler) {
    coroutine_check_idle(scheduler)
    if (scheduler.closed) {return}
    scheduler.closed=true
    scheduler.busy=true
    var slot=scheduler.head
    while (slot!=0) {
        coroutine_stop_record(scheduler.tasks[slot-1])
        slot=scheduler.tasks[slot-1].next
    }
    scheduler.busy=false
}

// Remove a terminal record from the registration-order list. Never cancel here.
def private coroutine_release_slot(var scheduler:CoroutineScheduler; slot:int) {
    // Only unlink fields; no allocations or callbacks can invalidate this reference.
    unsafe {
        var record & = scheduler.tasks[slot-1]
        if (record.previous!=0) {scheduler.tasks[record.previous-1].next=record.next}
        else {scheduler.head=record.next}
        if (record.next!=0) {scheduler.tasks[record.next-1].previous=record.previous}
        else {scheduler.tail=record.previous}
        record.occupied=false
        record.error=""
        record.previous=0
        record.next=0
        // Retire the slot rather than wrapping its generation and reviving old IDs.
        if (record.generation!=uint64(-1)) {
            record.next_free=scheduler.free_head
            scheduler.free_head=slot
        }
        scheduler.count--
    }
}
def coroutine_forget(var scheduler:CoroutineScheduler; id:CoroutineTaskId) : bool {
    coroutine_check_idle(scheduler)
    coroutine_check_id(scheduler,id)
    if (scheduler.tasks[id.slot-1].status==CoroutineStatus.Running) {return false}
    coroutine_release_slot(scheduler,id.slot)
    return true
}
def coroutine_prune(var scheduler:CoroutineScheduler) : int {
    coroutine_check_idle(scheduler)
    var removed=0
    var slot=scheduler.head
    while (slot!=0) {
        let next=scheduler.tasks[slot-1].next
        if (scheduler.tasks[slot-1].status!=CoroutineStatus.Running) {
            coroutine_release_slot(scheduler,slot)
            removed++
        }
        slot=next
    }
    return removed
}
def coroutine_task_count(scheduler:CoroutineScheduler) : int {return scheduler.count}
def coroutine_slot_count(scheduler:CoroutineScheduler) : int {return length(scheduler.tasks)}

// Protect the owner from native exceptions in the host game loop too.
def coroutine_scope(body:block<(var scheduler:CoroutineScheduler):void>) {
    var scheduler:CoroutineScheduler
    try {invoke(body,scheduler)} recover {
        let message="{this_context().last_exception}"
        delete scheduler
        panic(message)
    }
    delete scheduler
}


