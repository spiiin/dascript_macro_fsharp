options gen2
module move_builders public
require ./computation_builders.das public
require daslib/rtti
// Consuming outcomes: bind owns the variant, continuation only borrows payload.
struct MoveResultBuilder {_ce_marker:uint8}
struct MoveOptionBuilder {_ce_marker:uint8}

def move_ok(var value:auto(T)) : $Result<T -const -&;string> {
    // SDK 0.6.5-RC2 AOT does not clear a tuple payload's source when it is
    // moved directly in a variant initializer. Enter ok with an empty payload,
    // then use a separate field move, preserving the standard Result layout.
    var vacant=default<T -const -&>
    var result <- result::move_ok(vacant,type<string>)
    result as ok <- value
    return <- result
}
def move_error(message:string; unused:type<auto(T)>) : $Result<T -const -&;string> {
    return <- variant type<$Result<T -const -&;string>>(err=message)
}
def ce_protocol(builder:MoveResultBuilder) {return CeOwnedProtocol()}
def ce_unwrap(builder:MoveResultBuilder; var source:$Result<auto(T);string>) : T& {unsafe {return source as ok}}
def ce_return(builder:MoveResultBuilder; value:auto(T)) : $Result<T -const -&;string> {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: use return <- value for a move-only payload")
    return <- variant type<$Result<T -const -&;string>>(ok=value)
}
def ce_return_move(builder:MoveResultBuilder; var value:auto(T)) : $Result<T;string> {return <- move_ok(value)}
def ce_return_from(builder:MoveResultBuilder; var source:$Result<auto(T);string>) {return <- source}
def ce_delay(builder:MoveResultBuilder; body:block<():auto(R)>) : R {return <- invoke(body)}
def ce_zero(builder:MoveResultBuilder) : $Result<CeUnit;string> {
    return <- variant type<$Result<CeUnit;string>>(ok=CeUnit())
}
// V preserves scalar references and native reference types (array/struct).
// invoke below checks compatibility with the actual payload T.
def ce_bind(builder:MoveResultBuilder; var source:$Result<auto(T);string>;
            next:block<(var value:auto(V)):auto(R)>) : R {
    var inscope owner <- source
    if (owner is err) {return <- variant type<R>(err=owner as err)}
    var inscope result:R
    try {result <- invoke(next,owner as ok)} recover {ce_owned_source_rethrow(owner)}
    return <- result
}
def ce_combine(builder:MoveResultBuilder; first:$Result<CeUnit;string>; next:block<():auto(R)>) : R {
    if (first is err) {return <- variant type<R>(err=first as err)}
    return <- invoke(next)
}
def ce_loop_failed(builder:MoveResultBuilder; result:$Result<CeUnit;string>) {return result is err}
def ce_collect_append(builder:MoveResultBuilder; var total:$Result<CeUnit;string>;
                      step:$Result<CeUnit;string>) {if (!(total is err)) {total=step}}
def ce_collect_rethrow(builder:MoveResultBuilder; var result:auto) {ce_owned_source_rethrow(result)}
def ce_merge_sources(builder:MoveResultBuilder; var left:$Result<auto;string>;
                     var right:$Result<auto;string>) {
    var inscope a <- left
    var inscope b <- right
    unsafe {
        if(a is err) {return <- typeinfo ce_canonical(move_error(a as err,type<tuple<first:typedecl(a as ok) -const -&;second:typedecl(b as ok) -const -&>>))}
        if(b is err) {return <- typeinfo ce_canonical(move_error(b as err,type<tuple<first:typedecl(a as ok) -const -&;second:typedecl(b as ok) -const -&>>))}
        var pair <- (first <- (a as ok),second <- (b as ok))
        return <- typeinfo ce_canonical(move_ok(pair))
    }
}

def move_none(unused:type<auto(T)>) : $Option<T -const -&> {
    return <- default<$Option<T -const -&>>
}
def ce_protocol(builder:MoveOptionBuilder) {return CeOwnedProtocol()}
def ce_unwrap(builder:MoveOptionBuilder; var source:$Option<auto(T)>) : T& {unsafe {return source as some}}
def ce_return(builder:MoveOptionBuilder; value:auto(T)) : $Option<T -const -&> {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: use return <- value for a move-only payload")
    return <- variant type<$Option<T -const -&>>(some=value)
}
def ce_return_move(builder:MoveOptionBuilder; var value:auto(T)) : $Option<T> {return <- ce_move_some(value)}
def ce_return_from(builder:MoveOptionBuilder; var source:$Option<auto(T)>) {return <- source}
def ce_delay(builder:MoveOptionBuilder; body:block<():auto(R)>) : R {return <- invoke(body)}
def ce_zero(builder:MoveOptionBuilder) : $Option<CeUnit> {
    return <- variant type<$Option<CeUnit>>(some=CeUnit())
}
def ce_bind(builder:MoveOptionBuilder; var source:$Option<auto(T)>;
            next:block<(var value:auto(V)):auto(R)>) : R {
    var inscope owner <- source
    if (owner is none) {return <- default<R>}
    var inscope result:R
    try {result <- invoke(next,owner as some)} recover {ce_owned_source_rethrow(owner)}
    return <- result
}
def ce_combine(builder:MoveOptionBuilder; first:$Option<CeUnit>; next:block<():auto(R)>) : R {
    if (first is none) {return <- default<R>}
    return <- invoke(next)
}
def ce_loop_failed(builder:MoveOptionBuilder; result:$Option<CeUnit>) {return result is none}
def ce_collect_append(builder:MoveOptionBuilder; var total:$Option<CeUnit>;
                      step:$Option<CeUnit>) {if (!(total is none)) {total=step}}
def ce_collect_rethrow(builder:MoveOptionBuilder; var result:auto) {ce_owned_source_rethrow(result)}
def ce_merge_sources(builder:MoveOptionBuilder; var left:$Option<auto>;
                     var right:$Option<auto>) {
    var inscope a <- left
    var inscope b <- right
    unsafe {
        if(a is none || b is none) {return <- typeinfo ce_canonical(default<$Option<tuple<first:typedecl(a as some) -const -&;second:typedecl(b as some) -const -&>>>)}
        var pair <- (first <- (a as some),second <- (b as some))
        return <- typeinfo ce_canonical(ce_move_some(pair))
    }
}

def ce_try_with(builder:MoveResultBuilder; body:block<():auto(R)>; handler:block<(message:string):R>) : R {
    var inscope result:R
    var failed=false
    var message=""
    try {result <- invoke(body)} recover {
        message="{this_context().last_exception}"
        failed=true
    }
    if(failed) {return <- invoke(handler,message)}
    return <- result
}
def ce_try_finally(builder:MoveResultBuilder; body:block<():auto(R)>; cleanup:block<():void>) : R {
    var inscope result:R
    try {result <- invoke(body)} recover {
        let message="{this_context().last_exception}"
        invoke(cleanup)
        panic(message)
    }
    try {invoke(cleanup)} recover {ce_owned_source_rethrow(result)}
    return <- result
}
def ce_using(builder:MoveResultBuilder; resource:auto(T); body:block<(item:T):auto(R)>;
             cleanup:block<(var item:T):void>) : R {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: move-only payloads use bind; use_resource needs a copyable handle")
    var owner=resource
    var inscope result:R
    try {result <- invoke(body,owner)} recover {
        let message="{this_context().last_exception}"
        invoke(cleanup,owner)
        panic(message)
    }
    try {invoke(cleanup,owner)} recover {ce_owned_source_rethrow(result)}
    return <- result
}

def ce_try_with(builder:MoveOptionBuilder; body:block<():auto(R)>; handler:block<(message:string):R>) : R {
    var inscope result:R
    var failed=false
    var message=""
    try {result <- invoke(body)} recover {
        message="{this_context().last_exception}"
        failed=true
    }
    if(failed) {return <- invoke(handler,message)}
    return <- result
}
def ce_try_finally(builder:MoveOptionBuilder; body:block<():auto(R)>; cleanup:block<():void>) : R {
    var inscope result:R
    try {result <- invoke(body)} recover {
        let message="{this_context().last_exception}"
        invoke(cleanup)
        panic(message)
    }
    try {invoke(cleanup)} recover {ce_owned_source_rethrow(result)}
    return <- result
}
def ce_using(builder:MoveOptionBuilder; resource:auto(T); body:block<(item:T):auto(R)>;
             cleanup:block<(var item:T):void>) : R {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: move-only payloads use bind; use_resource needs a copyable handle")
    var owner=resource
    var inscope result:R
    try {result <- invoke(body,owner)} recover {
        let message="{this_context().last_exception}"
        invoke(cleanup,owner)
        panic(message)
    }
    try {invoke(cleanup,owner)} recover {ce_owned_source_rethrow(result)}
    return <- result
}

