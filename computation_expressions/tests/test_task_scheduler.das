options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
var trace=""
def child(name:string) {
    return <- computation(TaskBuilder(type<int>)) {
        trace+=name
        task_after_polls(1,CeUnit()) |> bind
        trace+=name
        return 7
    }
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=1))
    let a=task_spawn(scheduler,child("a"))
    let b=task_spawn(scheduler,child("b"))
    let c=task_spawn(scheduler,child("c"))
    verify(trace=="" && task_count(scheduler)==3)
    verify(task_tick(scheduler,0)==3 && trace=="a")
    verify(task_tick(scheduler,1)==3 && trace=="ab")
    verify(task_tick(scheduler,2)==3 && trace=="abc")
    verify(task_tick(scheduler,3)==2 && trace=="abca")
    verify(task_tick(scheduler,4)==1 && trace=="abcab")
    verify(task_tick(scheduler,5)==0 && trace=="abcabc")
    verify(task_status(scheduler,a)==TaskStatus.Succeeded && task_value(scheduler,a)==7)
    verify(task_status(scheduler,b)==TaskStatus.Succeeded && task_status(scheduler,c)==TaskStatus.Succeeded)
    verify(task_count(scheduler)==3 && task_active_count(scheduler)==0)
    verify(task_prune(scheduler)==3 && !task_valid(scheduler,a))
    // Budget two rotates the start position; a larger budget cannot poll twice.
    trace=""
    task_configure(scheduler,TaskSchedulerConfig(max_polls_per_tick=2))
    let d=task_spawn(scheduler,child("d"))
    let e=task_spawn(scheduler,child("e"))
    let f=task_spawn(scheduler,child("f"))
    verify(task_tick(scheduler,6)==3 && trace=="de")
    verify(task_tick(scheduler,6)==2 && trace=="defd")
    task_configure(scheduler,TaskSchedulerConfig(max_polls_per_tick=64))
    verify(task_tick(scheduler,7)==0 && trace=="defdef")
    verify(task_value(scheduler,d)==7 && task_value(scheduler,e)==7 && task_value(scheduler,f)==7)
    let waiting=task_spawn(scheduler,task_after_polls(3,9))
    verify(task_tick(scheduler,8)==1 && task_status(scheduler,waiting)==TaskStatus.Waiting)
    var caught=false
    try {let n=task_tick(scheduler,7)} recover {caught=true}
    verify(caught && task_scheduler_time(scheduler)==int64(8))
    caught=false
    try {let n=task_tick(scheduler,-1)} recover {caught=true}
    verify(caught && task_scheduler_time(scheduler)==int64(8))
    caught=false
    try {task_configure(scheduler,TaskSchedulerConfig(max_polls_per_tick=0))} recover {caught=true}
    verify(caught && task_scheduler_config(scheduler).max_polls_per_tick==64)
    caught=false
    try {var inscope invalid <- task_scheduler(type<int>,TaskSchedulerConfig(max_polls_per_tick=-1))} recover {caught=true}
    verify(caught)
    verify(task_cancel(scheduler,waiting))
    // Already terminal tasks enter history without joining the active queue.
    var inscope ready <- task_after_polls(0,42)
    verify(task_poll(ready)==TaskStatus.Succeeded)
    let readyId=task_spawn(scheduler,ready)
    verify(task_active_count(scheduler)==0 && task_value(scheduler,readyId)==42)
    // Cancelling the next queued item must advance the cursor correctly.
    trace=""
    task_configure(scheduler,TaskSchedulerConfig(max_polls_per_tick=1))
    let x=task_spawn(scheduler,child("x"))
    let y=task_spawn(scheduler,child("y"))
    let z=task_spawn(scheduler,child("z"))
    verify(task_tick(scheduler,9)==3 && trace=="x")
    verify(task_cancel(scheduler,y))
    verify(task_tick(scheduler,10)==2 && trace=="xz")
    verify(task_tick(scheduler,11)==1 && trace=="xzx")
    verify(task_tick(scheduler,12)==0 && trace=="xzxz")
    var inscope outcomes <- task_scheduler(type<$Result<int;string>>)
    var domainTask <- computation(TaskResultBuilder(type<int>)) {
        let n=task_after_polls(0,result_error("denied",type<int>)) |> bind
        panic("must not run")
        return n
    }
    let domainError=task_spawn(outcomes,domainTask)
    verify(task_tick(outcomes,0)==0 && task_status(outcomes,domainError)==TaskStatus.Succeeded)
    let result=task_value(outcomes,domainError)
    verify(result is err && result as err=="denied")
    print("Task scheduler checks OK\n")
}
