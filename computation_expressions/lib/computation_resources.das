options gen2
module computation_resources public
require daslib/rtti

// Normal cleanup is outside try: a throwing cleanup is never invoked twice.
def ce_try_finally(builder : auto; body : block<() : auto(R)>; cleanup : block<() : void>) : R {
    var result : R
    try {
        result = invoke(body)
    } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup)
        panic(failure)
    }
    invoke(cleanup)
    return result
}
// Ownership is scoped here. The macro creates cleanup in the caller's module
// so that its ce_dispose overload is visible, without a global default disposer.
def ce_using(builder : auto; resource : auto(T); body : block<(item : T) : auto(R)>;
             cleanup : block<(var item : T) : void>) : R {
    var owned = resource
    var result : R
    try {
        result = invoke(body, owned)
    } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup, owned)
        panic(failure)
    }
    invoke(cleanup, owned)
    return result
}


// Error/None are values; only a native exception enters this handler.
def ce_try_with(builder : auto; body : block<() : auto(R)>;
                handler : block<(message:string) : R>) : R {
    var result : R
    var failed=false
    var message=""
    try { result = invoke(body) } recover {
        message = "{this_context().last_exception}"
        failed=true
    }
    // JIT 0.6.5-RC2 treats return in recover as leaving that arm, not the function.
    if(failed) {return invoke(handler, message)}
    return result
}

// Explicit owning use_resource: the continuation borrows the resource.
// ce_dispose owns cleanup, including any nested allocations in the resource.
def ce_using_move(builder:auto; var resource:auto(T); body:block<(var item:auto(U)):auto(R)>;
                  cleanup:block<(var item:T):void>) : R {
    var owned <- resource
    var result:R
    try {
        static_if (typeinfo can_copy(type<R>)) {result=invoke(body,owned)}
        else {result <- invoke(body,owned)}
    } recover {
        let message="{this_context().last_exception}"
        invoke(cleanup,owned)
        panic(message)
    }
    try {invoke(cleanup,owned)} recover {
        let message="{this_context().last_exception}"
        static_if (!typeinfo can_copy(type<R>) && typeinfo can_delete(type<R>)) {delete result}
        panic(message)
    }
    static_if (typeinfo can_copy(type<R>)) {return result}
    else {return <- result}
}

// Stable address for the body and cleanup generators; no owning value capture.
def ce_resource_cell_move(var resource:auto(T)) {
    return new tuple<value:T>(value <- resource)
}
def ce_resource_cell_close(var cell:tuple<value:auto(T)>?; cleanup:block<(var item:T):void>) {
    var owned <- cell.value
    // The cell now holds a moved-from resource; its real payload has one owner.
    unsafe {delete cell}
    invoke(cleanup,owned)
}
