options gen2
module computation_builders public
require ./builder_protocol.das public
require daslib/rtti
require ./zip_runtime.das public

struct ResultBuilder {_ce_marker:uint8}
struct OptionBuilder {_ce_marker:uint8}

// Used in typedecl by the macro; it is not executed to obtain a bound value.
def ce_unwrap(builder : ResultBuilder; value : variant<ok : auto(T); error : string>) : T {
    return value as ok
}
def ce_unwrap(builder : OptionBuilder; value : variant<some : auto(T); none : bool>) : T {
    return value as some
}

def result_ok(value : auto(T)) : variant<ok : T -const -&; error : string> {
    return variant<ok : T -const -&; error : string>(ok=value)
}
def result_error(message : string; unused : type<auto(T)>) : variant<ok : T -const -&; error : string> {
    return variant<ok : T -const -&; error : string>(error=message)
}
def some(value : auto(T)) : variant<some : T -const -&; none : bool> {
    return variant<some : T -const -&; none : bool>(some=value)
}
def none(unused : type<auto(T)>) : variant<some : T -const -&; none : bool> {
    return variant<some : T -const -&; none : bool>(none=true)
}

def ce_return(builder : ResultBuilder; value : auto(T)) {
    return result_ok(value)
}
def ce_return(builder : OptionBuilder; value : auto(T)) {
    return some(value)
}

def ce_return_from(builder : ResultBuilder; value : variant<ok : auto(T); error : string>) {
    return value
}
def ce_return_from(builder : OptionBuilder; value : variant<some : auto(T); none : bool>) {
    return value
}

def ce_bind(builder : ResultBuilder; value : variant<ok : auto(T); error : string>;
            next : block<(item : T) : auto(R)>) : R {
    if (value is error) { return variant type<R>(error=value as error) }
    return invoke(next, value as ok)
}
def ce_bind(builder : OptionBuilder; value : variant<some : auto(T); none : bool>;
            next : block<(item : T) : auto(R)>) : R {
    if (value is none) { return variant type<R>(none=true) }
    return invoke(next, value as some)
}

// Unit is a successful computation with no useful payload (not None/Error).

def ce_zero(builder : ResultBuilder) { return variant<ok : CeUnit; error : string>(ok=CeUnit()) }
def ce_zero(builder : OptionBuilder) { return variant<some : CeUnit; none : bool>(some=CeUnit()) }

// Synchronous builders force the thunk here; no block escapes its stack frame.

def ce_combine(builder : ResultBuilder; first : variant<ok : CeUnit; error : string>;
               next : block<() : auto(R)>) : R {
    if (first is error) { return variant type<R>(error=first as error) }
    return ce_delay(builder, next)
}
def ce_combine(builder : OptionBuilder; first : variant<some : CeUnit; none : bool>;
               next : block<() : auto(R)>) : R {
    if (first is none) { return variant type<R>(none=true) }
    return ce_delay(builder, next)
}
// These signatures require each loop iteration to compute Unit.
def ce_loop_failed(builder : ResultBuilder; step : variant<ok : CeUnit; error : string>) : bool {
    return step is error
}
def ce_loop_failed(builder : OptionBuilder; step : variant<some : CeUnit; none : bool>) : bool {
    return step is none
}


// Fold loop effects. Result/Option keep their first failure; Writer appends logs.
def ce_loop_append(builder : ResultBuilder; first, step : variant<ok : CeUnit; error : string>) {
    if (first is error) { return first }
    return step
}
def ce_loop_append(builder : OptionBuilder; first, step : variant<some : CeUnit; none : bool>) {
    if (first is none) { return first }
    return step
}

def ce_protocol(builder : ResultBuilder) { return CeValueProtocol() }
def ce_protocol(builder : OptionBuilder) { return CeValueProtocol() }


def ce_merge_sources(builder : ResultBuilder; left : variant<ok:auto(A);error:string>;
                     right : variant<ok:auto(B);error:string>) : variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string> {
    if (left is error) { return variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(error=left as error) }
    if (right is error) { return variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(error=right as error) }
    return variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(ok=ce_source_pair(left as ok, right as ok))
}
def ce_merge_sources(builder : OptionBuilder; left : variant<some:auto(A);none:bool>;
                     right : variant<some:auto(B);none:bool>) : variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool> {
    if (left is none || right is none) { return variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool>(none=true) }
    return variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool>(some=ce_source_pair(left as some, right as some))
}

def ce_bind_return(builder : ResultBuilder; source : variant<ok:auto(T);error:string>;
                   mapper : block<(value:T):auto(U)>) : typedecl(ce_return(builder, default<U>)) {
    if (source is error) { return variant type<typedecl(ce_return(builder, default<U>))>(error=source as error) }
    return variant type<typedecl(ce_return(builder, default<U>))>(ok=invoke(mapper, source as ok))
}
def ce_bind_return(builder : OptionBuilder; source : variant<some:auto(T);none:bool>;
                   mapper : block<(value:T):auto(U)>) : typedecl(ce_return(builder, default<U>)) {
    if (source is none) { return variant type<typedecl(ce_return(builder, default<U>))>(none=true) }
    return variant type<typedecl(ce_return(builder, default<U>))>(some=invoke(mapper, source as some))
}


def ce_bind2_return(builder:ResultBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (left is error) { return variant type<typedecl(ce_return(builder,default<U>))>(error=left as error) }
    if (right is error) { return variant type<typedecl(ce_return(builder,default<U>))>(error=right as error) }
    return variant type<typedecl(ce_return(builder,default<U>))>(ok=invoke(mapper,ce_source_pair(left as ok,right as ok)))
}
def ce_bind2_return(builder:OptionBuilder; left:variant<some:auto(A);none:bool>; right:variant<some:auto(B);none:bool>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (left is none || right is none) { return variant type<typedecl(ce_return(builder,default<U>))>(none=true) }
    return variant type<typedecl(ce_return(builder,default<U>))>(some=invoke(mapper,ce_source_pair(left as some,right as some)))
}

// Grouped bind: the continuation already returns an outcome.
def ce_bind2(builder:ResultBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    if (left is error) { return variant type<R>(error=left as error) }
    if (right is error) { return variant type<R>(error=right as error) }
    return invoke(mapper,ce_source_pair(left as ok,right as ok))
}
def ce_bind2(builder:OptionBuilder; left:variant<some:auto(A);none:bool>; right:variant<some:auto(B);none:bool>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    if (left is none || right is none) { return variant type<R>(none=true) }
    return invoke(mapper,ce_source_pair(left as some,right as some))
}

// Shared implementation for the built-in eager, short-circuiting builders.
def private ce_for_values(builder:auto; source:auto; body:auto) {
    var result=ce_zero(builder)
    static_if ((typeinfo is_array(source)) || (typeinfo is_dim(source))) {
        static_if (typeinfo is_array(source)) { __builtin_array_lock_mutable(source) }
        try {
            for (index in range(length(source))) {
                result=ce_loop_append(builder,result,invoke(body,source[index]))
                if (ce_loop_failed(builder,result)) { break }
            }
        } recover {
            let message="{this_context().last_exception}"
            static_if (typeinfo is_array(source)) { __builtin_array_unlock_mutable(source) }
            panic(message)
        }
        static_if (typeinfo is_array(source)) { __builtin_array_unlock_mutable(source) }
    } else {
        for (value in source) {
            result=ce_loop_append(builder,result,invoke(body,value))
            if (ce_loop_failed(builder,result)) { return result }
        }
    }
    return result
}
def private ce_for_mutable_array(builder:auto; var source:auto; body:auto) {
    var result=ce_zero(builder)
    // Keep element references stable while still releasing the lock on panic.
    static_if (typeinfo is_array(source)) { __builtin_array_lock(source) }
    try {
        for (index in range(length(source))) {
            result=ce_loop_append(builder,result,invoke(body,source[index]))
            if (ce_loop_failed(builder,result)) { break }
        }
    } recover {
        let message="{this_context().last_exception}"
        static_if (typeinfo is_array(source)) { __builtin_array_unlock(source) }
        panic(message)
    }
    static_if (typeinfo is_array(source)) { __builtin_array_unlock(source) }
    return result
}
// Own the iterator explicitly: native for hides it from recover on panic.
def private ce_for_iterator(builder:auto; var source:iterator<auto(T)>; body:auto) {
    var cursor <- ce_zip_cursor(source)
    var result=ce_zero(builder)
    var message=""
    try {
        while (ce_zip_next(cursor)) {
            static_if (typeinfo is_ref_value(type<T>)) {
                unsafe {result=ce_loop_append(builder,result,invoke(body,*cursor.slot))}
            } else {
                result=ce_loop_append(builder,result,invoke(body,cursor.slot))
            }
            if (ce_loop_failed(builder,result)) {break}
        }
    } recover {message=ce_zip_exception()}
    ce_zip_close(cursor,message)
    if (!empty(message)) {panic(message)}
    return result
}

// The source expression runs once; a failed body stops before the next item.
def ce_for(builder:ResultBuilder; source:auto; body:auto) { return ce_for_values(builder,source,body) }
def ce_for(builder:ResultBuilder; var source:array<auto> ==const; body:auto) { return ce_for_mutable_array(builder,source,body) }
def ce_for(builder:ResultBuilder; var source:auto[] ==const; body:auto) { return ce_for_mutable_array(builder,source,body) }
def ce_for(builder:ResultBuilder; var source:iterator<auto>; body:auto) { return ce_for_iterator(builder,source,body) }

def ce_while(builder:ResultBuilder; condition:block<():bool>; body:block<():variant<ok:CeUnit;error:string>>) {
    var result=ce_zero(builder)
    while (invoke(condition)) {
        result=ce_loop_append(builder,result,invoke(body))
        if (ce_loop_failed(builder,result)) { return result }
    }
    return result
}

// The source expression runs once; a failed body stops before the next item.
def ce_for(builder:OptionBuilder; source:auto; body:auto) { return ce_for_values(builder,source,body) }
def ce_for(builder:OptionBuilder; var source:array<auto> ==const; body:auto) { return ce_for_mutable_array(builder,source,body) }
def ce_for(builder:OptionBuilder; var source:auto[] ==const; body:auto) { return ce_for_mutable_array(builder,source,body) }
def ce_for(builder:OptionBuilder; var source:iterator<auto>; body:auto) { return ce_for_iterator(builder,source,body) }

def ce_while(builder:OptionBuilder; condition:block<():bool>; body:block<():variant<some:CeUnit;none:bool>>) {
    var result=ce_zero(builder)
    while (invoke(condition)) {
        result=ce_loop_append(builder,result,invoke(body))
        if (ce_loop_failed(builder,result)) { return result }
    }
    return result
}

def ce_for_zip(builder:ResultBuilder; arity:int;
               traverse:block<(visit:block<(body:block<():variant<ok:CeUnit;error:string>>):bool>):void>) {
    var result=ce_zero(builder)
    invoke(traverse, $(body:block<():variant<ok:CeUnit;error:string>>) {
        result=invoke(body)
        return !ce_loop_failed(builder,result)
    })
    return result
}

def ce_for_zip(builder:OptionBuilder; arity:int;
               traverse:block<(visit:block<(body:block<():variant<some:CeUnit;none:bool>>):bool>):void>) {
    var result=ce_zero(builder)
    invoke(traverse, $(body:block<():variant<some:CeUnit;none:bool>>) {
        result=invoke(body)
        return !ce_loop_failed(builder,result)
    })
    return result
}
