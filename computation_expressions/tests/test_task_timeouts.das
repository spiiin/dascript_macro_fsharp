options gen2
require ../lib/task_scheduler.das
require daslib/strings_boost
require daslib/rtti
var events=""
var polled=0
var closed=0
def pending(name:string; fail_close:bool=false) {
    return <- task_from_poll(@(){polled++;events+=name;return task_pending(type<int>)},@(){
        closed++;events+="!"+name
        if(fail_close) {panic("timeout cleanup failed")}
    })
}
def boundaries() {
    var inscope scheduler <- task_scheduler(type<int>)
    let before=polled
    let id=task_spawn(scheduler,pending("a"),TaskTimeout(after_ms=10))
    verify(!task_timed_out(scheduler,id))
    verify(task_tick(scheduler,100)==1 && polled==before+1)
    verify(task_tick(scheduler,109)==1 && polled==before+2)
    verify(task_tick(scheduler,110)==0 && polled==before+2)
    verify(task_status(scheduler,id)==TaskStatus.Cancelled && task_timed_out(scheduler,id))
    verify(!task_cancel(scheduler,id) && empty(task_error(scheduler,id)))
    verify(task_tick(scheduler,110)==0 && polled==before+2)
    // New tasks use the latest accepted clock sample, not their first poll.
    let late=task_spawn(scheduler,pending("b"),TaskTimeout(after_ms=5))
    verify(task_tick(scheduler,115)==0 && polled==before+2 && task_timed_out(scheduler,late))
    // Zero expires before even an immediately ready Task can run.
    let zero=task_spawn(scheduler,task_after_polls(0,8),TaskTimeout(after_ms=0))
    verify(task_tick(scheduler,115)==0 && task_timed_out(scheduler,zero))
    var caught=false
    try {let value=task_value(scheduler,zero)} recover {caught=true}
    verify(caught)
    let noTimeout=task_spawn(scheduler,pending("c"))
    verify(task_tick(scheduler,100000)==1 && !task_timed_out(scheduler,noTimeout))
    verify(task_cancel(scheduler,noTimeout) && !task_timed_out(scheduler,noTimeout))
}
def ordering() {
    var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=1))
    verify(task_tick(scheduler,100)==0)
    events=""
    let a=task_spawn(scheduler,pending("a"),TaskTimeout(after_ms=30))
    let b=task_spawn(scheduler,pending("b"),TaskTimeout(after_ms=10))
    let c=task_spawn(scheduler,pending("c"),TaskTimeout(after_ms=20))
    let d=task_spawn(scheduler,pending("d"),TaskTimeout(after_ms=10))
    let survivor=task_spawn(scheduler,pending("s"))
    verify(task_tick(scheduler,100)==5 && events=="a")
    // Cancel four due tasks, ordered by deadline then registration, and still
    // give the surviving task its full polling budget. Cursor b is removed.
    verify(task_tick(scheduler,130)==1 && events=="a!b!d!c!as")
    verify(task_timed_out(scheduler,a) && task_timed_out(scheduler,b))
    verify(task_timed_out(scheduler,c) && task_timed_out(scheduler,d))
    verify(task_prune(scheduler)==4 && task_count(scheduler)==1)
    verify(task_cancel(scheduler,survivor))
}
def timer_removal() {
    var inscope scheduler <- task_scheduler(type<int>)
    let a=task_spawn(scheduler,pending("a"),TaskTimeout(after_ms=10))
    let b=task_spawn(scheduler,task_after_polls(0,7),TaskTimeout(after_ms=20))
    let c=task_spawn(scheduler,pending("c"),TaskTimeout(after_ms=30))
    let d=task_spawn(scheduler,pending("d"),TaskTimeout(after_ms=40))
    verify(task_tick(scheduler,100)==3 && task_value(scheduler,b)==7)
    verify(task_cancel(scheduler,a) && task_cancel(scheduler,c) && task_cancel(scheduler,d))
    verify(!task_timed_out(scheduler,a) && !task_timed_out(scheduler,b))
    verify(task_prune(scheduler)==4)
    let replacement=task_spawn(scheduler,pending("r"))
    var inscope moved <- scheduler
    verify(task_tick(moved,1000)==1 && !task_timed_out(moved,replacement))
    verify(!task_valid(moved,a) && !task_valid(scheduler,replacement))
    // A completed source is history even with a zero timeout.
    var ready <- task_after_polls(0,42)
    verify(task_poll(ready)==TaskStatus.Succeeded)
    let done=task_spawn(moved,ready,TaskTimeout(after_ms=0))
    verify(task_tick(moved,1001)==1 && task_value(moved,done)==42 && !task_timed_out(moved,done))
    let future=task_spawn(moved,pending("f"),TaskTimeout(after_ms=5))
    var caught=false
    try {let n=task_tick(moved,1000)} recover {caught=true}
    verify(caught && !task_timed_out(moved,future) && task_scheduler_time(moved)==int64(1001))
    verify(task_tick(moved,1006)==1 && task_timed_out(moved,future))
    task_scheduler_close(moved)
    verify(!task_timed_out(moved,replacement))
}
def limits_and_failures() {
    var inscope scheduler <- task_scheduler(type<int>)
    let before=closed
    var caught=false
    try {let id=task_spawn(scheduler,pending("bad"),TaskTimeout(after_ms=-1))} recover {
        caught=starts_with(this_context().last_exception,"task scheduler: timeout must be non-negative")
    }
    verify(caught && closed==before+1 && task_count(scheduler)==0)
    // A cleanup error preserves the timeout cause while reporting Failed.
    let bad=task_spawn(scheduler,pending("bad",true),TaskTimeout(after_ms=0))
    let next=task_spawn(scheduler,pending("next"),TaskTimeout(after_ms=0))
    verify(task_tick(scheduler,50)==0)
    verify(task_status(scheduler,bad)==TaskStatus.Failed && task_timed_out(scheduler,bad))
    verify(starts_with(task_error(scheduler,bad),"timeout cleanup failed"))
    verify(task_status(scheduler,next)==TaskStatus.Cancelled && task_timed_out(scheduler,next))
    // A deadline beyond the representable signed clock must not wrap to past.
    let maxTime=9223372036854775807l
    let huge=task_spawn(scheduler,pending("huge"),TaskTimeout(after_ms=maxTime))
    verify(task_tick(scheduler,maxTime)==1 && !task_timed_out(scheduler,huge))
    var inscope fresh <- task_scheduler(type<int>)
    let first=task_spawn(fresh,pending("first"),TaskTimeout(after_ms=maxTime))
    verify(task_tick(fresh,maxTime)==1 && !task_timed_out(fresh,first))
    // A positive timer still arms after a zero timer is removed before first tick.
    var inscope start <- task_scheduler(type<int>)
    let zero=task_spawn(start,pending("zero"),TaskTimeout(after_ms=0))
    let positive=task_spawn(start,pending("positive"),TaskTimeout(after_ms=1))
    verify(task_cancel(start,zero))
    verify(task_tick(start,900)==1 && !task_timed_out(start,positive))
    verify(task_tick(start,901)==0 && task_timed_out(start,positive))
}
[export]
def main() {
    boundaries();ordering();timer_removal();limits_and_failures()
    print("Task timeout checks OK\n")
}
