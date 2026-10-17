options gen2
module task_combinators public
require ./task_builder.das public
require daslib/rtti

struct TaskAllPolicy {}
struct TaskResultAllPolicy {}
struct TaskArrayTag {}
struct TaskArrayEventTag {}

// Array results are move-only, so a Task<Unit> drives the children while a
// separate owning array caches values. The generator only borrows its stable
// data buffer; the array owner always closes the driver before freeing it.
def private task_release_array(var children:array<auto>) {
    for(child in children) {
        let error=task_release_child(child)
        if(!empty(error)) {ce_task_cleanup_error(error)}
    }
    delete children
}
def task_when_all(var children:array<auto(C)>) {
    typedef ArrayValue=typedecl(children[0].value) -const -&
    concept_assert(typeinfo can_copy(type<ArrayValue>),"task_when_all array: child results must be copyable")
    static_assert(typeinfo ce_resumable_payload(default<ArrayValue>))
    // Reject moving an active callback's owner before consuming the array.
    for(index in range(length(children))) {
        if(ce_task_is_polling(children[index])) {panic("task_when_all array: cannot move a task being polled")}
    }
    var values:array<ArrayValue>
    values.resize(length(children))
    for(index in range(length(children))) {
        if(task_status(children[index])==TaskStatus.Succeeded) {values[index]=task_value(children[index])}
    }
    unsafe {
        var buffer:ArrayValue?
        static_if(typeinfo sizeof(type<ArrayValue>)>0) {
            if(!empty(values)) {buffer=addr(values[0])}
        }
        var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:CeUnit>> capture(<-children,copy(buffer)) {
            while(true) {
                var complete=true
                for(index in range(length(children))) {
                    if(task_status(children[index])==TaskStatus.Succeeded) {continue}
                    let status=task_poll(children[index])
                    if(!task_check_child(status,task_error(children[index]))) {
                        yield task_pending(type<CeUnit>)
                        return false
                    }
                    if(status==TaskStatus.Succeeded) {
                        static_if(typeinfo sizeof(type<ArrayValue>)>0) {unsafe {buffer[index]=task_value(children[index])}}
                    }
                    else {complete=false}
                }
                if(complete) {yield task_ready(CeUnit());return false}
                yield task_pending(type<CeUnit>)
            }
            return false
        } finally {ce_sequence_finalize($ {task_release_array(children)})}
        return <- (tag=TaskArrayTag(),control <- task_create(events),value <- values)
    }
}
def ce_task_is_polling(task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) : bool {return task.control.polling}
def task_poll(var task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {
    let status=task_poll(task.control)
    if(status==TaskStatus.Failed || status==TaskStatus.Cancelled) {delete task.value}
    return status
}
def task_status(task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {return task_status(task.control)}
def task_error(task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {return task_error(task.control)}
def task_cancel(var task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {
    let cancelled=task_cancel(task.control)
    if(task_status(task.control)!=TaskStatus.Succeeded) {delete task.value}
    return cancelled
}
def task_value(task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {
    if(task_status(task)!=TaskStatus.Succeeded) {panic("task_value: task has not succeeded")}
    return <- clone(task.value)
}
def finalize(var task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>) {
    ce_sequence_finalize($ {
        task_cancel(task.control)
        delete task.control
        delete task.value
    })
}
def task_with_cancellation(var task:tuple<tag:TaskArrayTag;control:auto;value:array<auto>>; token:CancellationToken) {
    var control <- task_with_cancellation(task.control,token)
    return <- (tag=TaskArrayTag(),control <- control,value <- task.value)
}
def task_scope(var task:tuple<tag:TaskArrayTag;control:auto(ControlType);value:array<auto(ArrayValueType)>>;
               body:block<(var owned:tuple<tag:TaskArrayTag;control:ControlType;value:array<ArrayValueType>>):void>) {
    var owned <- task
    try {invoke(body,owned)} recover {
        let message="{this_context().last_exception}"
        task_cancel(owned)
        delete owned
        panic(message)
    }
    let cancelled=task_cancel(owned)
    var cleanup=""
    if(cancelled && task_status(owned)==TaskStatus.Failed) {cleanup=task_error(owned)}
    delete owned
    if(!empty(cleanup)) {panic(cleanup)}
}

// The ready event lends the array while this source owns the aggregate Task.
// A CE continuation can suspend again: the source and its owner stay alive.
def ce_await_source(builder:auto; var task:tuple<tag:TaskArrayTag;control:auto;value:array<auto(ArrayItem)>>) {
    return <- generator<tuple<tag:TaskArrayEventTag;ready:bool;value:array<ArrayItem>?>> capture(<-task) {
        while(true) {
            let status=task_poll(task)
            if(status==TaskStatus.Failed) {panic(task_error(task))}
            if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {
                ce_task_cancelled()
                yield (tag=TaskArrayEventTag(),ready=false,value=null)
                return false
            }
            if(status==TaskStatus.Succeeded) {
                unsafe {yield (tag=TaskArrayEventTag(),ready=true,value=addr(task.value))}
                return false
            }
            yield (tag=TaskArrayEventTag(),ready=false,value=null)
        }
        return false
    } finally {ce_sequence_finalize($ {
        let cancelled=task_cancel(task)
        if(cancelled && task_status(task)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(task))}
        delete task
    })}
}

def ce_await_borrow_value(builder:auto; event:tuple<tag:TaskArrayEventTag;ready:bool;value:array<auto(ArrayItem)>?>) : array<ArrayItem>& {
    unsafe {return *event.value}
}
def ce_await_failed(builder:tuple<kind:TaskResultContext;element:auto>; event:tuple<tag:TaskArrayEventTag;ready:bool;value:array<auto>?>) {return false}
def ce_await_failure(builder:tuple<kind:TaskResultContext;element:auto(Root)>; event:tuple<tag:TaskArrayEventTag;ready:bool;value:array<auto>?>) {return task_pending(type<variant<ok:Root;error:string>>)}

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
def private task_check_child(status:TaskStatus; error:string) : bool {
    if(status==TaskStatus.Failed) {panic(error)}
    if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {ce_task_cancelled();return false}
    return true
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
            if(!task_check_child(first,task_error(left))) {yield task_pair_pending(policy,left.value,right.value);return false}
            if(first==TaskStatus.Succeeded && task_pair_stops(policy,left.value)) {
                yield task_ready(task_pair_error(policy,left.value,type<typedecl(task_pair_value(policy,left.value,right.value)) -const -&>))
                return false
            }
            let second=task_poll(right)
            if(!task_check_child(second,task_error(right))) {yield task_pair_pending(policy,left.value,right.value);return false}
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
// Native faults fail the parent; cancelled children cancel it. Losers are closed.
def private task_race_impl(var left,right:auto(T)) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:tuple<index:int;value:typedecl(left.value) -const -&>>> capture(<-left,<-right) {
        while(true) {
            let first=task_poll(left)
            if(!task_check_child(first,task_error(left))) {
                yield task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
                return false
            }
            if(first==TaskStatus.Succeeded) {yield task_ready((index=0,value=task_value(left)));return false}
            let second=task_poll(right)
            if(!task_check_child(second,task_error(right))) {
                yield task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
                return false
            }
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
