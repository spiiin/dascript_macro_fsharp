options gen2
module task_combinators public
require ./task_builder.das public
require daslib/rtti

struct TaskAllPolicy {}
struct TaskResultAllPolicy {}

def private task_pair_value(policy:TaskAllPolicy; left:auto; right:auto) {
    return ce_source_pair(left,right)
}
def private task_pair_value(policy:TaskResultAllPolicy;
    left:variant<ok:auto(T);error:string>; right:variant<ok:auto(U);error:string>) {
    return result_ok(ce_source_pair(left as ok,right as ok))
}
def private task_pair_stops(policy:TaskAllPolicy; value:auto) {return false}
def private task_pair_stops(policy:TaskResultAllPolicy; value:variant<ok:auto(T);error:string>) {return value is error}
def private task_pair_error(policy:TaskAllPolicy; value:auto; unused:type<auto(T)>) {return default<T>}
def private task_pair_error(policy:TaskResultAllPolicy; value:variant<ok:auto(T);error:string>; unused:type<auto(R)>) {
    return variant type<R>(error=value as error)
}

// Both arguments are consuming owners. Aliases must be rejected before moving.
def private task_check_distinct(var left:auto; var right:auto) {
    unsafe {
        if(reinterpret<void?>(addr(left))==reinterpret<void?>(addr(right))) {
            panic("task composition: the same owner cannot be passed twice")
        }
    }
}
def private task_check_child(status:TaskStatus; error:string) {
    if(status==TaskStatus.Failed) {panic(error)}
    if(status==TaskStatus.Cancelled) {panic("task composition: child was cancelled")}
}
def private task_release_child(var task:auto) : string {
    let cancelled=task_cancel(task)
    var error=""
    if(cancelled && task_status(task)==TaskStatus.Failed) {error=task_error(task)}
    delete task
    return error
}
def private task_release_pair(var left:auto; var right:auto) {
    let first=task_release_child(left)
    let second=task_release_child(right)
    if(!empty(first)) {ce_task_cleanup_error(first)}
    if(!empty(second)) {ce_task_cleanup_error(second)}
}

def private task_pair_pending(policy:auto; left:auto; right:auto) {
    return task_pending(type<typedecl(task_pair_value(policy,left,right)) -const -&>)
}
def private task_pair(var left:auto(L); var right:auto(R); policy:auto(P)) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:typedecl(task_pair_value(policy,left.value,right.value)) -const -&>> capture(<-left,<-right) {
        while(true) {
            let first=task_poll(left)
            task_check_child(first,task_error(left))
            if(first==TaskStatus.Succeeded && task_pair_stops(policy,left.value)) {
                yield task_ready(task_pair_error(policy,left.value,type<typedecl(task_pair_value(policy,left.value,right.value)) -const -&>))
                return false
            }
            let second=task_poll(right)
            task_check_child(second,task_error(right))
            if(second==TaskStatus.Succeeded && task_pair_stops(policy,right.value)) {
                yield task_ready(task_pair_error(policy,right.value,type<typedecl(task_pair_value(policy,left.value,right.value)) -const -&>))
                return false
            }
            if(first==TaskStatus.Succeeded && second==TaskStatus.Succeeded) {
                yield task_ready(task_pair_value(policy,left.value,right.value))
                return false
            }
            yield task_pair_pending(policy,left.value,right.value)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_pair(left,right)})}
    return <- task_create(events)
}

// At most one poll per active child per parent poll, in left-to-right order.
def task_when_all(var left:auto(L); var right:auto(R)) {
    task_check_distinct(left,right)
    return <- task_pair(left,right,TaskAllPolicy())
}
def task_result_when_all(var left:auto(L); var right:auto(R)) {
    task_check_distinct(left,right)
    return <- task_pair(left,right,TaskResultAllPolicy())
}

// First terminal child wins. A tie is won by the left child without polling right.
// Native faults/cancelled children fail the parent; pending losers are cancelled.
def private task_race_impl(var left,right:auto(T)) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:tuple<index:int;value:typedecl(left.value) -const -&>>> capture(<-left,<-right) {
        while(true) {
            let first=task_poll(left)
            task_check_child(first,task_error(left))
            if(first==TaskStatus.Succeeded) {yield task_ready((index=0,value=task_value(left)));return false}
            let second=task_poll(right)
            task_check_child(second,task_error(right))
            if(second==TaskStatus.Succeeded) {yield task_ready((index=1,value=task_value(right)));return false}
            yield task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_pair(left,right)})}
    return <- task_create(events)
}
def task_race(var left,right:auto(T)) {
    task_check_distinct(left,right)
    return <- task_race_impl(left,right)
}
