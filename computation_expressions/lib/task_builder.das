options gen2
module task_builder public
require ./computation_builders.das public
require ./sequence_runtime.das public
require ./resumable_lowering.das public
require daslib/rtti

enum TaskStatus {
    Created
    Waiting
    Succeeded
    Cancelled
    Failed
}
struct TaskTag {}
struct TaskEventTag {}
struct TaskContext {}
struct TaskResultContext {}

def task_pending(unused:type<auto(T)>) {
    return (tag=TaskEventTag(),ready=false,value=default<T -const -&>)
}
def task_ready(value:auto(T)) {
    concept_assert(typeinfo can_copy(type<T>),"task: payload must be copyable")
    return tuple<tag:TaskEventTag;ready:bool;value:T -const -&>(tag=TaskEventTag(),ready=true,value=value)
}
def task_create(var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>) {
    static_assert(typeinfo ce_resumable_payload(default<T>))
    concept_assert(typeinfo can_copy(type<T>),"task: payload must be copyable")
    return <- (tag=TaskTag(),source <- source,status=TaskStatus.Created,value=default<T>,error="",polling=false)
}
def TaskBuilder(unused:type<auto(T)>) {return (kind=TaskContext(),element=default<T -const -&>)}
def TaskResultBuilder(unused:type<auto(T)>) {return (kind=TaskResultContext(),element=default<T -const -&>)}

def ce_protocol(builder:tuple<kind:TaskContext;element:auto(T)>) {
    return ce_resumable_protocol(type<tuple<tag:TaskEventTag;ready:bool;value:T>>)
}
def ce_protocol(builder:tuple<kind:TaskResultContext;element:auto(T)>) {
    return ce_resumable_protocol(type<tuple<tag:TaskEventTag;ready:bool;value:variant<ok:T;error:string>>>)
}
def ce_await_pending(builder:tuple<kind:TaskContext;element:auto(T)>) {return task_pending(type<T>)}
def ce_await_pending(builder:tuple<kind:TaskResultContext;element:auto(T)>) {return task_pending(type<variant<ok:T;error:string>>)}
def ce_await_return(builder:tuple<kind:TaskContext;element:auto(T)>; value:T) {return task_ready(value)}
def ce_await_return(builder:tuple<kind:TaskResultContext;element:auto(T)>; value:T) {return task_ready(result_ok(value))}
def ce_await_value(builder:tuple<kind:TaskContext;element:auto(T)>; event:tuple<tag:TaskEventTag;ready:bool;value:auto(U)>) {return event.value}
def ce_await_value(builder:tuple<kind:TaskResultContext;element:auto(T)>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {return event.value as ok}
def ce_await_failed(builder:tuple<kind:TaskContext;element:auto(T)>; event:auto) {return false}
def ce_await_failed(builder:tuple<kind:TaskResultContext;element:auto(T)>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {return event.value is error}
def ce_await_failure(builder:tuple<kind:TaskContext;element:auto(T)>; event:auto) {return task_pending(type<T>)}
def ce_await_failure(builder:tuple<kind:TaskResultContext;element:auto(T)>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {return task_ready(result_error(event.value as error,type<T>))}

def ce_sequence_run(builder:tuple<kind:TaskContext;element:auto(T)>; var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:T>>) {return <- task_create(source)}
def ce_sequence_run(builder:tuple<kind:TaskResultContext;element:auto(T)>; var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<ok:T;error:string>>>) {return <- task_create(source)}

def task_status(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) {return task.status}
def task_value(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : T {
    if(task.status!=TaskStatus.Succeeded) {panic("task_value: task has not succeeded")}
    return task.value
}
def task_error(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) {return task.error}

def task_cancel(var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : bool {
    if(task.polling) {panic("task_cancel: task is being polled")}
    if(task.status!=TaskStatus.Created && task.status!=TaskStatus.Waiting) {return false}
    task.status=TaskStatus.Cancelled
    try {sequence_close(task.source)} recover {task.status=TaskStatus.Failed;task.error="{this_context().last_exception}"}
    return true
}

// One poll drives the continuation to its next suspension or final result.
// Terminal results are cached. There is no implicit busy-wait or worker thread.
def task_poll(var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : TaskStatus {
    if(task.polling) {panic("task_poll: reentrant polling is unsupported")}
    if(task.status!=TaskStatus.Created && task.status!=TaskStatus.Waiting) {return task.status}
    task.polling=true
    var event=task_pending(type<T>)
    try {
        if(!ce_sequence_next_value(task.source,event)) {panic("task: computation ended without return")}
        if(event.ready) {
            task.value=event.value
            task.status=TaskStatus.Succeeded
            sequence_close(task.source)
        } else {task.status=TaskStatus.Waiting}
    } recover {
        task.error="{this_context().last_exception}"
        task.status=TaskStatus.Failed
        try {sequence_close(task.source)} recover {}
    }
    task.polling=false
    return task.status
}

// Move an awaited child into the parent; closing the parent cancels the child.
def ce_await_source(builder:auto; var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : iterator<tuple<tag:TaskEventTag;ready:bool;value:T>> {
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:T>> capture(<-task) {
        while(true) {
            let status=task_poll(task)
            if(status==TaskStatus.Succeeded) {yield task_ready(task_value(task));break}
            if(status==TaskStatus.Failed) {panic(task_error(task))}
            if(status==TaskStatus.Cancelled) {panic("task: awaited child was cancelled")}
            yield task_pending(type<T>)
        }
        return false
    } finally {ce_sequence_finalize($ {task_cancel(task);delete task})}
}

// Adapter for a nonblocking operation's poll callback. The lambda owns captures.
// Each poll returns Pending or Ready; close runs on success, cancellation or panic.
def private task_close_callbacks(var poll:lambda<():auto(T)>; var close:lambda<():void>) {
    var message=""
    try {invoke(close)} recover {message="{this_context().last_exception}"}
    unsafe {delete poll;delete close}
    if(!empty(message)) {panic(message)}
}

def task_from_poll(var poll:lambda<():tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>; var close:lambda<():void>) {
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:T>> capture(<-poll,<-close) {
        while(true) {
            let event=invoke(poll)
            yield event
            if(event.ready) {break}
        }
        return false
    } finally {ce_sequence_finalize($ {task_close_callbacks(poll,close)})}
    return <- task_create(source)
}

def task_after_polls(count:int; value:auto(T)) {
    if(count<0) {panic("task_after_polls: count must be non-negative")}
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:T -const -&>> {
        for(i in range(count)) {yield task_pending(type<T>)}
        yield task_ready(value)
        return false
    }
    return <- task_create(source)
}

// Own a task across exceptions in the driving/event-loop code as well.
def task_scope(var task:auto(T); body:block<(var owned:T):void>) {
    var owned <- task
    try {invoke(body,owned)} recover {
        let message="{this_context().last_exception}"
        task_cancel(owned)
        delete owned
        panic(message)
    }
    task_cancel(owned)
    delete owned
}
