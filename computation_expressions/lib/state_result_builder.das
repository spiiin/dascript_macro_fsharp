options gen2
module state_result_builder public
require ./computation_effects.das public

struct StateResultContext {_ce_marker:uint8}
def ce_state_gets(builder:tuple<kind:StateResultContext;initial:auto(S);state:S>; project:auto) {
    return ce_return(builder,invoke(project,builder.state))
}
// initial is the transaction boundary, shared by all scopes of one computation.
def StateResultBuilder(initial : auto(S)) : tuple<kind : StateResultContext; initial : S -const; state : S -const> {
    return (kind = StateResultContext(), initial = initial, state = initial)
}
def state_result_value(value : $Result<auto(T);string>; state : auto(S)) {
    return (result = value, state = state)
}
def state_result_ok(value : auto(T); state : auto(S)) {
    return state_result_value(result_ok(value), state)
}
def state_result_error(message : string; unused : type<auto(T)>; state : auto(S)) {
    return state_result_value(result_error(message, type<T>), state)
}
def private sr_failure(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
                       message : string; unused : type<auto(R)>) : R {
    builder.state = builder.initial
    var failed = default<R>
    failed.result = variant type<typedecl(failed.result)>(err=message)
    failed.state = builder.initial
    return failed
}
def ce_unwrap(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>; op : StateGet) : S {
    return builder.state
}
def ce_unwrap(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
              op : tuple<operation : StatePut; state : S>) : CeUnit { return CeUnit() }
def ce_unwrap(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
              op : $Result<auto(T);string>) : T { return op as ok }
def ce_unwrap(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
              op : tuple<result : $Result<auto(T);string>; state : S>) : T { return op.result as ok }

def ce_bind(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>; op : StateGet;
            next : block<(item : S) : auto(R)>) : R {
    let snapshot = builder.state
    return invoke(next, snapshot)
}
def ce_bind(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
            op : tuple<operation : StatePut; state : S>; next : block<(item : CeUnit) : auto(R)>) : R {
    builder.state = op.state
    return invoke(next, CeUnit())
}
def ce_bind(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
            op : $Result<auto(T);string>; next : block<(item : T) : auto(R)>) : R {
    if (op is err) { return sr_failure(builder, op as err, type<R>) }
    return invoke(next, op as ok)
}
def ce_bind(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
            op : tuple<result : $Result<auto(T);string>; state : S>;
            next : block<(item : T) : auto(R)>) : R {
    if (op.result is err) { return sr_failure(builder, op.result as err, type<R>) }
    builder.state = op.state
    return invoke(next, op.result as ok)
}
def ce_return(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>; value : auto(T)) {
    return state_result_ok(value, builder.state)
}
def ce_zero(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>) {
    return state_result_value(ce_zero(ResultBuilder()), builder.state)
}
def ce_return_from(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
                   value : $Result<auto(T);string>) {
    if (value is err) { builder.state = builder.initial }
    return state_result_value(value, builder.state)
}
def ce_return_from(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
                   value : tuple<result : $Result<auto(T);string>; state : S>) {
    if (value.result is err) { builder.state = builder.initial }
    else { builder.state = value.state }
    return state_result_value(value.result, builder.state)
}
def ce_combine(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
               first : tuple<result : $Result<CeUnit;string>; state : S>;
               next : block<() : auto(R)>) : R {
    if (first.result is err) { return sr_failure(builder, first.result as err, type<R>) }
    builder.state = first.state
    return ce_delay(builder, next)
}
def ce_loop_failed(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
                   value : tuple<result : $Result<CeUnit;string>; state : S>) : bool {
    return value.result is err
}
def ce_loop_append(var builder : tuple<kind : StateResultContext; initial : auto(S); state : S>;
                   first, step : tuple<result : $Result<CeUnit;string>; state : S>) {
    if (first.result is err) { return sr_failure(builder, first.result as err, type<typedecl(first)>) }
    if (step.result is err) { return sr_failure(builder, step.result as err, type<typedecl(step)>) }
    builder.state = step.state
    return step
}

def ce_protocol(builder : tuple<kind:StateResultContext;initial:auto(S);state:S>) { return CeValueProtocol() }

def ce_bind_return(var builder:tuple<kind:StateResultContext;initial:auto(S);state:S>; op:StateGet;
                   mapper:block<(value:S):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    let snapshot=builder.state
    let mapped=invoke(mapper,snapshot)
    return state_result_ok(mapped,builder.state)
}
def ce_bind_return(var builder:tuple<kind:StateResultContext;initial:auto(S);state:S>;
                   op:tuple<operation:StatePut;state:S>;
                   mapper:block<(value:CeUnit):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    builder.state=op.state
    let mapped=invoke(mapper,CeUnit())
    return state_result_ok(mapped,builder.state)
}
def ce_bind_return(var builder:tuple<kind:StateResultContext;initial:auto(S);state:S>;
                   op:$Result<auto(T);string>;
                   mapper:block<(value:T):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (op is err) { return sr_failure(builder,op as err,type<typedecl(ce_return(builder,default<U>))>) }
    let mapped=invoke(mapper,op as ok)
    return state_result_ok(mapped,builder.state)
}
def ce_bind_return(var builder:tuple<kind:StateResultContext;initial:auto(S);state:S>;
                   op:tuple<result:$Result<auto(T);string>;state:S>;
                   mapper:block<(value:T):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (op.result is err) { return sr_failure(builder,op.result as err,type<typedecl(ce_return(builder,default<U>))>) }
    builder.state=op.state
    let mapped=invoke(mapper,op.result as ok)
    return state_result_ok(mapped,builder.state)
}
