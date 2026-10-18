options gen2
module async_sequence_builder public
require ./task_combinators.das public
require daslib/rtti

struct AsyncSequenceContext {_ce_marker:uint8}
struct AsyncSequenceTag {_ce_marker:uint8}

// Task grouping has TaskBuilder semantics: Result/Option payloads remain data.
// Reuse its owning combinator for cooperative polling, cancellation and cleanup.
def ce_merge_sources(builder:tuple<kind:AsyncSequenceContext;element:auto>;
    var left:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(L)>>;status:TaskStatus;value:L;error:string;polling:bool>;
    var right:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(R)>>;status:TaskStatus;value:R;error:string;polling:bool>) {
    return <- task_when_all(left,right)
}

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

// One iterator owns both the Task and its event slot. The yielded reference
// stays valid across the entire continuation, including subsequent suspension.
def ce_await_input(builder:tuple<kind:AsyncSequenceContext;element:auto>;
    var task:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) : iterator<tuple<tag:TaskEventTag;ready:bool;value:T>&> {
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:T>&> capture(<-task) {
        var event:tuple<tag:TaskEventTag;ready:bool;value:T>
        while(true) {
            var status=TaskStatus.Created
            var message=""
            var failed=false
            try {status=task_poll(task)} recover {message="{this_context().last_exception}";failed=true}
            if(status==TaskStatus.Failed) {message=task_error(task);failed=true}
            if(failed) {
                // Close immediately, before an enclosing try_with can resume.
                ce_sequence_finalize($ {task_cancel(task);delete task})
                panic(message)
            }
            if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {
                ce_task_cancelled()
                yield event
                return false
            }
            if(status==TaskStatus.Succeeded) {
                event.ready=true
                static_if(typeinfo can_copy(type<T>)) {event.value=task_value(task)}
                else {event.value <- task.value}
                yield event
                break
            }
            yield event
        }
        return false
    } finally {ce_sequence_finalize($ {
        static_if(typeinfo can_delete(event)) {delete event}
        let cancelled=task_cancel(task)
        if(cancelled && task_status(task)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(task))}
        delete task
    })}
}

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

// The lowerer moves the payload into an iteration owner, safe to capture across
// nested awaits/resources. A signalled break never polls another next.
def ce_await_for_source(builder:tuple<kind:AsyncSequenceContext;element:auto?>;
    var stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto>;element:iterator<auto(T)>>;
    control:CeTaskLoopControl?) {
    var events <- ce_await_yield_from(AsyncSequenceBuilder(type<T>),stream)
    return <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>> capture(<-events,copy(control)) {
        var event:tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>
        while(ce_task_loop_not_broken(control)) {
            if(!ce_sequence_next_value(events,event)) {break}
            yield <- event
        }
        return false
    } finally {ce_sequence_finalize($ {
        delete event
        sequence_close(events)
    })}
}

def ce_await_for_value(builder:tuple<kind:AsyncSequenceContext;element:auto?>;
    var event:tuple<tag:TaskEventTag;ready:bool;value:variant<some:auto(T);none:bool>>) : T& {
    unsafe {return event.value as some}
}

def private ce_async_sequence_zip_check(request:auto) : bool {
    if(request.status==TaskStatus.Failed) {panic(request.error)}
    if(request.status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {
        ce_task_cancelled()
        return false
    }
    return true
}

// A binary zip composes to any arity. Each round keeps one next per child,
// polls left-to-right, and stops immediately when either child reports None.
def ce_await_for_merge(builder:tuple<kind:AsyncSequenceContext;element:auto?>;
    var left:tuple<tag:AsyncSequenceTag;owner:iterator<auto>;element:iterator<auto(L)>>;
    var right:tuple<tag:AsyncSequenceTag;owner:iterator<auto>;element:iterator<auto(R)>>) {
    unsafe {
        if(reinterpret<void?>(ce_async_sequence_state(left))==reinterpret<void?>(ce_async_sequence_state(right))) {
            panic("async For: the same stream cannot be used twice")
        }
    }
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:tuple<first:L;second:R>;none:bool>>> capture(<-left,<-right) {
        while(true) {
            var inscope first <- async_sequence_next(left)
            var inscope second <- async_sequence_next(right)
            while(true) {
                task_poll(first)
                if(!ce_async_sequence_zip_check(first)) {
                    yield <- task_pending(type<variant<some:tuple<first:L;second:R>;none:bool>>)
                    return false
                }
                if(first.status==TaskStatus.Succeeded && first.value is none) {return false}
                task_poll(second)
                if(!ce_async_sequence_zip_check(second)) {
                    yield <- task_pending(type<variant<some:tuple<first:L;second:R>;none:bool>>)
                    return false
                }
                if(second.status==TaskStatus.Succeeded && second.value is none) {return false}
                if(first.status==TaskStatus.Succeeded && second.status==TaskStatus.Succeeded) {
                    var pair:tuple<first:L;second:R>
                    pair.first <- first.value as some
                    pair.second <- second.value as some
                    yield <- ce_await_yield_move(AsyncSequenceBuilder(type<tuple<first:L;second:R>>),pair)
                    break
                }
                yield <- task_pending(type<variant<some:tuple<first:L;second:R>;none:bool>>)
            }
        }
        return false
    } finally {ce_sequence_finalize($ {
        ce_dispose(left)
        ce_dispose(right)
    })}
    return <- ce_sequence_run(AsyncSequenceBuilder(type<tuple<first:L;second:R>>),events)
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
    // For/yield_from may consume a stream already registered with use_resource.
    if(!empty(stream.owner)) {async_sequence_close(stream)}
    delete stream
}
def async_sequence_next(stream:tuple<tag:AsyncSequenceTag;owner:iterator<auto(State)?>;element:iterator<auto(T)>>) : tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>>;status:TaskStatus;value:variant<some:T;none:bool>;error:string;polling:bool> {
    var state=ce_async_sequence_state(stream)
    unsafe {
        if(state.busy) {panic("async sequence: only one next may be active")}
        state.busy=true
        state.references++
        // The request generator itself owns the counted reference. Its finally
        // also runs when unopened, so a second lease iterator is unnecessary.
        var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:T;none:bool>>> capture(copy(state)) {
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
            ce_async_sequence_release(state)
        })}
        return <- task_create(events)
    }
}
