options gen2
module zip_runtime public
require ./sequence_runtime.das public
require daslib/rtti

struct CeZipReadOnly {}
struct CeZipMutable {}

// Reference iterators write an address, value iterators write the value itself.
def private ce_zip_pack(var source:iterator<auto(T)>; mode:auto) {
    static_if (typeinfo is_ref_value(type<T>)) {
        var value:T -&?
        return <- (stream <- source, slot=value, mode=mode)
    } else {
        concept_assert(typeinfo can_copy(type<T>), "zip: value iterator elements must be copyable")
        var value:T
        return <- (stream <- source, slot=value, mode=mode)
    }
}
def ce_zip_cursor(var source:iterator<auto>) { return <- ce_zip_pack(source,CeZipMutable()) }
def ce_zip_cursor(source:auto ==const) {
    unsafe {
        var stream <- each(source)
        return <- ce_zip_pack(stream,CeZipReadOnly())
    }
}
def ce_zip_cursor(var source:auto ==const) {
    unsafe {
        var stream <- each(source)
        return <- ce_zip_pack(stream,CeZipMutable())
    }
}
def ce_zip_next(var cursor:tuple<stream:iterator<auto(T)>;slot:auto;mode:auto>) : bool {
    unsafe {return _builtin_iterator_iterate(cursor.stream,addr(cursor.slot))}
}
// Always attempt every close; preserve the original producer/consumer exception.
def ce_zip_close(var cursor:tuple<stream:iterator<auto>;slot:auto;mode:auto>; var message:string&) {
    try { sequence_close(cursor.stream) } recover {
        if (empty(message)) {message="{this_context().last_exception}"}
    }
}

def ce_zip_exception() : string {return "{this_context().last_exception}"}

// Protect an iterator used as a nested Sequence source, preserving ref elements.
def ce_sequence_input(var source:iterator<auto(T)>) : iterator<T> {
    var cursor <- ce_zip_cursor(source)
    return <- generator<T> capture(<-cursor) {
        while (true) {
            var more=false
            var failed=false
            var message=""
            try {more=ce_zip_next(cursor)} recover {message=ce_zip_exception();failed=true}
            if (failed) {
                ce_zip_close(cursor,message)
                panic(message)
            }
            if (!more) {break}
            static_if (typeinfo is_ref_value(type<T>)) {
                unsafe {yield *cursor.slot}
            } else {yield cursor.slot}
        }
        return false
    } finally {
        ce_sequence_finalize($ {
            var message=""
            ce_zip_close(cursor,message)
            if (!empty(message)) {panic(message)}
        })
    }
}
