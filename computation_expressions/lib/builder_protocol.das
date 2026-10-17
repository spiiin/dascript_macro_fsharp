options gen2
module builder_protocol public
require ./computation_resources.das public
require daslib/rtti

// Nominal, compile-time protocol descriptors. ce_protocol is only type-inferred.
struct CeValueProtocol {}
struct CeCollectProtocol {}
struct CeSequenceProtocol {}
struct CeResumableProtocol {}
struct CeUnit {}

def ce_sequence_protocol(unused : type<auto(T)>) {
    return (strategy=CeSequenceProtocol(), element=default<T -const -&>)
}

def ce_resumable_protocol(unused:type<auto(T)>) {
    return (strategy=CeResumableProtocol(),element=default<T -const -&>)
}

// Default for copyable eager outcomes. Move-only builders override this.
def ce_delay(builder : auto; body : block<() : auto(R)>) : R { return invoke(body) }

// A shared, explicitly typed pair avoids carrying const/ref qualifiers in fields.
def ce_source_pair(first : auto(A); second : auto(B)) : tuple<first:A -const -&;second:B -const -&> {
    return (first=first, second=second)
}

// Release an owned source/result before rethrowing a native exception.
def ce_exception_message() : string {return "{this_context().last_exception}"}
def ce_owned_source_rethrow(var source : auto) {
    let message = "{this_context().last_exception}"
    delete source
    panic(message)
}




// Type-only fallback marker. The macro emits the original Bind/Return when
// no more specific overload exists; this function never runs in generated CE.
struct CeBindReturnFallback {}
def ce_bind_return(builder:auto; source:auto; mapper:auto) { return CeBindReturnFallback() }

def ce_bind2_return(builder:auto; left:auto; right:auto; mapper:auto) { return CeBindReturnFallback() }

// Optional grouped bind with a continuation returning the builder outcome.
def ce_bind2(builder:auto; left:auto; right:auto; next:auto) { return CeBindReturnFallback() }

// Compile-time defaults, removed by the macro before runtime.
struct CeMissingProtocol {}
struct CeMergeSourcesFallback {}
def ce_merge_sources(builder:auto; left,right:auto) { return CeMergeSourcesFallback() }
// Type-only diagnostic envelope, always removed by ce_checked_merge.
def ce_merge_origin(source:auto; builder:auto; location:string) {}
// A materialized resumable merge keeps its left type for diagnostic recovery.
def ce_merge_origin(source:auto; builder:auto; location:string; left:auto) {}
def ce_protocol(builder:auto) { return CeMissingProtocol() }
struct CeRunFallback {}
def ce_run(builder:auto; outcome:auto) { return CeRunFallback() }

// Optional eager loops. Marker overloads are only inspected at compile time.
struct CeLoopFallback {}
def ce_for(builder:auto; source:auto; body:auto) { return CeLoopFallback() }
def ce_while(builder:auto; condition:auto; body:auto) { return CeLoopFallback() }

// Used only under typedecl; never traverses the source at runtime.
def ce_for_element(source:auto) {
    for (value in source) { var item : typedecl(value) -const -&; return <- item }
}

def ce_for_element(var source:iterator<auto(T)>) {
    var item : T -const -&
    return <- item
}

// Preserve native for references when iterating arrays (type-only calls).
def ce_for_element(var source:array<auto(T)> ==const) : T& { unsafe { return source[0] } }
def ce_for_element(source:array<auto(T)> ==const) : T const& { unsafe { return source[0] } }
def ce_for_element(var source:auto(T)[] ==const) : T& { unsafe { return source[0] } }
def ce_for_element(source:auto(T)[] ==const) : T const& { unsafe { return source[0] } }

// Optional simultaneous For of any arity. traverse(visitor) retains native source
// evaluation and element references; visitor(body) returns whether to continue.
def ce_for_zip(builder:auto; arity:int; traverse:auto) { return CeLoopFallback() }

// Optional source conversion. The marker is erased without evaluating this call.
struct CeSourceFallback {}
def ce_source(builder:auto; source:auto) {return CeSourceFallback()}

// Eager outcomes with explicit ownership and consuming bind.
struct CeOwnedProtocol {}

// Opt-in linear bind/return collection fusion. Descriptor calls are type-only.
struct CeCollectSink {}
struct CeCollectSinkFallback {}
def ce_collect_sink(builder:auto) {return CeCollectSinkFallback()}

def ce_collect_sink_protocol(unused:type<auto(T)>) {
    var marker:T -const -&?
    return (kind=CeCollectSink(),element=marker)
}
