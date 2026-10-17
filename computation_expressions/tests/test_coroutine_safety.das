options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das
require daslib/rtti
require daslib/strings_boost

var opened=0
var closed=0
var ran=0
struct Resource {values:array<int>}
def acquire() {
    var result:Resource
    result.values <- [1,2,3]
    opened++
    return <- result
}
def ce_dispose(var value:Resource) {closed++; delete value}
def job() {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire() |> use_resource
        ran++
        yield next_frame()
        ran++
    }
}
def reject_foreign(var scheduler:CoroutineScheduler; id:CoroutineTaskId) {
    verify(!coroutine_valid(scheduler,id))
    var caught=false
    try {let result=coroutine_cancel(scheduler,id)} recover {caught=true}
    assert(caught)
    caught=false
    try {let result=coroutine_forget(scheduler,id)} recover {caught=true}
    assert(caught)
    caught=false
    try {let result=coroutine_status(scheduler,id)} recover {caught=true}
    assert(caught)
    caught=false
    try {let result=coroutine_error(scheduler,id)} recover {caught=true}
    assert(caught)
}
def identities() {
    let baseline=heap_bytes_allocated()
    var old=CoroutineTaskId()
    {
        var inscope left:CoroutineScheduler
        var inscope right:CoroutineScheduler
        let a=coroutine_spawn(left,job())
        let b=coroutine_spawn(right,job())
        assert(a.slot==b.slot && a.generation==b.generation && a.owner!=b.owner)
        reject_foreign(left,b)
        reject_foreign(right,a)
        verify(coroutine_tick(left)==1 && coroutine_tick(right)==1)
        var inscope moved <- left
        verify(coroutine_valid(moved,a))
        verify(!coroutine_valid(left,a))
        verify(coroutine_tick(moved)==0)
        verify(coroutine_status(right,b)==CoroutineStatus.Running)
        old=b
    }
    {
        var inscope replacement:CoroutineScheduler
        let next=coroutine_spawn(replacement,job())
        assert(next.owner!=old.owner)
        reject_foreign(replacement,old)
    }
    assert(opened==closed)
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def host_scope() {
    let baseline=heap_bytes_allocated()
    var escaped=CoroutineTaskId()
    coroutine_scope($(var scheduler:CoroutineScheduler) {
        escaped=coroutine_spawn(scheduler,job())
        verify(coroutine_tick(scheduler)==1)
    })
    assert(opened==closed)
    var caught=false
    try {
        coroutine_scope($(var scheduler:CoroutineScheduler) {
            let a=coroutine_spawn(scheduler,job())
            let b=coroutine_spawn(scheduler,job())
            verify(coroutine_tick(scheduler)==2)
            panic("host game loop failed")
        })
    } recover {
        caught=true
        assert(starts_with(this_context().last_exception,"host game loop failed"))
    }
    assert(caught && opened==closed)
    coroutine_scope($(var scheduler:CoroutineScheduler) {
        let id=coroutine_spawn(scheduler,job())
        reject_foreign(scheduler,escaped)
        coroutine_close(scheduler)
    })
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
var reentryScheduler:CoroutineScheduler
var badId:CoroutineTaskId
var operation=0
def started_job() {
    var inscope task <- job()
    verify(coroutine_resume(task))
    return <- task
}
def reentrant_job() {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire() |> use_resource
        if (operation==0) {let n=coroutine_tick(reentryScheduler)}
        elif (operation==1) {let n=coroutine_spawn(reentryScheduler,started_job())}
        elif (operation==2) {let n=coroutine_cancel(reentryScheduler,badId)}
        elif (operation==3) {coroutine_close(reentryScheduler)}
        elif (operation==4) {let n=coroutine_forget(reentryScheduler,badId)}
        else {let n=coroutine_prune(reentryScheduler)}
        panic("guard failed")
        yield next_frame()
    }
}
def mutation_guards() {
    let baseline=heap_bytes_allocated()
    for (index in range(6)) {
        operation=index
        reentryScheduler <- CoroutineScheduler()
        badId=coroutine_spawn(reentryScheduler,reentrant_job())
        let survivor=coroutine_spawn(reentryScheduler,job())
        verify(coroutine_tick(reentryScheduler)==1)
        verify(coroutine_status(reentryScheduler,badId)==CoroutineStatus.Failed)
        let error=coroutine_error(reentryScheduler,badId)
        assert(starts_with(error,"coroutine scheduler: mutation"))
        verify(coroutine_task_count(reentryScheduler)==2)
        verify(coroutine_status(reentryScheduler,survivor)==CoroutineStatus.Running)
        verify(coroutine_tick(reentryScheduler)==0)
        delete reentryScheduler
        assert(opened==closed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
[export]
def main() {
    identities()
    host_scope()
    mutation_guards()
    print("coroutine scheduler safety checks OK\n")
}
