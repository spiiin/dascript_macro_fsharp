options gen2
module derive_optics_runtime public
require ./derive_runtime.das public
require daslib/rtti

// These helpers return outside recover blocks (including owning CMRES results).
def optics_update_copy(source:auto(T);edit:block<(var value:T -const -&)>) : T -const -& {
    unsafe {
        var result:T -const -&
        try {
            static_if(typeinfo can_copy(result)) {result=_::derive_clone(source)}
            else {result <- _::derive_clone(source)}
            invoke(edit,result)
        } recover {
            let error="{this_context().last_exception}"
            static_if(typeinfo can_delete(result)) {delete result}
            panic(error)
        }
        static_if(typeinfo can_copy(result)) {return result} else {return <- result}
    }
}
def optics_update_owned(var source:auto(T);edit:block<(var value:T -const -&)>) : T -const -& {
    unsafe {
        var result:T -const -&
        static_if(typeinfo can_copy(result)) {result=source} else {result <- source}
        try {invoke(edit,result)} recover {
            let error="{this_context().last_exception}"
            static_if(typeinfo can_delete(result)) {delete result}
            panic(error)
        }
        static_if(typeinfo can_copy(result)) {return result} else {return <- result}
    }
}
def optics_get_owned(var source:auto(T);read:block<(value:T -const -&):auto(F)>) : F -const -& {
    unsafe {
        var result:F -const -&
        try {
            static_if(typeinfo can_copy(result)) {result=invoke(read,source)}
            else {result <- invoke(read,source)}
        } recover {
            let error="{this_context().last_exception}"
            static_if(typeinfo can_delete(source)) {delete source}
            static_if(typeinfo can_delete(result)) {delete result}
            panic(error)
        }
        static_if(typeinfo can_delete(source)) {delete source}
        static_if(typeinfo can_copy(result)) {return result} else {return <- result}
    }
}
def optics_assign_copy(var target:auto(T)&;value:T) {
    static_if(typeinfo can_copy(target)) {target=_::derive_clone(value)}
    else {
        var inscope replacement <- _::derive_clone(value)
        static_if(typeinfo can_delete(target)) {delete target}
        target <- replacement
    }
}
def optics_assign_owned(var target:auto(T)&;var value:T) {
    static_if(typeinfo can_copy(target)) {target=value}
    else {
        static_if(typeinfo can_delete(target)) {delete target}
        target <- value
    }
}
def optics_modify(var target:auto(T)&;transform:block<(value:T):auto(U)>) {
    static_assert(typeinfo typename(type<T -const -&>)==typeinfo typename(type<U -const -&>),"Optics: callback must return the focus type")
    static_if(typeinfo can_copy(type<U>)) {optics_assign_copy(target,invoke(transform,target))}
    else {
        var inscope replacement <- invoke(transform,target)
        optics_assign_owned(target,replacement)
    }
}

// Borrowing reader: unlike optics_get_owned this never closes its source.
def prism_read(source:auto(T);read:block<(value:T const):auto(F)>) : F -const -& {
    static_if(typeinfo can_copy(type<F>)) {return invoke(read,source)}
    else {return <- invoke(read,source)}
}

def prism_snapshot(value:auto(F)) : $Option<F -const -&> {
    unsafe {
        var payload:F -const -&
        var result=default<$Option<F -const -&>>
        try {
            static_if(typeinfo can_copy(payload)) {payload=_::derive_clone(value)}
            else {payload <- _::derive_clone(value)}
            result <- move_some(payload)
            // SDK AOT move_some does not clear all nested variant fields.
            memzero(payload)
        } recover {
            let error="{this_context().last_exception}"
            static_if(typeinfo can_delete(payload)) {delete payload}
            static_if(typeinfo can_delete(result)) {delete result}
            panic(error)
        }
        return <- result
    }
}
