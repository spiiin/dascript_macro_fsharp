options gen2
module async_sequence_builder public
require ./task_builder.das public

struct AsyncSequenceContext {_ce_marker:uint8}
struct AsyncSequenceTag {_ce_marker:uint8}

def AsyncSequenceBuilder(unused:type<auto(T)>) {
    static_assert(typeinfo ce_resumable_payload(default<T>))
    var marker:T -const -&?
    return (kind=AsyncSequenceContext(),element=marker)
}
def AsyncSequenceBuilder() {return AsyncSequenceBuilder(type<int>)}

def ce_protocol(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>) {
    return ce_resumable_protocol(type<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>)
}
def ce_await_pending(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>) {return task_pending(type<variant<some:T;none:bool>>)}
def ce_await_yield(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>; value:T) {
    static_if(typeinfo can_copy(type<T>)) {return task_ready(some(value))}
    else {
        concept_assert(false,"async sequence: move-only elements require yield <- value")
        return <- ce_await_pending(builder)
    }
}
def ce_await_yield_move(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>; var value:T) {
    // Separate assignment avoids the SDK AOT variant-initializer shallow copy.
    var item:variant<some:T;none:bool>
    item as some <- value
    return <- task_ready_move(item)
}
def private ce_async_sequence_done(unused:type<auto(T)>) {
    var item <- move_none(type<T>)
    return <- task_ready_move(item)
}
def ce_await_zero(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>) {return <- ce_async_sequence_done(type<T>)}
def ce_await_return(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>; value:CeUnit) {return <- ce_await_zero(builder)}
def ce_await_return(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>; value:auto) {
    concept_assert(false,"async sequence: emit elements with yield; only bare return is supported")
    return <- ce_await_zero(builder)
}
def ce_await_value(builder:tuple<kind:AsyncSequenceContext;element:auto>; event:tuple<tag:TaskEventTag;ready:bool;value:auto(U)>) {
    concept_assert(typeinfo can_copy(type<U>),"async sequence: move-only bind needs 'var value & = source |> bind'")
    return event.value
}
def ce_await_borrow_value(builder:tuple<kind:AsyncSequenceContext;element:auto>; var event:tuple<tag:TaskEventTag;ready:bool;value:auto(U)>) : U& {unsafe {return event.value}}
def ce_await_failed(builder:tuple<kind:AsyncSequenceContext;element:auto>; event:auto) {return false}
def ce_await_failure(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>; event:auto) {return <- ce_await_pending(builder)}

// Delegation transfers the child stream into the forwarding iterator. Never
// forward its terminal None: the enclosing producer may have more elements.
def ce_await_yield_from(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>;
    var stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto>;element:iterator<T>>) {
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>> capture(<-stream) {
        while(true) {
            var inscope request <- async_sequence_next(stream)
            while(task_poll(request)==TaskStatus.Waiting) {
                yield <- task_pending(type<variant<some:T;none:bool>>)
            }
            if(request.status==TaskStatus.Cancelled) {
                ce_task_cancelled()
                yield <- task_pending(type<variant<some:T;none:bool>>)
                return false
            }
            if(request.status==TaskStatus.Failed) {panic(request.error)}
            var inscope item <- task_take(request)
            if(item is none) {break}
            yield <- ce_await_yield_move(builder,item as some)
        }
        return false
    } finally {ce_sequence_finalize($ {ce_dispose(stream)})}
}

// A next-Task owns a separate lease, never a reference into the caller's stack.
// The sequence's primary lease closes the producer even with a pending next.
def private ce_async_sequence_close(var state:auto(State)?; cancelled:bool) {
    unsafe {
        if(state.closed) {return}
        state.closed=true
        state.cancelled=cancelled
        var message=""
        try {sequence_close(state.source)} recover {message=ce_exception_message()}
        if(!empty(message)) {
            if(empty(state.error)) {state.error=message}
            ce_task_cleanup_error(message)
        }
    }
}
def private ce_async_sequence_release(var state:auto(State)?) {
    unsafe {
        state.references--
        if(state.references==0) {delete state}
    }
}
def private ce_async_sequence_lease(var state:auto(State)?; primary:bool) {
    return <- generator<State?> capture(copy(state),copy(primary)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {
        if(primary) {ce_async_sequence_close(state,true)}
        ce_async_sequence_release(state)
    })}
}
// Explicit owner/Task types let nested CE bind infer their outputs immediately,
// instead of spending inference passes expanding the implementation generators.
def ce_sequence_run(builder:tuple<kind:AsyncSequenceContext;element:auto(T)?>;
    var source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>) : tuple<tag:AsyncSequenceTag;owner:iterator<tuple<source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>;references:int;closed:bool;cancelled:bool;busy:bool;polling:bool;error:string>?>;element:iterator<T>> {
    unsafe {
        var state=new tuple<source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>;references:int;closed:bool;cancelled:bool;busy:bool;polling:bool;error:string>(source <- source,references=1)
        // Empty iterator carries T without constructing or finalizing a dummy T.
        return <- (tag=AsyncSequenceTag(),owner <- ce_async_sequence_lease(state,true),element <- default<iterator<T>>)
    }
}
def private ce_async_sequence_state(stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto(State)?>;element:auto>) : State? {
    unsafe {
        var state:State?
        var owner=reinterpret<iterator<State?>?>(addr(stream.owner))
        if(!next(*owner,state)) {panic("async sequence: owner has been moved or deleted")}
        return state
    }
}
def async_sequence_close(stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto(State)?>;element:auto>) {
    var state=ce_async_sequence_state(stream)
    unsafe {if(state.polling) {panic("async sequence: cannot close during producer poll")}}
    ce_async_sequence_close(state,true)
}
def ce_dispose(var stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto(State)?>;element:auto>) {
    async_sequence_close(stream)
    delete stream
}
def async_sequence_next(stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto(State)?>;element:iterator<auto(T)>>) : tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>;status:TaskStatus;value:variant<some:T;none:bool>;error:string;polling:bool> {
    var state=ce_async_sequence_state(stream)
    unsafe {
        if(state.busy) {panic("async sequence: only one next may be active")}
        state.busy=true
        state.references++
        var lease <- ce_async_sequence_lease(state,false)
        var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>> capture(copy(state),<-lease) {
            var delivered=false
            var event:tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>
            while(true) {
                if(state.closed) {
                    if(!empty(state.error)) {panic(state.error)}
                    if(state.cancelled) {
                        ce_task_cancelled()
                        yield <- event
                        return false
                    }
                    static_if(typeinfo can_delete(event)) {delete event}
                    event <- ce_async_sequence_done(type<T>)
                    delivered=true
                    yield <- event
                    return false
                }
                var more=false
                var message=""
                state.polling=true
                try {more=ce_sequence_next_value(state.source,event)} recover {message=ce_exception_message()}
                state.polling=false
                if(!empty(message)) {
                    state.error=message
                    ce_async_sequence_close(state,false)
                    panic(message)
                }
                if(!more) {
                    static_if(typeinfo can_delete(event)) {delete event}
                    event <- ce_async_sequence_done(type<T>)
                }
                if(event.ready) {
                    if(event.value is none) {ce_async_sequence_close(state,false)}
                    delivered=true
                    yield <- event
                    return false
                }
                yield <- event
            }
            return false
        } finally {ce_sequence_finalize($ {
            if(!delivered || ce_task_cancellation_requested()) {ce_async_sequence_close(state,true)}
            state.busy=false
            static_if(typeinfo can_delete(event)) {delete event}
            delete lease
        })}
        return <- task_create(events)
    }
}
