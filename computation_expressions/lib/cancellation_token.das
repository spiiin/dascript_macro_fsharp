options gen2
module cancellation_token public
require ./sequence_runtime.das public
require daslib/rtti

// parent is a counted lease: a child keeps its ancestors alive and observes them.
struct CeCancellationState {references:uint64;requested:bool;reason:string;parent:CeCancellationState?}
// read_only handles observe a token but cannot request cancellation.
struct CancellationToken {owners:array<CeCancellationState?>;read_only:bool}

def private cancellation_check(token:CancellationToken) {
    if(length(token.owners)!=1) {panic("cancellation token: handle was moved or deleted")}
}
def cancellation_token() : CancellationToken {
    var inscope token:CancellationToken
    unsafe {token.owners |> push(new CeCancellationState(references=uint64(1)))}
    return <- token
}
def private cancellation_lease(var state:CeCancellationState?) {
    unsafe {
        if(state.references==uint64(-1)) {panic("cancellation token: reference count exhausted")}
        state.references++
    }
}
def private cancellation_release(var state:CeCancellationState?) {
    unsafe {
        var current=state
        while(current!=null) {
            current.references--
            if(current.references!=uint64(0)) {break}
            var parent=current.parent
            current.parent=null
            delete current
            current=parent
        }
    }
}
def cancellation_clone(token:CancellationToken) : CancellationToken {
    cancellation_check(token)
    var inscope result:CancellationToken
    unsafe {
        var state=reinterpret<CeCancellationState?>(token.owners[0])
        cancellation_lease(state)
        result.owners |> push(state)
        result.read_only=token.read_only
    }
    return <- result
}
// Child token: cancelled by its own request or by any ancestor. Cancelling a
// child never cancels its parent. The child holds a lease on the whole chain.
def cancellation_child(parent:CancellationToken) : CancellationToken {
    cancellation_check(parent)
    var inscope result:CancellationToken
    unsafe {
        var parent_state=reinterpret<CeCancellationState?>(parent.owners[0])
        cancellation_lease(parent_state)
        result.owners |> push(new CeCancellationState(references=uint64(1),parent=parent_state))
    }
    return <- result
}
// Observer handle for the same state: requested/reason work, cancel panics.
def cancellation_view(token:CancellationToken) : CancellationToken {
    var inscope result <- cancellation_clone(token)
    result.read_only=true
    return <- result
}
def cancellation_is_read_only(token:CancellationToken) : bool {
    cancellation_check(token)
    return token.read_only
}
def private cancellation_requested_state(state:CeCancellationState?) : CeCancellationState const? {
    unsafe {
        var current:CeCancellationState const?=state
        while(current!=null) {
            if(current.requested) {return current}
            current=current.parent
        }
    }
    return null
}
def cancellation_requested(token:CancellationToken) : bool {
    cancellation_check(token)
    unsafe {return cancellation_requested_state(token.owners[0])!=null}
}
// Reason of the nearest requested state (own first, then ancestors); "" if none.
def cancellation_reason(token:CancellationToken) : string {
    cancellation_check(token)
    unsafe {
        let state=cancellation_requested_state(token.owners[0])
        return state!=null ? state.reason : ""
    }
}
// Returns false when this token itself was already requested. A request that
// came only from an ancestor still lets the child record its own reason.
def cancellation_cancel(token:CancellationToken;reason:string) : bool {
    cancellation_check(token)
    if(token.read_only) {panic("cancellation token: read-only view cannot cancel")}
    unsafe {
        var state=reinterpret<CeCancellationState?>(token.owners[0])
        if(state.requested) {return false}
        state.requested=true
        state.reason=reason
    }
    return true
}
def cancellation_cancel(token:CancellationToken) : bool {return cancellation_cancel(token,"cancelled")}
def clone(var destination:CancellationToken; source:CancellationToken) {
    var inscope next <- cancellation_clone(source)
    delete destination
    destination <- next
}
def finalize(var token:CancellationToken) {
    ce_sequence_finalize($ {
        unsafe {
            if(!empty(token.owners)) {
                cancellation_release(token.owners[0])
                // delete array<pointer> also deletes its non-null elements.
                // This array owns a lease, not the shared state exclusively.
                token.owners[0]=null
            }
            delete token.owners
        }
    })
}

// Borrowed only across a synchronous poll call, never across a yield.
var private cancellation_scopes:array<CancellationToken const?>

// Cancelling one shared waiter must not cancel the shared producer. A producer
// can still install its own explicit token inside this isolated synchronous poll.
def ce_cancellation_isolate(action:block<():void>) {
    var saved <- cancellation_scopes
    try {invoke(action)} recover {
        let message="{this_context().last_exception}"
        // Scope entries are borrowed; discard them before freeing only the array.
        cancellation_scopes.resize(0)
        __builtin_array_free(cancellation_scopes,typeinfo sizeof(cancellation_scopes[0]))
        cancellation_scopes <- saved
        panic(message)
    }
    cancellation_scopes.resize(0)
    __builtin_array_free(cancellation_scopes,typeinfo sizeof(cancellation_scopes[0]))
    cancellation_scopes <- saved
}
def ce_task_cancellation_requested() : bool {
    unsafe {
        for(token in cancellation_scopes) {if(cancellation_requested(*token)) {return true}}
    }
    return false
}
def ce_cancellation_scope(token:CancellationToken; action:block<():void>) {
    let depth=length(cancellation_scopes)
    unsafe {cancellation_scopes |> push(addr(token))}
    try {invoke(action)} recover {
        let message="{this_context().last_exception}"
        cancellation_scopes.resize(depth)
        panic(message)
    }
    cancellation_scopes.resize(depth)
}
