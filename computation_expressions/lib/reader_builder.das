options gen2
module reader_builder public
require ./builder_protocol.das public

struct ReaderContext {_ce_marker:uint8}
struct ReaderAsk {_ce_marker:uint8}
def ReaderBuilder(environment : auto(E)) { return (kind=ReaderContext(), environment=environment) }
def reader_ask() { return ReaderAsk() }
def reader_value(value : auto(T)) { return (value=value) }
def ce_protocol(builder : tuple<kind:ReaderContext;environment:auto(E)>) { return CeValueProtocol() }
def ce_unwrap(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : ReaderAsk) : E { return builder.environment }
def ce_unwrap(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : tuple<value:auto(T)>) : T { return source.value }
def ce_bind(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : ReaderAsk;
            next : block<(item:E):auto(R)>) : R { return invoke(next, builder.environment) }
def ce_bind(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : tuple<value:auto(T)>;
            next : block<(item:T):auto(R)>) : R { return invoke(next, source.value) }
def ce_return(builder : tuple<kind:ReaderContext;environment:auto(E)>; value : auto(T)) { return reader_value(value) }
def ce_return_from(builder : tuple<kind:ReaderContext;environment:auto(E)>; value : tuple<value:auto(T)>) { return value }
def ce_zero(builder : tuple<kind:ReaderContext;environment:auto(E)>) { return reader_value(CeUnit()) }
def ce_combine(builder : tuple<kind:ReaderContext;environment:auto(E)>; first : tuple<value:CeUnit>;
               next : block<():auto(R)>) : R { return invoke(next) }
def ce_loop_failed(builder : tuple<kind:ReaderContext;environment:auto(E)>; step : tuple<value:CeUnit>) : bool { return false }
def ce_loop_append(builder : tuple<kind:ReaderContext;environment:auto(E)>; first, step : tuple<value:CeUnit>) { return step }

def ce_bind_return(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : ReaderAsk;
                   mapper : block<(value:E):auto(U)>) { return reader_value(invoke(mapper, builder.environment)) }
def ce_bind_return(builder : tuple<kind:ReaderContext;environment:auto(E)>; source : tuple<value:auto(T)>;
                   mapper : block<(value:T):auto(U)>) { return reader_value(invoke(mapper, source.value)) }
