options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
struct Resource {items:array<int>}
def acquire() {var r:Resource;r.items <- [1,2,3];opened++;return <- r}
def ce_dispose(var r:Resource) {closed++;delete r}
def job() {
    return <- computation(TaskBuilder(type<int>)) {
        var r & = acquire() |> use_resource
        task_after_polls(1,CeUnit()) |> bind
        return length(r.items)
    }
}
def checks() {
    {
        var inscope scheduler <- task_scheduler(type<int>)
        for(i in range(16)) {
            let first=task_spawn(scheduler,job())
            let second=task_spawn(scheduler,job())
            verify(task_tick(scheduler,i*2)==2)
            verify(task_cancel(scheduler,first))
            verify(task_tick(scheduler,i*2+1)==0 && task_value(scheduler,second)==3)
            verify(task_prune(scheduler)==2 && task_slot_count(scheduler)==2)
        }
        let active=task_spawn(scheduler,job())
        verify(task_tick(scheduler,33)==1)
        // The owner destructor cancels a suspended CE and releases its resources.
    }
    verify(opened==closed)
    {
        var scheduler <- task_scheduler(type<int>)
        var caught=false
        try {
            task_scheduler_scope(scheduler,$(var owner) {
                let a=task_spawn(owner,job());let b=task_spawn(owner,job())
                verify(task_tick(owner,0)==2)
                panic("host failed")
            })
        } recover {caught=starts_with(this_context().last_exception,"host failed")}
        verify(caught && opened==closed)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==closed)
    print("Task scheduler lifetime checks OK\n")
}
