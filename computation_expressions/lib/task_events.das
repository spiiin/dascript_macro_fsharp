options gen2
module task_events public
require ./task_builder.das public

struct TaskEventSourceTag {_ce_marker:uint8}
var private event_sources_created=0
var private event_sources_released=0
var private event_waits_created=0
var private event_waits_released=0
var private event_subscribed=0
var private event_unsubscribed=0

def task_event_stats() {
    return (sources=event_sources_created-event_sources_released,
        waits=event_waits_created-event_waits_released,
        subscriptions=event_subscribed-event_unsubscribed,
        subscribed=event_subscribed,unsubscribed=event_unsubscribed)
}

// Only the owner's lease closes the source; waiter leases retain its storage.
// Generator cleanup also runs when a lease is deleted before its first yield.
def private ce_event_lease(var state:auto(S)?;close_source:bool=false) {
    return <- generator<S?> capture(copy(state),copy(close_source)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {
        unsafe {
            if(close_source) {state.closed=true}
            state.references--
            if(state.references==uint64(0)) {delete state;event_sources_released++}
        }
    })}
}

def private ce_event_state(source:tuple<tag:TaskEventSourceTag;owner:iterator<auto(S)?>>) : S? {
    unsafe {
        var lease=reinterpret<iterator<S?>?>(addr(source.owner))
        var state:S?
        if(!next(*lease,state)) {panic("task event source: handle was moved or deleted")}
        return state
    }
}

def task_event_source(unused:type<auto(T)>) {
    static_assert(typeinfo ce_resumable_payload(default<T -const -&>))
    concept_assert(typeinfo can_copy(type<T -const -&>),"task events: broadcast payload must be copyable")
    unsafe {
        var state=new tuple<references:uint64;closed:bool;serial:uint64;slots:array<tuple<id:uint64;ready:bool;value:T -const -&>>>(references=uint64(1))
        event_sources_created++
        return <- (tag=TaskEventSourceTag(),owner <- ce_event_lease(state,true))
    }
}

def task_event_close(source:tuple<tag:TaskEventSourceTag;owner:iterator<auto(S)?>>) : bool {
    var state=ce_event_state(source)
    unsafe {
        if(state.closed) {return false}
        state.closed=true
        return true
    }
}

def ce_dispose(var source:tuple<tag:TaskEventSourceTag;owner:auto>) {
    sequence_close(source.owner)
}

def task_event_subscriber_count(source:tuple<tag:TaskEventSourceTag;owner:iterator<auto(S)?>>) : int {
    let state=ce_event_state(source)
    unsafe {return length(state.slots)}
}

// Broadcast only to already registered waits. Each wait latches its first event.
// No user continuation or callback runs while emit walks the slots.
def task_event_emit(source:tuple<tag:TaskEventSourceTag;owner:iterator<auto(S)?>>;value:auto(T)) : int {
    var state=ce_event_state(source)
    unsafe {
        if(state.closed) {return 0}
        var delivered=0
        for(slot in state.slots) {
            if(!slot.ready) {
                // Native callbacks may supply a borrowed string# buffer.
                static_if(typeinfo is_string(type<T>)) {slot.value=string(value)}
                else {slot.value=value}
                slot.ready=true;delivered++
            }
        }
        return delivered
    }
}

def private ce_event_poll(var op:auto(O)?) {
    unsafe {
        var state=op.state
        if(op.id==uint64(0) && !state.closed) {
            if(state.serial==uint64(-1)) {panic("task events: subscription IDs exhausted")}
            state.serial++;op.id=state.serial
            var slot:typedecl(state.slots[0]) -& -const
            slot.id=op.id
            state.slots |> push(slot)
            event_subscribed++
        }
        for(slot in state.slots) {
            if(slot.id==op.id && slot.ready) {return task_ready(result_ok(slot.value))}
        }
        if(state.closed) {return task_ready(result_error("task event source is closed",type<typedecl(state.slots[0].value) -const -&>))}
        return task_pending(type<variant<ok:typedecl(state.slots[0].value) -const -&;error:string>>)
    }
}

def private ce_event_finish(var op:auto(O)?) {
    unsafe {
        var state=op.state
        for(i in range(length(state.slots))) {
            if(state.slots[i].id==op.id) {
                state.slots |> erase(i)
                event_unsubscribed++
                break
            }
        }
        // The lease owns the reference. Never let the alias auto-delete it.
        op.state=null
        sequence_close(op.lease)
        delete op
        event_waits_released++
    }
}

def task_wait_event(source:tuple<tag:TaskEventSourceTag;owner:iterator<auto(S)?>>) {
    var state=ce_event_state(source)
    unsafe {
        if(state.references==uint64(-1)) {panic("task events: reference count exhausted")}
        state.references++
        var op=new tuple<state:S?;lease:iterator<S?>;id:uint64>(state=state,lease <- ce_event_lease(state))
        event_waits_created++
        return <- task_from_poll(@(){return ce_event_poll(op)},@(){ce_event_finish(op)})
    }
}
