options gen2
module state_writer_result_builder public
require ./computation_effects.das public

struct StateWriterResultContext {_ce_marker:uint8}
def ce_state_gets(builder:tuple<kind:StateWriterResultContext;initial:auto(S);state:S>; project:auto) {
    return ce_return(builder,invoke(project,builder.state))
}
// initial is the transaction boundary, shared by all scopes of one computation.
def StateWriterResultBuilder(initial : auto(TransactionState)) : tuple<kind : StateWriterResultContext; initial : TransactionState -const; state : TransactionState -const> {
    return (kind = StateWriterResultContext(), initial = initial, state = initial)
}
def state_writer_result_value(value : variant<ok : auto(T); error : string>; state : auto(TransactionState); log : string = "") {
    return (result = value, state = state, log = log)
}
def state_writer_result_ok(value : auto(T); state : auto(TransactionState); log : string = "") {
    return state_writer_result_value(result_ok(value), state, log)
}
def state_writer_result_error(message : string; unused : type<auto(T)>; state : auto(TransactionState); log : string = "") {
    return state_writer_result_value(result_error(message, type<T>), state, log)
}
def private swr_failure(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
                       message, log : string; unused : type<auto(R)>) : R {
    builder.state = builder.initial
    var failed = default<R>
    failed.result = variant type<typedecl(failed.result)>(error=message)
    failed.state = builder.initial
    failed.log = log
    return failed
}
def ce_unwrap(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>; op : StateGet) : TransactionState {
    return builder.state
}
def ce_unwrap(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
              op : tuple<operation : StatePut; state : TransactionState>) : CeUnit { return CeUnit() }
def ce_unwrap(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
              op : variant<ok : auto(T); error : string>) : T { return op as ok }
def ce_unwrap(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
              op : tuple<result : variant<ok : auto(T); error : string>; state : TransactionState; log : string>) : T { return op.result as ok }

def ce_bind(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>; op : StateGet;
            next : block<(item : TransactionState) : auto(R)>) : R {
    let snapshot = builder.state
    return invoke(next, snapshot)
}
def ce_bind(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
            op : tuple<operation : StatePut; state : TransactionState>; next : block<(item : CeUnit) : auto(R)>) : R {
    builder.state = op.state
    return invoke(next, CeUnit())
}
def ce_bind(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
            op : variant<ok : auto(T); error : string>; next : block<(item : T) : auto(R)>) : R {
    if (op is error) { return swr_failure(builder, op as error, "", type<R>) }
    return invoke(next, op as ok)
}
def ce_bind(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
            op : tuple<result : variant<ok : auto(T); error : string>; state : TransactionState; log : string>;
            next : block<(item : T) : auto(R)>) : R {
    if (op.result is error) { return swr_failure(builder, op.result as error, op.log, type<R>) }
    builder.state = op.state
    var rest = invoke(next, op.result as ok)
    rest.log = op.log + rest.log
    return rest
}
def ce_return(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>; value : auto(T)) {
    return state_writer_result_ok(value, builder.state)
}
def ce_zero(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>) {
    return state_writer_result_value(ce_zero(ResultBuilder()), builder.state)
}
def ce_return_from(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
                   value : variant<ok : auto(T); error : string>) {
    if (value is error) { builder.state = builder.initial }
    return state_writer_result_value(value, builder.state)
}
def ce_return_from(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
                   value : tuple<result : variant<ok : auto(T); error : string>; state : TransactionState; log : string>) {
    if (value.result is error) { builder.state = builder.initial }
    else { builder.state = value.state }
    return state_writer_result_value(value.result, builder.state, value.log)
}
def ce_combine(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
               first : tuple<result : variant<ok : CeUnit; error : string>; state : TransactionState; log : string>;
               next : block<() : auto(R)>) : R {
    if (first.result is error) { return swr_failure(builder, first.result as error, first.log, type<R>) }
    builder.state = first.state
    var rest = ce_delay(builder, next)
    rest.log = first.log + rest.log
    return rest
}
def ce_loop_failed(builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
                   value : tuple<result : variant<ok : CeUnit; error : string>; state : TransactionState; log : string>) : bool {
    return value.result is error
}
def ce_loop_append(var builder : tuple<kind : StateWriterResultContext; initial : auto(TransactionState); state : TransactionState>;
                   first, step : tuple<result : variant<ok : CeUnit; error : string>; state : TransactionState; log : string>) {
    if (first.result is error) { return swr_failure(builder, first.result as error, first.log, type<typedecl(first)>) }
    if (step.result is error) { return swr_failure(builder, step.result as error, first.log + step.log, type<typedecl(step)>) }
    builder.state = step.state
    return state_writer_result_value(step.result, builder.state, first.log + step.log)
}

def ce_protocol(builder : tuple<kind:StateWriterResultContext;initial:auto(TransactionState);state:TransactionState>) { return CeValueProtocol() }


// Lift Writer<Unit> (tell) without changing state.
def ce_unwrap(builder:tuple<kind:StateWriterResultContext;initial:auto(TransactionState);state:TransactionState>;
              op:tuple<value:CeUnit;log:string>) : CeUnit {return CeUnit()}
def ce_bind(var builder:tuple<kind:StateWriterResultContext;initial:auto(TransactionState);state:TransactionState>;
            op:tuple<value:CeUnit;log:string>; next:block<(item:CeUnit):auto(R)>) : R {
    var rest=invoke(next,CeUnit())
    rest.log=op.log+rest.log
    return rest
}
def ce_return_from(builder:tuple<kind:StateWriterResultContext;initial:auto(TransactionState);state:TransactionState>;
                   op:tuple<value:CeUnit;log:string>) {
    return state_writer_result_ok(CeUnit(),builder.state,op.log)
}

