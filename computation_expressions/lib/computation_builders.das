options gen2
module computation_builders public
require ./builder_protocol.das public
require daslib/rtti
require ./zip_runtime.das public

struct ResultBuilder {_ce_marker:uint8}
struct OptionBuilder {_ce_marker:uint8}

// Used in typedecl by the macro; it is not executed to obtain a bound value.
def ce_unwrap(builder : ResultBuilder; value : $Result<auto(T);string>) : T {
    return value as ok
}
def ce_unwrap(builder : OptionBuilder; value : $Option<auto(T)>) : T {
    return value as some
}

def result_ok(value : auto(T)) : $Result<T -const -&;string> {
    return <- result::ok(value,type<string>)
}
def result_error(message : string; unused : type<auto(T)>) : $Result<T -const -&;string> {
    return <- result::err(message,type<T>)
}

def ce_return(builder : ResultBuilder; value : auto(T)) {
    return result_ok(value)
}
def ce_return(builder : OptionBuilder; value : auto(T)) {
    return some(value)
}

def ce_return_from(builder : ResultBuilder; value : $Result<auto(T);string>) {
    return value
}
def ce_return_from(builder : OptionBuilder; value : $Option<auto(T)>) {
    return value
}

def ce_bind(builder : ResultBuilder; value : $Result<auto(T);string>;
            next : block<(item : T) : auto(R)>) : R {
    if (value is err) { return variant type<R>(err=value as err) }
    return invoke(next, value as ok)
}
def ce_bind(builder : OptionBuilder; value : $Option<auto(T)>;
            next : block<(item : T) : auto(R)>) : R {
    if (value is none) { return default<R> }
    return invoke(next, value as some)
}

// Unit is a successful computation with no useful payload (not None/Error).

def ce_zero(builder : ResultBuilder) { return variant type<$Result<CeUnit;string>>(ok=CeUnit()) }
def ce_zero(builder : OptionBuilder) { return variant type<$Option<CeUnit>>(some=CeUnit()) }

// Synchronous builders force the thunk here; no block escapes its stack frame.

def ce_combine(builder : ResultBuilder; first : $Result<CeUnit;string>;
               next : block<() : auto(R)>) : R {
    if (first is err) { return variant type<R>(err=first as err) }
    return ce_delay(builder, next)
}
def ce_combine(builder : OptionBuilder; first : $Option<CeUnit>;
               next : block<() : auto(R)>) : R {
    if (first is none) { return default<R> }
    return ce_delay(builder, next)
}
// These signatures require each loop iteration to compute Unit.
def ce_loop_failed(builder : ResultBuilder; step : $Result<CeUnit;string>) : bool {
    return step is err
}
def ce_loop_failed(builder : OptionBuilder; step : $Option<CeUnit>) : bool {
    return step is none
}


// Fold loop effects. Result/Option keep their first failure; Writer appends logs.
def ce_loop_append(builder : ResultBuilder; first, step : $Result<CeUnit;string>) {
    if (first is err) { return first }
    return step
}
def ce_loop_append(builder : OptionBuilder; first, step : $Option<CeUnit>) {
    if (first is none) { return first }
    return step
}

def ce_protocol(builder : ResultBuilder) { return CeValueProtocol() }
def ce_protocol(builder : OptionBuilder) { return CeValueProtocol() }


def ce_merge_sources(builder : ResultBuilder; left : $Result<auto;string>;
                     right : $Result<auto;string>) {
    unsafe {
        if(left is err) {return typeinfo ce_canonical(variant type<$Result<typedecl(ce_source_pair(left as ok,right as ok));string>>(err=left as err))}
        if(right is err) {return typeinfo ce_canonical(variant type<$Result<typedecl(ce_source_pair(left as ok,right as ok));string>>(err=right as err))}
        return typeinfo ce_canonical(result_ok(ce_source_pair(left as ok,right as ok)))
    }
}
def ce_merge_sources(builder : OptionBuilder; left : $Option<auto>;
                     right : $Option<auto>) {
    unsafe {
        if(left is none || right is none) {return typeinfo ce_canonical(default<$Option<typedecl(ce_source_pair(left as some,right as some))>>)}
        return typeinfo ce_canonical(some(ce_source_pair(left as some,right as some)))
    }
}

def ce_bind_return(builder : ResultBuilder; source : $Result<auto(T);string>;
                   mapper : block<(value:T):auto(U)>) : typedecl(ce_return(builder, default<U>)) {
    if (source is err) { return variant type<typedecl(ce_return(builder, default<U>))>(err=source as err) }
    return variant type<typedecl(ce_return(builder, default<U>))>(ok=invoke(mapper, source as ok))
}
def ce_bind_return(builder : OptionBuilder; source : $Option<auto(T)>;
                   mapper : block<(value:T):auto(U)>) : typedecl(ce_return(builder, default<U>)) {
    if (source is none) { return default<typedecl(ce_return(builder, default<U>))> }
    return variant type<typedecl(ce_return(builder, default<U>))>(some=invoke(mapper, source as some))
}


def ce_bind2_return(builder:ResultBuilder; left:$Result<auto(A);string>; right:$Result<auto(B);string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (left is err) { return variant type<typedecl(ce_return(builder,default<U>))>(err=left as err) }
    if (right is err) { return variant type<typedecl(ce_return(builder,default<U>))>(err=right as err) }
    return variant type<typedecl(ce_return(builder,default<U>))>(ok=invoke(mapper,ce_source_pair(left as ok,right as ok)))
}
def ce_bind2_return(builder:OptionBuilder; left:$Option<auto(A)>; right:$Option<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (left is none || right is none) { return default<typedecl(ce_return(builder,default<U>))> }
    return variant type<typedecl(ce_return(builder,default<U>))>(some=invoke(mapper,ce_source_pair(left as some,right as some)))
}

// Grouped bind: the continuation already returns an outcome.
def ce_bind2(builder:ResultBuilder; left:$Result<auto(A);string>; right:$Result<auto(B);string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    if (left is err) { return variant type<R>(err=left as err) }
    if (right is err) { return variant type<R>(err=right as err) }
    return invoke(mapper,ce_source_pair(left as ok,right as ok))
}
def ce_bind2(builder:OptionBuilder; left:$Option<auto(A)>; right:$Option<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    if (left is none || right is none) { return default<R> }
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

def ce_while(builder:ResultBuilder; condition:block<():bool>; body:block<():$Result<CeUnit;string>>) {
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

def ce_while(builder:OptionBuilder; condition:block<():bool>; body:block<():$Option<CeUnit>>) {
    var result=ce_zero(builder)
    while (invoke(condition)) {
        result=ce_loop_append(builder,result,invoke(body))
        if (ce_loop_failed(builder,result)) { return result }
    }
    return result
}

def ce_for_zip(builder:ResultBuilder; arity:int;
               traverse:block<(visit:block<(body:block<():$Result<CeUnit;string>>):bool>):void>) {
    var result=ce_zero(builder)
    invoke(traverse, $(body:block<():$Result<CeUnit;string>>) {
        result=invoke(body)
        return !ce_loop_failed(builder,result)
    })
    return result
}

def ce_for_zip(builder:OptionBuilder; arity:int;
               traverse:block<(visit:block<(body:block<():$Option<CeUnit>>):bool>):void>) {
    var result=ce_zero(builder)
    invoke(traverse, $(body:block<():$Option<CeUnit>>) {
        result=invoke(body)
        return !ce_loop_failed(builder,result)
    })
    return result
}
