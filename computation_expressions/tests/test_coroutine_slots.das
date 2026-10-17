options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das
require daslib/rtti
var trace=""
var opened=0
var closed=0
struct Resource {values:array<int>}
def acquire() {
    var value:Resource
    value.values <- [1,2,3]
    opened++
    return <- value
}
def ce_dispose(var value:Resource) {closed++; delete value}
def job(name:string; frames:int; fail:bool=false) {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire() |> use_resource
        trace+="{name};"
        yield wait_frames(frames)
        if (fail) {panic("failure {name}")}
        trace+="{name} done;"
    }
}
def reject_stale(var scheduler:CoroutineScheduler; old:CoroutineTaskId) {
    verify(!coroutine_valid(scheduler,old))
    var caught=false
    try {let status=coroutine_status(scheduler,old)} recover {caught=true}
    assert(caught)
    caught=false
    try {let error=coroutine_error(scheduler,old)} recover {caught=true}
    assert(caught)
    caught=false
    try {let changed=coroutine_cancel(scheduler,old)} recover {caught=true}
    assert(caught)
    caught=false
    try {let removed=coroutine_forget(scheduler,old)} recover {caught=true}
    assert(caught)
}
def reuse_and_order() {
    trace=""
    var inscope scheduler:CoroutineScheduler
    let a=coroutine_spawn(scheduler,job("a",0))
    let b=coroutine_spawn(scheduler,job("b",2))
    let c=coroutine_spawn(scheduler,job("c",0,true))
    verify(!coroutine_forget(scheduler,b))
    verify(coroutine_tick(scheduler)==1)
    assert(trace=="a;a done;b;c;")
    verify(coroutine_prune(scheduler)==2)
    verify(coroutine_task_count(scheduler)==1)
    reject_stale(scheduler,a)
    reject_stale(scheduler,c)
    let d=coroutine_spawn(scheduler,job("d",1))
    let e=coroutine_spawn(scheduler,job("e",1))
    assert(e.slot==a.slot && e.generation!=a.generation)
    assert(d.slot==c.slot && d.generation!=c.generation)
    let cleanError=coroutine_error(scheduler,d)
    assert(cleanError=="")
    reject_stale(scheduler,a)
    verify(coroutine_status(scheduler,e)==CoroutineStatus.Running)
    verify(coroutine_tick(scheduler)==3)
    assert(trace=="a;a done;b;c;d;e;")
    verify(coroutine_tick(scheduler)==0)
    assert(trace=="a;a done;b;c;d;e;b done;d done;e done;")
    verify(coroutine_forget(scheduler,d)) // unlink middle
    verify(coroutine_forget(scheduler,b)) // unlink head
    verify(coroutine_forget(scheduler,e)) // unlink last
    verify(coroutine_task_count(scheduler)==0 && coroutine_slot_count(scheduler)==3)
    verify(coroutine_prune(scheduler)==0)
    verify(coroutine_tick(scheduler)==0)
    let last=coroutine_spawn(scheduler,job("last",1))
    verify(coroutine_tick(scheduler)==1)
    coroutine_close(scheduler)
    verify(coroutine_status(scheduler,last)==CoroutineStatus.Cancelled)
    verify(coroutine_prune(scheduler)==1)
    reject_stale(scheduler,last)
    assert(opened==closed)
}
def short_job() {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire() |> use_resource
        yield next_frame()
    }
}
def bounded_storage() {
    let baseline=heap_bytes_allocated()
    {
        var inscope scheduler:CoroutineScheduler
        var previous=CoroutineTaskId()
        var warmed:uint64=0
        for (round in range(128)) {
            let first=coroutine_spawn(scheduler,short_job())
            for (i in range(3)) {let id=coroutine_spawn(scheduler,short_job())}
            if (round>0) {reject_stale(scheduler,previous)}
            verify(coroutine_tick(scheduler)==4)
            verify(coroutine_tick(scheduler)==0)
            verify(coroutine_prune(scheduler)==4)
            verify(coroutine_slot_count(scheduler)==4 && coroutine_task_count(scheduler)==0)
            assert(opened==closed)
            let current=heap_bytes_allocated()
            if (round==0) {warmed=uint64(current)}
            else {assert(uint64(current)==warmed)}
            previous=first
        }
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
// Exercise the overflow boundary directly without 2^64 registrations.
def generation_boundary() {
    var inscope scheduler:CoroutineScheduler
    let id=coroutine_spawn(scheduler,short_job())
    verify(coroutine_cancel(scheduler,id))
    scheduler.tasks[id.slot-1].generation=uint64(-1)
    let exhausted=CoroutineTaskId(owner=id.owner,slot=id.slot,generation=uint64(-1))
    verify(coroutine_forget(scheduler,exhausted))
    let next=coroutine_spawn(scheduler,short_job())
    assert(next.slot!=id.slot)
    reject_stale(scheduler,exhausted)
    verify(coroutine_cancel(scheduler,next))
}
[export]
def main() {
    reuse_and_order()
    bounded_storage()
    generation_boundary()
    print("coroutine slot checks OK\n")
}
