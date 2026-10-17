options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost

var trace=""
var opened=0
var closed=0
struct Owned {data:array<int>}
def acquire() {
    var value:Owned
    value.data <- [10,20,30]
    opened++
    return <- value
}
def ce_dispose(var value:Owned) {closed++; delete value}
def script(name:string; fail:bool) {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire() |> use_resource
        trace+="{name}1;"
        yield next_frame()
        trace+="{name}2;"
        if (fail) {panic("task {name} failed")}
        yield next_frame()
        trace+="{name}3;"
    }
}
def lifecycle() {
    trace=""
    let baseline=heap_bytes_allocated()
    {
        var inscope scheduler:CoroutineScheduler
        var inscope source <- script("a",true)
        let a=coroutine_spawn(scheduler,source)
        let b=coroutine_spawn(scheduler,script("b",false))
        let c=coroutine_spawn(scheduler,script("c",false))
        assert(a.slot==1 && b.slot==2 && c.slot==3 && trace=="")
        verify(!coroutine_resume(source))
        verify(coroutine_status(scheduler,a)==CoroutineStatus.Running)
        verify(coroutine_tick(scheduler)==3)
        assert(trace=="a1;b1;c1;")
        verify(coroutine_cancel(scheduler,b))
        verify(!coroutine_cancel(scheduler,b))
        verify(coroutine_tick(scheduler)==1)
        assert(trace=="a1;b1;c1;a2;c2;")
        verify(coroutine_status(scheduler,a)==CoroutineStatus.Failed)
        let failure=coroutine_error(scheduler,a)
        assert(starts_with(failure,"task a failed"))
        verify(coroutine_status(scheduler,b)==CoroutineStatus.Cancelled)
        verify(coroutine_tick(scheduler)==0)
        verify(coroutine_status(scheduler,c)==CoroutineStatus.Completed)
        let noError=coroutine_error(scheduler,c)
        assert(noError=="" && trace=="a1;b1;c1;a2;c2;c3;")
        verify(coroutine_tick(scheduler)==0)
        verify(!coroutine_cancel(scheduler,c))
        // Terminal records are retained until forget/prune.
        let d=coroutine_spawn(scheduler,script("d",false))
        assert(d.slot==4)
        verify(coroutine_cancel(scheduler,d))
        assert(opened==closed)
        coroutine_close(scheduler)
        coroutine_close(scheduler)
        verify(coroutine_tick(scheduler)==0)
        verify(coroutine_status(scheduler,a)==CoroutineStatus.Failed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def cleanup() {
    let baseline=heap_bytes_allocated()
    let before=opened
    {
        var inscope unused:CoroutineScheduler
        let id=coroutine_spawn(unused,script("unused",false))
    }
    assert(opened==before)
    {
        var inscope scheduler:CoroutineScheduler
        let a=coroutine_spawn(scheduler,script("close",false))
        let b=coroutine_spawn(scheduler,script("close2",false))
        verify(coroutine_tick(scheduler)==2)
        coroutine_close(scheduler)
        verify(coroutine_status(scheduler,a)==CoroutineStatus.Cancelled)
        verify(coroutine_status(scheduler,b)==CoroutineStatus.Cancelled)
        assert(opened==closed)
        var inscope rejected <- script("rejected",false)
        verify(coroutine_resume(rejected))
        var caught=false
        try {let id=coroutine_spawn(scheduler,rejected)} recover {caught=true}
        assert(caught && opened==closed)
        verify(!coroutine_resume(rejected))
    }
    {
        var inscope original:CoroutineScheduler
        let id=coroutine_spawn(original,script("moved",false))
        verify(coroutine_tick(original)==1)
        var inscope moved <- original
        delete original
        verify(coroutine_status(moved,id)==CoroutineStatus.Running)
        // The moved scheduler's scope exit must close the running task.
    }
    assert(opened==closed)
    for (i in range(2)) {
        var inscope broken:CoroutineScheduler
        let id=coroutine_spawn(broken,script("break",false))
        verify(coroutine_tick(broken)==1)
        break
    }
    assert(opened==closed)
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
var globalScheduler:CoroutineScheduler
def reentrant() {
    let baseline=heap_bytes_allocated()
    {
        var inscope recursive <- computation(CoroutineBuilder()) {
            var resource & = acquire() |> use_resource
            let impossible=coroutine_tick(globalScheduler)
            yield next_frame()
        }
        let bad=coroutine_spawn(globalScheduler,recursive)
        let good=coroutine_spawn(globalScheduler,script("survivor",false))
        verify(coroutine_tick(globalScheduler)==1)
        verify(coroutine_status(globalScheduler,bad)==CoroutineStatus.Failed)
        let error=coroutine_error(globalScheduler,bad)
        assert(starts_with(error,"coroutine scheduler: mutation"))
        verify(coroutine_status(globalScheduler,good)==CoroutineStatus.Running)
        coroutine_close(globalScheduler)
    }
    delete globalScheduler
    assert(opened==closed)
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def deferred_tasks() {
    let baseline=heap_bytes_allocated()
    trace=""
    {
        var inscope scheduler:CoroutineScheduler
        var inscope saved <- deferred(CoroutineBuilder(),fixed_array(7,8)) $(snapshot) {
            var resource & = acquire() |> use_resource
            let item=snapshot |> bind
            trace+="{item};"
            yield next_frame()
        }
        let a=coroutine_spawn(scheduler,run_deferred(saved))
        let b=coroutine_spawn(scheduler,run_deferred(saved))
        delete saved
        verify(coroutine_tick(scheduler)==2)
        assert(trace=="7;7;")
        verify(coroutine_cancel(scheduler,a))
        verify(coroutine_tick(scheduler)==1)
        verify(coroutine_tick(scheduler)==0)
        assert(trace=="7;7;8;" && opened==closed)
        verify(coroutine_status(scheduler,b)==CoroutineStatus.Completed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def invalid_ids() {
    var inscope scheduler:CoroutineScheduler
    for (slot in fixed_array(-1,0,1)) {
        let id=CoroutineTaskId(slot=slot,generation=uint64(1))
        var caught=false
        try {let status=coroutine_status(scheduler,id)} recover {caught=true}
        assert(caught)
        caught=false
        try {let changed=coroutine_cancel(scheduler,id)} recover {caught=true}
        assert(caught)
    }
    verify(coroutine_tick(scheduler)==0)
}
[export]
def main() {
    for (round in range(3)) {lifecycle(); cleanup(); deferred_tasks(); invalid_ids()}
    reentrant()
    print("coroutine scheduler checks OK\n")
}


