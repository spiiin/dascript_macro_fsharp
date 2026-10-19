options gen2
module task_builder public
require ./computation_builders.das public
require ./sequence_runtime.das public
require ./resumable_lowering.das public
require ./cancellation_token.das public
require ./move_builders.das public
require daslib/rtti

enum TaskStatus {
    Created
    Waiting
    Succeeded
    Cancelled
    Failed
}
struct TaskTag {_ce_marker:uint8}
struct TaskEventTag {_ce_marker:uint8}
struct TaskContext {_ce_marker:uint8}
struct TaskResultContext {_ce_marker:uint8}
def ce_task_local_delete(var value:auto) {static_if(typeinfo can_delete(value)) {delete value}}

// Control is handle by nested await/resource generators, scoped to one loop.
struct CeTaskLoopControl {signal:int}
def ce_task_loop_scope() {
    var state=new CeTaskLoopControl()
    return <- generator<CeTaskLoopControl?> capture(copy(state)) {
        yield state
        return false
    } finally {ce_sequence_finalize($ {unsafe {delete state}})}
}
def ce_task_loop_signal(state:CeTaskLoopControl?; signal:int) {unsafe {var current=reinterpret<CeTaskLoopControl?>(state);current.signal=signal}}
def ce_task_loop_active(state:CeTaskLoopControl?) : bool {unsafe {return state.signal==0}}
def ce_task_loop_not_broken(state:CeTaskLoopControl?) : bool {unsafe {return state.signal!=1}}

def private ce_task_loop_input(var source:iterator<auto(T)>; state:CeTaskLoopControl?) : iterator<T> {
    var cursor <- ce_zip_cursor(source)
    return <- generator<T> capture(<-cursor,copy(state)) {
        while(ce_task_loop_not_broken(state)) {
            var more=false
            var failed=false
            var message=""
            try {more=ce_zip_next(cursor)} recover {failed=true;message=ce_exception_message()}
            if(failed) {ce_zip_close(cursor,message);panic(message)}
            if(!more) {break}
            static_if(typeinfo is_ref_value(type<T>)) {unsafe {yield *cursor.slot}}
            else {yield cursor.slot}
        }
        return false
    } finally {ce_sequence_finalize($ {var message="";ce_zip_close(cursor,message);if(!empty(message)){ce_task_cleanup_error(message)}})}
}
def ce_task_loop_source(var source:iterator<auto>;state:CeTaskLoopControl?) {return <- ce_task_loop_input(source,state)}
def ce_task_loop_source_owned(var source:iterator<auto>;state:CeTaskLoopControl?) {return <- ce_task_loop_input(source,state)}
def ce_task_loop_source_owned(var source:array<auto(Item)>;state:CeTaskLoopControl?) {
    var stream <- generator<Item&> capture(<-source) {
        var index=0
        while(index<length(source)) {yield source[index];index++}
        return false
    } finally {ce_sequence_finalize($ {delete source})}
    return <- ce_task_loop_input(stream,state)
}
def ce_task_loop_source(source:auto ==const;state:CeTaskLoopControl?) {
    unsafe {var stream <- each(source);return <- ce_task_loop_input(stream,state)}
}
def ce_task_loop_source(var source:auto ==const;state:CeTaskLoopControl?) {
    unsafe {var stream <- each(source);return <- ce_task_loop_input(stream,state)}
}
def ce_task_is_polling(task:auto) : bool {return task.polling}
def ce_await_borrow_value(builder:auto; source:auto) {
    concept_assert(false,"task: reference binding requires an owning array Task")
}

// Task is single-threaded. A nested error scope reports callback failures only
// after native iterator finalizers have returned and released their closures.
// Throwing directly from a 0.6.4 generator finalizer skips its deallocation.
struct TaskPollScope {error:string;cancelled:bool}
var private task_cleanup_scopes:array<TaskPollScope>
def private task_cleanup_begin() {task_cleanup_scopes |> push(TaskPollScope())}
def ce_task_cleanup_error(message:string) {
    let count=length(task_cleanup_scopes)
    if(count>0 && empty(task_cleanup_scopes[count-1].error)) {task_cleanup_scopes[count-1].error=message}
}
// Task/AsyncSequence resource scopes must not throw from native generator
// finalizers: the SDK then skips freeing the iterator closure. Record cleanup
// failures in the surrounding poll/cancel scope after releasing every owner.
def ce_sequence_scoped(var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(ScopedTaskValue)>>;
    var cleanup:lambda<():void>) : iterator<tuple<tag:TaskEventTag;ready:bool;value:ScopedTaskValue>> {
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:ScopedTaskValue>> capture(<-source,<-cleanup) {
        var event:tuple<tag:TaskEventTag;ready:bool;value:ScopedTaskValue>
        while(ce_sequence_next_value(source,event)) {
            static_if(typeinfo can_copy(type<ScopedTaskValue>)) {yield event}
            else {yield <- event}
        }
        return false
    } finally {ce_sequence_finalize($ {
        var message=""
        try {sequence_close(source)} recover {message="{this_context().last_exception}"}
        try {invoke(cleanup)} recover {if(empty(message)) {message="{this_context().last_exception}"}}
        try {unsafe {delete cleanup}} recover {if(empty(message)) {message="{this_context().last_exception}"}}
        static_if(typeinfo can_delete(event)) {
            try {delete event} recover {if(empty(message)) {message="{this_context().last_exception}"}}
        }
        if(!empty(message)) {ce_task_cleanup_error(message)}
    })}
}

// Cancellation is a scoped control signal, never a catchable panic/string.
def ce_task_cancelled() {
    let count=length(task_cleanup_scopes)
    if(count>0) {task_cleanup_scopes[count-1].cancelled=true}
}
def private task_cleanup_cancelled() : bool {
    let count=length(task_cleanup_scopes)
    return count>0 && task_cleanup_scopes[count-1].cancelled
}
def private task_cleanup_current() : string {
    let count=length(task_cleanup_scopes)
    return count>0 ? task_cleanup_scopes[count-1].error : ""
}
def private task_cleanup_end() : string {
    let message=task_cleanup_current()
    task_cleanup_scopes.resize(length(task_cleanup_scopes)-1)
    return message
}

def task_pending(unused:type<auto(T)>) {
    static_if(typeinfo can_copy(type<T -const -&>)) {
        return (tag=TaskEventTag(),ready=false,value=default<T -const -&>)
    } else {return <- (tag=TaskEventTag(),ready=false,value <- default<T -const -&>)}
}
def task_ready(value:auto(T)) {
    concept_assert(typeinfo can_copy(type<T>),"task: move-only return needs 'return <- value' or task_ready_move")
    return tuple<tag:TaskEventTag;ready:bool;value:T -const -&>(tag=TaskEventTag(),ready=true,value=value)
}

def task_ready_move(var value:auto(T)) {
    static_assert(typeinfo ce_resumable_payload(default<T -const -&>))
    return <- (tag=TaskEventTag(),ready=true,value <- value)
}
def task_create(var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>) {
    static_assert(typeinfo ce_resumable_payload(default<T>))
    return <- (tag=TaskTag(),source <- source,status=TaskStatus.Created,value <- default<T>,error="",polling=false)
}
def TaskBuilder(unused:type<auto(T)>) {var marker:T -const -&?;return (kind=TaskContext(),element=marker)}
def TaskResultBuilder(unused:type<auto(T)>) {var marker:T -const -&?;return (kind=TaskResultContext(),element=marker)}

// Resumable streams may emit values; single-result Task builders may not.
def ce_await_yield(builder:auto; value:auto) {
    concept_assert(false,"task: use source |> bind to await; yield is not supported")
    return <- ce_await_pending(builder)
}
def ce_await_yield_move(builder:auto; var value:auto) {
    concept_assert(false,"task: use source |> bind to await; yield is not supported")
    return <- ce_await_pending(builder)
}

def ce_protocol(builder:tuple<kind:TaskContext;element:auto(T)?>) {
    return ce_resumable_protocol(type<tuple<tag:TaskEventTag;ready:bool;value:T>>)
}
def ce_protocol(builder:tuple<kind:TaskResultContext;element:auto(T)?>) {
    return ce_resumable_protocol(type<tuple<tag:TaskEventTag;ready:bool;value:variant<ok:T;error:string>>>)
}
def ce_await_pending(builder:tuple<kind:TaskContext;element:auto(T)?>) {return task_pending(type<T>)}
def ce_await_pending(builder:tuple<kind:TaskResultContext;element:auto(T)?>) {return task_pending(type<variant<ok:T;error:string>>)}
def ce_await_return(builder:tuple<kind:TaskContext;element:auto(T)?>; value:T) {return task_ready(value)}
def ce_await_return(builder:tuple<kind:TaskResultContext;element:auto(T)?>; value:T) {return task_ready(result_ok(value))}

def ce_await_return_move(builder:tuple<kind:TaskContext;element:auto(T)?>; var value:T) {return <- task_ready_move(value)}
def ce_await_return_move(builder:tuple<kind:TaskResultContext;element:auto(T)?>; var value:T) {
    var result <- move_ok(value)
    return <- task_ready_move(result)
}
def ce_await_zero(builder:tuple<kind:TaskContext;element:CeUnit?>) {return task_ready(CeUnit())}
def ce_await_zero(builder:tuple<kind:TaskResultContext;element:CeUnit?>) {return task_ready(result_ok(CeUnit()))}

def ce_await_borrow_value(builder:tuple<kind:TaskContext;element:auto>; var event:tuple<tag:TaskEventTag;ready:bool;value:auto(T)>) : T& {
    unsafe {return event.value}
}
def ce_await_borrow_value(builder:tuple<kind:TaskResultContext;element:auto>; var event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(T);error:string>>) : T& {
    unsafe {return event.value as ok}
}
def ce_await_borrow_value(builder:tuple<kind:TaskResultContext;element:auto>; var event:tuple<tag:TaskEventTag;ready:bool;value:CeUnit>) : CeUnit& {return event.value}
def ce_await_borrow_value(builder:tuple<kind:TaskResultContext;element:auto>; var event:tuple<tag:TaskEventTag;ready:bool;value:array<auto(T)>>) : array<T>& {unsafe {return event.value}}
def ce_await_failed(builder:tuple<kind:TaskResultContext;element:auto>; event:tuple<tag:TaskEventTag;ready:bool;value:array<auto>>) {return false}
def ce_await_failure(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:array<auto>>) {return <- task_pending(type<variant<ok:T;error:string>>)}
def ce_await_value(builder:tuple<kind:TaskContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:auto(U)>) {
    concept_assert(typeinfo can_copy(type<U>),"task: move-only bind needs 'var value & = source |> bind'")
    return event.value
}
def ce_await_value(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {
    concept_assert(typeinfo can_copy(type<U>),"task: move-only bind needs 'var value & = source |> bind'")
    return event.value as ok
}
def ce_await_failed(builder:tuple<kind:TaskContext;element:auto(T)?>; event:auto) {return false}
def ce_await_failed(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {return event.value is error}
def ce_await_failure(builder:tuple<kind:TaskContext;element:auto(T)?>; event:auto) {return task_pending(type<T>)}
def ce_await_failure(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:variant<ok:auto(U);error:string>>) {
    var result <- move_error(event.value as error,type<T>)
    return <- task_ready_move(result)
}

// Unit operations have no domain Error; native failure/cancellation still
// propagate through ce_await_source. This also permits delay |> bind in TaskResult.
def ce_await_value(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:CeUnit>) {return CeUnit()}
def ce_await_failed(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:CeUnit>) {return false}
def ce_await_failure(builder:tuple<kind:TaskResultContext;element:auto(T)?>; event:tuple<tag:TaskEventTag;ready:bool;value:CeUnit>) {return task_pending(type<variant<ok:T;error:string>>)}

def ce_sequence_run(builder:tuple<kind:TaskContext;element:auto(T)?>; var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:T>>) {return <- task_create(source)}
def ce_sequence_run(builder:tuple<kind:TaskResultContext;element:auto(T)?>; var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<ok:T;error:string>>>) {return <- task_create(source)}

def task_status(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) {return task.status}
def task_value(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : T {
    if(task.status!=TaskStatus.Succeeded) {panic("task_value: task has not succeeded")}
    static_if(typeinfo can_copy(type<T>)) {return task.value}
    else {return <- clone(task.value)}
}

def task_take(var task:auto) {
    if(ce_task_is_polling(task)) {panic("task_take: task is being polled")}
    if(task_status(task)!=TaskStatus.Succeeded) {panic("task_take: task has not succeeded")}
    var result <- task.value
    delete task
    return <- result
}
def task_error(task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) {return task.error}

def task_cancel(var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : bool {
    if(task.polling) {panic("task_cancel: task is being polled")}
    if(task.status!=TaskStatus.Created && task.status!=TaskStatus.Waiting) {return false}
    task_cleanup_begin()
    task.status=TaskStatus.Cancelled
    try {sequence_close(task.source)} recover {task.status=TaskStatus.Failed;task.error="{this_context().last_exception}"}
    let cleanup=task_cleanup_end()
    if(!empty(cleanup) && task.status!=TaskStatus.Failed) {task.status=TaskStatus.Failed;task.error=cleanup}
    return true
}

// One poll drives the continuation to its next suspension or final result.
// Terminal results are cached. There is no implicit busy-wait or worker thread.
def task_poll(var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : TaskStatus {
    if(task.polling) {panic("task_poll: reentrant polling is unsupported")}
    if(task.status!=TaskStatus.Created && task.status!=TaskStatus.Waiting) {return task.status}
    if(ce_task_cancellation_requested()) {task_cancel(task);return task.status}
    task.polling=true
    task_cleanup_begin()
    var event <- task_pending(type<T>)
    try {
        let more=ce_sequence_next_value(task.source,event)
        if(task_cleanup_cancelled() || ce_task_cancellation_requested()) {
            task.status=TaskStatus.Cancelled
            sequence_close(task.source)
        } elif(!more) {panic("task: computation ended without return")}
        elif(event.ready) {
            static_if(typeinfo can_copy(type<T>)) {task.value=event.value}
            else {task.value <- event.value}
            task.status=TaskStatus.Succeeded
            sequence_close(task.source)
        } else {task.status=TaskStatus.Waiting}
    } recover {
        task.error="{this_context().last_exception}"
        task.status=TaskStatus.Failed
        try {sequence_close(task.source)} recover {}
    }
    let cleanup=task_cleanup_current()
    if(!empty(cleanup) && task.status!=TaskStatus.Failed) {
        task.status=TaskStatus.Failed;task.error=cleanup
        try {sequence_close(task.source)} recover {}
    }
    task_cleanup_end()
    task.polling=false
    static_if(typeinfo can_delete(event)) {delete event}
    if(task.status==TaskStatus.Failed || task.status==TaskStatus.Cancelled) {
        static_if(typeinfo can_delete(task.value)) {delete task.value}
    }
    return task.status
}

// Move an awaited child into the parent; closing the parent cancels the child.
def ce_await_source(builder:auto; var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : iterator<tuple<tag:TaskEventTag;ready:bool;value:T>> {
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:T>> capture(<-task) {
        while(true) {
            let status=task_poll(task)
            if(status==TaskStatus.Failed) {panic(task_error(task))}
            if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {
                ce_task_cancelled()
                yield <- task_pending(type<T>)
                return false
            }
            if(status==TaskStatus.Succeeded) {
                static_if(typeinfo can_copy(type<T>)) {yield task_ready(task_value(task))}
                else {yield <- task_ready_move(task.value)}
                break
            }
            yield <- task_pending(type<T>)
        }
        return false
    } finally {ce_sequence_finalize($ {
        let cancelled=task_cancel(task)
        if(cancelled && task_status(task)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(task))}
        delete task
    })}
}

// Own both a child and a lease on the handle token. The dynamic scope lasts
// only for task_poll, so nested binds observe the token without stack captures.
def task_with_cancellation(var task:auto; token:CancellationToken) {
    if(task.polling) {panic("task cancellation: cannot move a task being polled")}
    var lease <- cancellation_clone(token)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:typedecl(task.value) -const -&>> capture(<-task,<-lease) {
        while(true) {
            var status=TaskStatus.Created
            ce_cancellation_scope(lease,$ {status=task_poll(task)})
            if(status==TaskStatus.Failed) {panic(task_error(task))}
            if(status==TaskStatus.Cancelled || cancellation_requested(lease)) {
                ce_task_cancelled()
                yield <- task_pending(type<typedecl(task.value) -const -&>)
                return false
            }
            if(status==TaskStatus.Succeeded) {yield <- task_ready_move(task.value);return false}
            yield <- task_pending(type<typedecl(task.value) -const -&>)
        }
        return false
    } finally {ce_sequence_finalize($ {
        let cancelled=task_cancel(task)
        if(cancelled && task_status(task)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(task))}
        delete task
        delete lease
    })}
    return <- task_create(events)
}

// Adapter for a nonblocking operation's poll callback. The lambda owns captures.
// Each poll returns Pending or Ready; close runs on success, cancellation or panic.
def private task_close_callbacks(var poll:lambda<():auto(T)>; var close:lambda<():void>) {
    var message=""
    try {invoke(close)} recover {message="{this_context().last_exception}"}
    unsafe {delete poll;delete close}
    if(!empty(message)) {ce_task_cleanup_error(message)}
}

def task_from_poll(var poll:lambda<():tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>; var close:lambda<():void>) {
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:T>> capture(<-poll,<-close) {
        while(true) {
            var event <- invoke(poll)
            let ready=event.ready
            static_if(typeinfo can_copy(type<T>)) {yield event}
            else {yield <- event}
            if(ready) {break}
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

def task_after_polls_move(count:int;var value:auto(OwnedValue)) {
    if(count<0) {panic("task_after_polls_move: count must be non-negative")}
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:OwnedValue -const -&>> capture(<-value) {
        for(i in range(count)) {yield <- task_pending(type<OwnedValue -const -&>)}
        yield <- task_ready_move(value)
        return false
    } finally {ce_sequence_finalize($ {static_if(typeinfo can_delete(value)) {delete value}})}
    return <- task_create(events)
}

// Standard [async] generators can produce several res events. Like native await,
// finish the producer and retain its last result; only wait events suspend us.
// This also observes side effects and exceptions after the last yielded value.
def task_from_async(var source:iterator<variant<res:auto(T);wait:bool>>) {
    static_assert(typeinfo ce_resumable_payload(default<T>))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:T -const -&>> capture(<-source) {
        var event:variant<res:T;wait:bool>
        var value:T -const -&
        var received=false
        while(ce_sequence_next_value(source,event)) {
            if(event is res) {
                static_if(typeinfo can_copy(type<T>)) {value=event as res}
                else {delete value;value <- event as res}
                received=true
            }
            else {yield <- task_pending(type<T>)}
        }
        sequence_close(source)
        if(!received) {panic("task_from_async: async completed without a result")}
        yield <- task_ready_move(value)
        return false
    } finally {ce_sequence_finalize($ {
        sequence_close(source)
        static_if(typeinfo can_delete(value)) {delete value}
        static_if(typeinfo can_delete(event)) {delete event}
    })}
    return <- task_create(events)
}

// Void [async] functions produce iterator<bool>; completion yields successful Unit.
def task_from_async(var source:iterator<bool>) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:CeUnit>> capture(<-source) {
        var waiting=false
        while(ce_sequence_next_value(source,waiting)) {yield task_pending(type<CeUnit>)}
        sequence_close(source)
        yield task_ready(CeUnit())
        return false
    } finally {ce_sequence_finalize($ {sequence_close(source)})}
    return <- task_create(events)
}

// Own an external operation/resource until the async source is closed. The
// Sequence owner runs close even for an unstarted source and frees the lambda.
def task_from_async(var source:iterator<auto(T)>; var close:lambda<():void>) {
    var safeClose <- @ capture(move(close)) {
        var message=""
        try {invoke(close)} recover {message="{this_context().last_exception}"}
        unsafe {delete close}
        if(!empty(message)) {ce_task_cleanup_error(message)}
    }
    var scoped <- ce_sequence_scoped(source,safeClose)
    return <- task_from_async(scoped)
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
    let cancelled=task_cancel(owned)
    var cleanup=""
    if(cancelled && task_status(owned)==TaskStatus.Failed) {cleanup=task_error(owned)}
    delete owned
    if(!empty(cleanup)) {panic(cleanup)}
}

struct TaskSharedTag {_ce_marker:uint8}

def private ce_task_shared_lease(var state:auto(SharedState)?) {
    var owner <- generator<SharedState?> capture(copy(state)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {
        unsafe {
            state.references--
            if(state.references==uint64(0)) {
                let cancelled=task_cancel(state.task)
                if(cancelled && task_status(state.task)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(state.task))}
                delete state
            }
        }
    })}
    return <- (tag=TaskSharedTag(),owner <- owner)
}
def task_share(var task:auto(SharedOwner)) {
    if(ce_task_is_polling(task)) {panic("task_share: cannot move a task being polled")}
    unsafe {
        var state=new tuple<references:uint64;task:SharedOwner>(references=uint64(1),task <- task)
        return <- ce_task_shared_lease(state)
    }
}
def private ce_task_shared_state(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) : SharedState? {
    var state:SharedState?
    unsafe {
        var lease=reinterpret<iterator<SharedState?>?>(addr(handle.owner))
        if(!next(*lease,state)) {panic("shared Task: handle has been moved or deleted")}
        return state
    }
}
def task_shared_clone(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    unsafe {
        if(state.references==uint64(-1)) {panic("shared Task: reference count exhausted")}
        state.references++
        return <- ce_task_shared_lease(state)
    }
}
def clone(var target:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>; source:tuple<tag:TaskSharedTag;owner:iterator<SharedState?>>) {
    var next <- task_shared_clone(source)
    delete target
    target <- next
}
def task_status(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    unsafe {return task_status(state.task)}
}
def task_error(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    unsafe {return task_error(state.task)}
}
def task_value(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    unsafe {
        static_if(typeinfo can_copy(state.task.value)) {return task_value(state.task)}
        else {return <- task_value(state.task)}
    }
}
def ce_task_is_polling(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) : bool {
    var state=ce_task_shared_state(handle)
    unsafe {return state.task.polling}
}
def task_poll(var handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    var status=TaskStatus.Created
    unsafe {ce_cancellation_isolate($ {status=task_poll(state.task)})}
    return status
}
def task_cancel(var handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var state=ce_task_shared_state(handle)
    unsafe {return task_cancel(state.task)}
}
def task_from_shared(var handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    typedef SharedValue=typedecl(task_value(handle)) -const -&
    var source <- generator<tuple<tag:TaskEventTag;ready:bool;value:SharedValue>> capture(<-handle) {
        while(true) {
            let status=task_poll(handle)
            if(status==TaskStatus.Failed) {panic(task_error(handle))}
            if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {
                ce_task_cancelled();yield <- task_pending(type<SharedValue>);return false
            }
            if(status==TaskStatus.Succeeded) {
                var value:SharedValue
                static_if(typeinfo can_copy(type<SharedValue>)) {value=task_value(handle)}
                else {value <- task_value(handle)}
                yield <- task_ready_move(value)
                return false
            }
            yield <- task_pending(type<SharedValue>)
        }
        return false
    } finally {ce_sequence_finalize($ {delete handle})}
    return <- task_create(source)
}
def ce_task_source(var task:auto) {return <- task}
def ce_task_source(handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var lease <- task_shared_clone(handle)
    return <- task_from_shared(lease)
}
def ce_source(builder:auto; handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {return <- ce_task_source(handle)}
def ce_await_source(builder:auto; handle:tuple<tag:TaskSharedTag;owner:iterator<auto(SharedState)?>>) {
    var source <- ce_task_source(handle)
    return <- ce_await_source(builder,source)
}
