options gen2
module deferred_runtime public
require ./sequence_runtime.das public
require daslib/rtti

struct DeferredComputation {_ce_marker:uint8}
struct CeDeferredValueBuilder {_ce_marker:uint8}
struct CeDeferredTypeBuilder {_ce_marker:uint8}
struct CeDeferredTaskBuilder {_ce_marker:uint8}
struct CeDeferredAsyncSequenceBuilder {_ce_marker:uint8}
def private ce_deferred_copy_builder(var target:auto; source:auto; policy:CeDeferredValueBuilder) {target := source}
// The macro checks that this built-in phantom descriptor contains only null.
def private ce_deferred_copy_builder(var target:auto; source:auto; policy:CeDeferredTypeBuilder) {target.element = null}
def private ce_deferred_copy_builder(var target:auto; source:auto; policy:CeDeferredTaskBuilder) {target.element = null}
def private ce_deferred_copy_builder(var target:auto; source:auto; policy:CeDeferredAsyncSequenceBuilder) {target.element = null}

def private ce_deferred_finish(var result:auto;var frame:auto?;policy:auto) {
    unsafe {delete frame}
    return <- result
}
def private ce_deferred_finish(var result:auto;var frame:auto?;policy:CeDeferredTaskBuilder) {
    var cleanup <- @ capture(move(frame)) {unsafe {delete frame}}
    result.source <- ce_deferred_wrap_sequence(result.source,cleanup)
    return <- result
}
def private ce_deferred_finish(var result:tuple<tag:auto;owner:iterator<auto(State)?>;element:auto>;var frame:auto?;policy:CeDeferredAsyncSequenceBuilder) {
    var cleanup <- @ capture(move(frame)) {unsafe {delete frame}}
    // The producer owns the frame across all next-Tasks; its finalizers run
    // before cleanup, even if the primary lease closes while next is pending.
    var state:State?
    if(!next(result.owner,state)) {panic("deferred: AsyncSequence owner is closed")}
    unsafe {state.source <- ce_deferred_wrap_sequence(state.source,cleanup)}
    return <- result
}


def private ce_deferred_delete(var value:auto) {
    static_if (typeinfo can_delete(value)) { delete value }
}

def private ce_deferred_hold(var body:lambda<():auto(R)>) {
    var owner <- generator<lambda<():R>> capture(<-body) {
        while (true) { yield body }
        return false
    } finally { ce_sequence_finalize($ { unsafe { delete body } }) }
    return <- (kind=DeferredComputation(),owner <- owner)
}

def ce_deferred_create(builder:auto(B); data:auto(E); body:function<(frame:tuple<marker:int;builder:B -const -&;value:E -const -&>?):auto(R)>; policy:auto(P)) {
    var savedBuilder=default<B -const -&>
    var savedData=default<E -const -&>
    try { ce_deferred_copy_builder(savedBuilder,builder,policy); savedData := data } recover {
        let message="{this_context().last_exception}"
        ce_deferred_delete(savedData)
        ce_deferred_delete(savedBuilder)
        panic(message)
    }
    var thunk <- @ capture(move(savedBuilder),move(savedData),copy(body)) : R { {
        var frame = new tuple<marker:int;builder:B -const -&;value:E -const -&>()
        static_if (typeinfo is_iterator(type<R>)) {
            var source:R
            try {
                ce_deferred_copy_builder(frame.builder,savedBuilder,default<P>)
                frame.value := savedData
                source <- invoke(body,frame)
            } recover {
                let message="{this_context().last_exception}"
                sequence_close(source)
                unsafe { delete frame }
                panic(message)
            }
            // The child closes before cleanup so its resource finalizers can
            // still access the snapshot. The pointer is moved into its owner.
            var cleanup <- @ capture(move(frame)) { unsafe { delete frame } }
            return <- ce_deferred_wrap_sequence(source,cleanup)
        } static_elif (typeinfo can_copy(type<R>)) {
            var result=default<R>
            try { ce_deferred_copy_builder(frame.builder,savedBuilder,default<P>); frame.value := savedData; result=invoke(body,frame) } recover {
                let message="{this_context().last_exception}"
                unsafe { delete frame }
                panic(message)
            }
            unsafe { delete frame }
            return result
        } else {
            var inscope result:R
            try { ce_deferred_copy_builder(frame.builder,savedBuilder,default<P>); frame.value := savedData; result <- invoke(body,frame) } recover {
                let message="{this_context().last_exception}"
                unsafe { delete frame }
                panic(message)
            }
            return <- ce_deferred_finish(result,frame,policy)
        }
    } } finally { ce_deferred_delete(savedData); ce_deferred_delete(savedBuilder) }
    return <- ce_deferred_hold(thunk)
}

def run_deferred(var task:tuple<kind:DeferredComputation;owner:iterator<lambda<():auto(R)>>>) : R {
    var body:lambda<():R>
    if (!next(task.owner,body)) { panic("deferred: computation has been moved or disposed") }
    static_if (typeinfo can_copy(type<R>)) { return invoke(body) }
    else { return <- invoke(body) }
}

// Keep the run snapshot alive behind a reference-yielding owning-slot iterator.
// Close the child (including its current element) before deleting the frame.
def private ce_deferred_reference_close(var state:tuple<source:iterator<auto(T)>;cleanup:lambda<():void>;closed:bool>) {
    if (state.closed) {return}
    state.closed=true
    ce_sequence_close_scope(state.source,state.cleanup)
}
def ce_deferred_reference_scope(var source:iterator<auto(T)&>; var cleanup:lambda<():void>) : iterator<T&> {
    var state <- (source <- source,cleanup <- cleanup,closed=false)
    return <- generator<T&> capture(<-state) {
        var slot:T -&?
        while (true) {
            var more=false
            var failed=false
            var message=""
            try {unsafe {more=_builtin_iterator_iterate(state.source,addr(slot))}} recover {
                message="{this_context().last_exception}"
                failed=true
            }
            if (failed) {
                ce_deferred_reference_close(state)
                panic(message)
            }
            if (!more) {ce_deferred_reference_close(state);break}
            unsafe {yield *slot}
        }
        return false
    } finally {ce_sequence_finalize($ {ce_deferred_reference_close(state)})}
}

def private ce_deferred_wrap_sequence(var source:iterator<auto(T)>; var cleanup:lambda<():void>) {
    static_if (typeinfo is_ref_value(type<T>)) {
        return <- ce_deferred_reference_scope(source,cleanup)
    } else {
        var scoped <- ce_sequence_scoped(source,cleanup)
        return <- ce_sequence_protect(scoped)
    }
}

// Preserve the existing low-level entry point for ordinary value builders.
def ce_deferred_create(builder:auto; data:auto; body:auto) {
    return <- ce_deferred_create(builder,data,body,CeDeferredValueBuilder())
}
