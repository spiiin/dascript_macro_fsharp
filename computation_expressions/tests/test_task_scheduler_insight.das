options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require daslib/rtti
require strings

def sleeper(ms:int) {
    return <- computation(TaskBuilder(type<int>)) {
        task_delay_ms(ms) |> bind
        return ms
    }
}
def blocked() {return <- task_from_poll(@(){return task_pending(type<int>)},@(){})}
def busy(usec:int) {
    return <- task_from_poll(@(){
        let t0=ref_time_ticks()
        while(get_time_usec(t0)<usec) {}
        return task_pending(type<int>)
    },@(){})
}

def deadline_checks() {
    var inscope runtime <- task_runtime()
    verify(task_next_deadline(runtime)==-1l)
    var inscope a <- task_spawn(runtime,sleeper(30))
    // Before the first tick the scheduler asks for an immediate tick.
    verify(task_next_deadline(runtime)==0l)
    task_tick(runtime,100)
    verify(task_next_deadline(runtime)==130l)
    var inscope b <- task_spawn_named(runtime,"timed",blocked(),TaskTimeout(after_ms=20))
    // The timeout counts from scheduler time at spawn (100): deadline 120.
    task_tick(runtime,105)
    verify(task_next_deadline(runtime)==120l) // timeout earlier than the delay
    task_tick(runtime,120)
    verify(task_status(b)==TaskStatus.Cancelled && task_next_deadline(runtime)==130l)
    task_tick(runtime,130)
    verify(task_value(a)==30 && task_next_deadline(runtime)==-1l)
    // A task waiting on something unknown has no deadline.
    var inscope c <- task_spawn(runtime,blocked())
    task_tick(runtime,131)
    verify(task_next_deadline(runtime)==-1l)
    task_cancel(runtime,c)
    // A poll budget smaller than the active set asks for an immediate tick.
    task_configure(runtime,TaskSchedulerConfig(max_polls_per_tick=1))
    var inscope d <- task_spawn(runtime,sleeper(50))
    var inscope e <- task_spawn(runtime,sleeper(50))
    task_tick(runtime,140)
    verify(task_next_deadline(runtime)==140l)
    task_tick(runtime,141)
    verify(task_next_deadline(runtime)==190l || task_next_deadline(runtime)==141l)
}

def budget_checks() {
    // Time budget: three busy tasks of ~3 ms with a 1 ms budget poll one per tick.
    var inscope runtime <- task_runtime(TaskSchedulerConfig(max_polls_per_tick=8,max_tick_usec=1000))
    var inscope a <- task_spawn_named(runtime,"a",busy(3000))
    var inscope b <- task_spawn_named(runtime,"b",busy(3000))
    var inscope c <- task_spawn_named(runtime,"c",busy(3000))
    task_tick(runtime,0)
    var inscope infos <- task_dump(runtime)
    var polled=0
    for(info in infos) {polled+=info.polls}
    verify(polled==1 && task_next_deadline(runtime)==0l)
    var failed=false
    try {task_configure(runtime,TaskSchedulerConfig(max_tick_usec=-1))} recover {failed=true}
    verify(failed)
}

def dump_checks() {
    var inscope runtime <- task_runtime()
    var inscope loader <- task_spawn_named(runtime,"load level",blocked(),TaskTimeout(after_ms=500))
    var inscope quick <- task_spawn(runtime,task_after_polls(0,1))
    task_tick(runtime,1000)
    verify(task_name(runtime,loader)=="load level" && task_name(runtime,quick)=="")
    var inscope infos <- task_dump(runtime)
    verify(length(infos)==2)
    for(info in infos) {
        if(info.name=="load level") {
            verify(info.active && info.status==TaskStatus.Waiting && info.spawned_ms==1000l)
            verify(info.polls==1 && info.last_poll_ms==1000l && info.deadline_ms==1500l)
        } else {
            verify(!info.active && info.status==TaskStatus.Succeeded && info.deadline_ms==-1l)
        }
    }
    task_tick(runtime,1100)
    var inscope stalled <- task_stalled(runtime,100)
    verify(length(stalled)==1 && stalled[0].name=="load level")
    var inscope fresh <- task_stalled(runtime,101)
    verify(empty(fresh))
    let text=task_dump_text(runtime)
    verify(find(text,"load level: Waiting")>=0 && find(text,"<unnamed>")>=0 && find(text,"timeout at 1500")>=0)
    task_tick(runtime,1500)
    var inscope after <- task_dump(runtime)
    for(info in after) {if(info.name=="load level") {verify(info.timed_out && info.status==TaskStatus.Cancelled)}}
    // Typed scheduler: names and set_name.
    var inscope scheduler <- task_scheduler(type<int>)
    let id=task_spawn_named(scheduler,"first",task_after_polls(1,5))
    task_set_name(scheduler,id,"renamed")
    verify(task_name(scheduler,id)=="renamed")
}

[export]
def main() {
    deadline_checks();budget_checks();dump_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {deadline_checks();dump_checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task scheduler insight checks OK\n")
}
