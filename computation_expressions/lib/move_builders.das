options gen2
module move_builders public
require ./computation_builders.das public
require daslib/rtti
// Consuming outcomes: bind owns the variant, continuation only borrows payload.
struct MoveResultBuilder {_ce_marker:uint8}
struct MoveOptionBuilder {_ce_marker:uint8}

def move_ok(var value:auto(T)) : variant<ok:T -const -&;error:string> {
    // 0.6.4 AOT emits a shallow copy for a variant field initializer with <-.
    // A separate assignment emits das_move and clears the original owner.
    var result:variant<ok:T -const -&;error:string>
    result as ok <- value
    return <- result
}
def move_error(message:string; unused:type<auto(T)>) : variant<ok:T -const -&;error:string> {
    return <- variant<ok:T -const -&;error:string>(error=message)
}
def ce_protocol(builder:MoveResultBuilder) {return CeOwnedProtocol()}
def ce_unwrap(builder:MoveResultBuilder; var source:variant<ok:auto(T);error:string>) : T& {unsafe {return source as ok}}
def ce_return(builder:MoveResultBuilder; value:auto(T)) : variant<ok:T -const -&;error:string> {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: use return <- value for a move-only payload")
    return <- variant<ok:T -const -&;error:string>(ok=value)
}
def ce_return_move(builder:MoveResultBuilder; var value:auto(T)) : variant<ok:T;error:string> {return <- move_ok(value)}
def ce_return_from(builder:MoveResultBuilder; var source:variant<ok:auto(T);error:string>) {return <- source}
def ce_delay(builder:MoveResultBuilder; body:block<():auto(R)>) : R {return <- invoke(body)}
def ce_zero(builder:MoveResultBuilder) : variant<ok:CeUnit;error:string> {
    return <- variant<ok:CeUnit;error:string>(ok=CeUnit())
}
// V preserves scalar references and native reference types (array/struct).
// invoke below checks compatibility with the actual payload T.
def ce_bind(builder:MoveResultBuilder; var source:variant<ok:auto(T);error:string>;
            next:block<(var value:auto(V)):auto(R)>) : R {
    var inscope owner <- source
    if (owner is error) {return <- variant type<R>(error=owner as error)}
    var inscope result:R
    try {result <- invoke(next,owner as ok)} recover {ce_owned_source_rethrow(owner)}
    return <- result
}
def ce_combine(builder:MoveResultBuilder; first:variant<ok:CeUnit;error:string>; next:block<():auto(R)>) : R {
    if (first is error) {return <- variant type<R>(error=first as error)}
    return <- invoke(next)
}
def ce_loop_failed(builder:MoveResultBuilder; result:variant<ok:CeUnit;error:string>) {return result is error}
def ce_collect_append(builder:MoveResultBuilder; var total:variant<ok:CeUnit;error:string>;
                      step:variant<ok:CeUnit;error:string>) {if (!(total is error)) {total=step}}
def ce_collect_rethrow(builder:MoveResultBuilder; var result:auto) {ce_owned_source_rethrow(result)}
def ce_merge_sources(builder:MoveResultBuilder; var left:variant<ok:auto(A);error:string>;
                     var right:variant<ok:auto(B);error:string>) {
    var inscope a <- left
    var inscope b <- right
    if (a is error) {return <- variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(error=a as error)}
    if (b is error) {return <- variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(error=b as error)}
    return <- variant<ok:tuple<first:A -const -&;second:B -const -&>;error:string>(ok <- (first <- (a as ok),second <- (b as ok)))
}

def move_some(var value:auto(T)) : variant<some:T;none:bool> {
    return <- variant<some:T;none:bool>(some <- value)
}
def move_none(unused:type<auto(T)>) : variant<some:T -const -&;none:bool> {
    return <- variant<some:T -const -&;none:bool>(none=true)
}
def ce_protocol(builder:MoveOptionBuilder) {return CeOwnedProtocol()}
def ce_unwrap(builder:MoveOptionBuilder; var source:variant<some:auto(T);none:bool>) : T& {unsafe {return source as some}}
def ce_return(builder:MoveOptionBuilder; value:auto(T)) : variant<some:T -const -&;none:bool> {
    concept_assert(typeinfo can_copy(type<T>),"owned CE: use return <- value for a move-only payload")
    return <- variant<some:T -const -&;none:bool>(some=value)
}
def ce_return_move(builder:MoveOptionBuilder; var value:auto(T)) : variant<some:T;none:bool> {return <- move_some(value)}
def ce_return_from(builder:MoveOptionBuilder; var source:variant<some:auto(T);none:bool>) {return <- source}
def ce_delay(builder:MoveOptionBuilder; body:block<():auto(R)>) : R {return <- invoke(body)}
def ce_zero(builder:MoveOptionBuilder) : variant<some:CeUnit;none:bool> {
    return <- variant<some:CeUnit;none:bool>(some=CeUnit())
}
def ce_bind(builder:MoveOptionBuilder; var source:variant<some:auto(T);none:bool>;
            next:block<(var value:auto(V)):auto(R)>) : R {
    var inscope owner <- source
    if (owner is none) {return <- variant type<R>(none=true)}
    var inscope result:R
    try {result <- invoke(next,owner as some)} recover {ce_owned_source_rethrow(owner)}
    return <- result
}
def ce_combine(builder:MoveOptionBuilder; first:variant<some:CeUnit;none:bool>; next:block<():auto(R)>) : R {
    if (first is none) {return <- variant type<R>(none=true)}
    return <- invoke(next)
}
def ce_loop_failed(builder:MoveOptionBuilder; result:variant<some:CeUnit;none:bool>) {return result is none}
def ce_collect_append(builder:MoveOptionBuilder; var total:variant<some:CeUnit;none:bool>;
                      step:variant<some:CeUnit;none:bool>) {if (!(total is none)) {total=step}}
def ce_collect_rethrow(builder:MoveOptionBuilder; var result:auto) {ce_owned_source_rethrow(result)}
def ce_merge_sources(builder:MoveOptionBuilder; var left:variant<some:auto(A);none:bool>;
                     var right:variant<some:auto(B);none:bool>) {
    var inscope a <- left
    var inscope b <- right
    if (a is none) {return <- variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool>(none=true)}
    if (b is none) {return <- variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool>(none=true)}
    return <- variant<some:tuple<first:A -const -&;second:B -const -&>;none:bool>(some <- (first <- (a as some),second <- (b as some)))
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

