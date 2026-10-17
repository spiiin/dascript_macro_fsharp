options gen2
module cancellation_token public
require ./sequence_runtime.das public
require daslib/rtti

struct CeCancellationState {references:uint64;requested:bool}
struct CancellationToken {owners:array<CeCancellationState?>}

def private cancellation_check(token:CancellationToken) {
    if(length(token.owners)!=1) {panic("cancellation token: handle was moved or deleted")}
}
def cancellation_token() : CancellationToken {
    var inscope token:CancellationToken
    unsafe {token.owners |> push(new CeCancellationState(references=uint64(1)))}
    return <- token
}
def cancellation_clone(token:CancellationToken) : CancellationToken {
    cancellation_check(token)
    var inscope result:CancellationToken
    unsafe {
        var state=reinterpret<CeCancellationState?>(token.owners[0])
        if(state.references==uint64(-1)) {panic("cancellation token: reference count exhausted")}
        result.owners |> push(state)
        state.references++
    }
    return <- result
}
def cancellation_requested(token:CancellationToken) : bool {
    cancellation_check(token)
    unsafe {return token.owners[0].requested}
}
def cancellation_cancel(token:CancellationToken) : bool {
    cancellation_check(token)
    unsafe {
        var state=reinterpret<CeCancellationState?>(token.owners[0])
        if(state.requested) {return false}
        state.requested=true
    }
    return true
}
def clone(var destination:CancellationToken; source:CancellationToken) {
    var inscope next <- cancellation_clone(source)
    delete destination
    destination <- next
}
def finalize(var token:CancellationToken) {
    ce_sequence_finalize($ {
        unsafe {
            if(!empty(token.owners)) {
                token.owners[0].references--
                if(token.owners[0].references==uint64(0)) {delete token.owners[0]}
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
