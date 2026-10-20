options gen2
module reader_result_builder public
require ./computation_builders.das public
require ./reader_builder.das public

struct ReaderResultContext {_ce_marker:uint8}

// Eager reader: copyable environment and ordinary Result outcomes.
def ReaderResultBuilder(environment:auto(ReaderEnvironment)) {
    return (kind=ReaderResultContext(), environment=environment)
}

def ce_protocol(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>) { return CeValueProtocol() }

def ce_unwrap(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:ReaderAsk) : ReaderEnvironment {
    return builder.environment
}
def ce_unwrap(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:$Result<auto(T);string>) : T {
    return source as ok
}
def ce_bind(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:ReaderAsk;
            next:block<(item:ReaderEnvironment):auto(R)>) : R {
    return invoke(next,builder.environment)
}
def ce_bind(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:$Result<auto(T);string>;
            next:block<(item:T):auto(R)>) : R {
    return ce_bind(ResultBuilder(),source,next)
}
def ce_return(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; value:auto(T)) {
    return result_ok(value)
}
def ce_return_from(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; value:$Result<auto(T);string>) {
    return value
}
def ce_zero(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>) { return ce_zero(ResultBuilder()) }
def ce_combine(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; first:$Result<CeUnit;string>;
               next:block<():auto(R)>) : R {
    return ce_combine(ResultBuilder(),first,next)
}
// Default For/While lowering supplies traversal and resource protection.
def ce_loop_failed(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; step:$Result<CeUnit;string>) : bool {
    return step is err
}
def ce_loop_append(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; first,step:$Result<CeUnit;string>) {
    return ce_loop_append(ResultBuilder(),first,step)
}
def ce_bind_return(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:ReaderAsk;
                   mapper:block<(value:ReaderEnvironment):auto(U)>) {
    return result_ok(invoke(mapper,builder.environment))
}
def ce_bind_return(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:$Result<auto(T);string>;
                   mapper:block<(value:T):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    return ce_bind_return(ResultBuilder(),source,mapper)
}

def private rr_source(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:ReaderAsk) {
    return result_ok(builder.environment)
}
def private rr_source(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; source:$Result<auto(T);string>) {
    return source
}
def ce_merge_sources(builder:tuple<kind:ReaderResultContext;environment:auto(ReaderEnvironment)>; left,right:auto) {
    return ce_merge_sources(ResultBuilder(),rr_source(builder,left),rr_source(builder,right))
}

