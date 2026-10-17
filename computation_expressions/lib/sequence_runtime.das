options gen2
module sequence_runtime public
require ./builder_protocol.das public
require daslib/rtti

// LambdaIterator::close saves/restores the caller's stop flags but does not
// clear them before running the finalizer (0.6.4). Enter recover to clear the
// inherited break/return flag before invoking arbitrary multi-statement code.
def ce_sequence_finalize(action : block<() : void>) {
    try { panic("__ce_sequence_finalize_entry") } recover { invoke(action) }
}

// No yield is enclosed by try/recover: native generators cannot resume into it.
def ce_sequence_protect(var source : iterator<auto(T)>) : iterator<T> {
    return <- generator<T> capture(<- source) {
        var value : T
        while (true) {
            var more = false
            try { more = ce_sequence_next_value(source, value) } recover {
                let message = "{this_context().last_exception}"
                sequence_close(source)
                panic(message)
            }
            if (!more) { break }
            static_if(typeinfo can_copy(type<T>)) {yield value}
            else {yield <- value}
        }
        return false
    } finally { ce_sequence_finalize($ { sequence_close(source) }) }
}

// Native for does not close an iterator when its consumer throws. This helper
// owns traversal and closes the iterator on consumer as well as producer errors.
def sequence_each(var source : iterator<auto(T)>; action : block<(value:auto(V)) : void>) {
    static_if (typeinfo is_ref_value(type<T>)) {
        var slot:T -&?
        try {
            while (true) {
                var more=false
                unsafe {more=_builtin_iterator_iterate(source,addr(slot))}
                if (!more) {break}
                unsafe {invoke(action,*slot)}
            }
            sequence_close(source)
        } recover {
            let message="{this_context().last_exception}"
            sequence_close(source)
            panic(message)
        }
    } else {
        var value:T
        try {
            while (ce_sequence_next_value(source,value)) {
                invoke(action,value)
                static_if (!typeinfo can_copy(type<T>)) {delete value}
            }
            sequence_close(source)
        } recover {
            let message="{this_context().last_exception}"
            static_if (!typeinfo can_copy(type<T>)) {delete value}
            sequence_close(source)
            panic(message)
        }
    }
}


def ce_sequence_close_scope(var source : iterator<auto(T)>; var cleanup : lambda<() : void>) {
    var message = ""
    try { sequence_close(source) } recover { message = "{this_context().last_exception}" }
    try { invoke(cleanup) } recover { message = "{this_context().last_exception}" }
    unsafe { delete cleanup }
    if (!empty(message)) { panic(message) }
}

def ce_sequence_scoped(var source : iterator<auto(T)>; var cleanup : lambda<() : void>) : iterator<T> {
    return <- generator<T> capture(<-source, <-cleanup) {
        var value : T
        while (ce_sequence_next_value(source, value)) {
            static_if (typeinfo can_copy(type<T>)) {yield value}
            else {yield <- value}
        }
        return false
    } finally {
        ce_sequence_finalize($ { ce_sequence_close_scope(source, cleanup) })
    }
}



// Detach before finalization so a throwing cleanup cannot cause a retry.
def sequence_close(var source : iterator<auto(T)>) {
    var owned <- source
    unsafe { delete owned }
}

// A copyable descriptor with one mutable payload, owned by the lexical CE scope.
struct CeSequenceCellTag {_ce_marker:uint8}
def ce_sequence_new_cell(value : auto(T)) {
    return new tuple<tag:CeSequenceCellTag;value:T -const -&>(tag=CeSequenceCellTag(), value=value)
}
def ce_dispose(var cell : tuple<tag:CeSequenceCellTag;value:auto(T)>?) {
    unsafe { delete cell }
}


// No yield occurs inside try. Recovery switches the iterator exactly once.
def ce_sequence_recover(var source : iterator<auto(T)>;
                        var handler : lambda<(message:string) : iterator<T>>) : iterator<T> {
    return <- generator<T> capture(<-source, <-handler) {
        var recovered=false
        var value:T
        while (true) {
            var more=false
            var failed=false
            var message=""
            try {
                more=ce_sequence_next_value(source,value)
                if (!more) { sequence_close(source) }
            } recover {
                message="{this_context().last_exception}"
                failed=true
            }
            if (failed) {
                try { sequence_close(source) } recover { message="{this_context().last_exception}" }
                if (recovered) { panic(message) }
                recovered=true
                source <- invoke(handler,message)
            } else {
                if (!more) {break}
                static_if (typeinfo can_copy(type<T>)) {yield value}
                else {yield <- value}
            }
        }
        return false
    } finally { ce_sequence_finalize($ { ce_sequence_close_recovery(source,handler) }) }
}
def ce_sequence_close_recovery(var source : iterator<auto(T)>;
                               var handler : lambda<(message:string) : iterator<T>>) {
    var message=""
    try {sequence_close(source)} recover {message="{this_context().last_exception}"}
    unsafe {delete handler}
    if (!empty(message)) {panic(message)}
}


// A value generator writes into our owned slot. Public iteration borrows that
// slot until next/close; native for cannot own or clean a move-only value slot.
def ce_sequence_own_elements(var source:iterator<auto(T)>) : iterator<T&> {
    var slot:T
    return <- generator<T&> capture(<-source, <-slot) {
        while (true) {
            delete slot
            var more=false
            try {more=ce_sequence_next_value(source,slot)} recover {
                let message="{this_context().last_exception}"
                sequence_close(source)
                delete slot
                panic(message)
            }
            if (!more) {break}
            yield slot
        }
        return false
    } finally {
        ce_sequence_finalize($ {
            // Clear the owned payload even if a child finalizer throws.
            delete slot
            sequence_close(source)
        })
    }
}
// Mutable borrow for consumers that explicitly move a yielded item elsewhere.
// Also closes on consumer exceptions, unlike native for outside a CE.
def sequence_each_move(var source:iterator<auto(T)&>; action:block<(var value:auto(V)):void>) {
    var slot:T -&?
    try {
        while (true) {
            var more=false
            unsafe {more=_builtin_iterator_iterate(source,addr(slot))}
            if (!more) {break}
            unsafe {invoke(action,*slot)}
        }
        sequence_close(source)
    } recover {
        let message="{this_context().last_exception}"
        sequence_close(source)
        panic(message)
    }
}

// Called only with value slots; ownership is held by the caller.
def ce_sequence_next_value(var source:iterator<auto(T)>; var slot:T&) : bool {
    concept_assert(!typeinfo is_ref_value(type<T>),"sequence: a value slot cannot receive a reference iterator")
    unsafe {return _builtin_iterator_iterate(source,addr(slot))}
}

// Pull one owning element. Exhaustion/error preserves the last delivered value.
// Reference iterators lend their current slot; value iterators fill a temporary.
def sequence_next_move(var source:iterator<auto(T)>; var value:T -&) : bool {
    static_if (typeinfo can_copy(type<T -&>)) {
        concept_assert(false,"sequence_next_move requires a move-only element; use next for copyable values")
        return false
    } static_elif (typeinfo is_ref_value(type<T>)) {
        var slot:T -&?
        var more=false
        try {unsafe {more=_builtin_iterator_iterate(source,addr(slot))}} recover {
            let message="{this_context().last_exception}"
            sequence_close(source)
            panic(message)
        }
        if (!more) {sequence_close(source);return false}
        delete value
        unsafe {value <- *slot}
    } else {
        var inscope incoming:T
        var more=false
        try {more=ce_sequence_next_value(source,incoming)} recover {
            let message="{this_context().last_exception}"
            delete incoming
            sequence_close(source)
            panic(message)
        }
        if (!more) {sequence_close(source);return false}
        delete value
        value <- incoming
    }
    return true
}
