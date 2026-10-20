options gen2
module writer_result_builder public
require ./computation_effects.das public

struct WriterResultBuilder {_ce_marker:uint8}

def writer_result(value : $Result<auto(T);string>; log : string = "") {
    return (result = value, log = log)
}
def writer_result_ok(value : auto(T); log : string = "") {
    return writer_result(result_ok(value), log)
}
def writer_result_error(message : string; unused : type<auto(T)>; log : string = "") {
    return writer_result(result_error(message, type<T>), log)
}
// Re-type only the absent success payload, preserving both error and log.
def private wr_failure(message, log : string; unused : type<auto(R)>) : R {
    var failed = default<R>
    failed.result = variant type<typedecl(failed.result)>(err=message)
    failed.log = log
    return failed
}

def ce_unwrap(builder : WriterResultBuilder;
              value : tuple<result : $Result<auto(T);string>; log : string>) : T {
    return value.result as ok
}
def ce_unwrap(builder : WriterResultBuilder; value : $Result<auto(T);string>) : T {
    return value as ok
}
// Lift tell (Writer<Unit>) only; arbitrary Writer payloads require explicit conversion.
def ce_unwrap(builder : WriterResultBuilder; value : tuple<value : CeUnit; log : string>) : CeUnit {
    return CeUnit()
}
def ce_bind(builder : WriterResultBuilder;
            value : tuple<result : $Result<auto(T);string>; log : string>;
            next : block<(item : T) : auto(R)>) : R {
    if (value.result is err) {
        return wr_failure(value.result as err, value.log, type<R>)
    }
    var rest = invoke(next, value.result as ok)
    rest.log = value.log + rest.log
    return rest
}
def ce_bind(builder : WriterResultBuilder; value : $Result<auto(T);string>;
            next : block<(item : T) : auto(R)>) : R {
    return ce_bind(builder, writer_result(value), next)
}
def ce_bind(builder : WriterResultBuilder; value : tuple<value : CeUnit; log : string>;
            next : block<(item : CeUnit) : auto(R)>) : R {
    return ce_bind(builder, writer_result(ce_zero(ResultBuilder()), value.log), next)
}
def ce_return(builder : WriterResultBuilder; value : auto(T)) {
    return writer_result_ok(value)
}
def ce_zero(builder : WriterResultBuilder) {
    return writer_result(ce_zero(ResultBuilder()))
}
def ce_return_from(builder : WriterResultBuilder;
                   value : tuple<result : $Result<auto(T);string>; log : string>) {
    return value
}
def ce_return_from(builder : WriterResultBuilder; value : $Result<auto(T);string>) {
    return writer_result(value)
}
def ce_return_from(builder : WriterResultBuilder; value : tuple<value : CeUnit; log : string>) {
    return writer_result(ce_zero(ResultBuilder()), value.log)
}
def ce_combine(builder : WriterResultBuilder;
               first : tuple<result : $Result<CeUnit;string>; log : string>;
               next : block<() : auto(R)>) : R {
    if (first.result is err) {
        return wr_failure(first.result as err, first.log, type<R>)
    }
    var rest = ce_delay(builder, next)
    rest.log = first.log + rest.log
    return rest
}
def ce_loop_failed(builder : WriterResultBuilder;
                   step : tuple<result : $Result<CeUnit;string>; log : string>) : bool {
    return step.result is err
}
def ce_loop_append(builder : WriterResultBuilder;
                   first, step : tuple<result : $Result<CeUnit;string>; log : string>) {
    if (first.result is err) { return first }
    return writer_result(step.result, first.log + step.log)
}

def ce_protocol(builder : WriterResultBuilder) { return CeValueProtocol() }

def ce_bind_return(builder:WriterResultBuilder;
                   source:tuple<result:$Result<auto(T);string>;log:string>;
                   mapper:block<(value:T):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (source.result is err) {
        return wr_failure(source.result as err,source.log,type<typedecl(ce_return(builder,default<U>))>)
    }
    let mapped=invoke(mapper,source.result as ok)
    return writer_result_ok(mapped,source.log)
}
def ce_bind_return(builder:WriterResultBuilder; source:$Result<auto(T);string>;
                   mapper:block<(value:T):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (source is err) { return wr_failure(source as err,"",type<typedecl(ce_return(builder,default<U>))>) }
    let mapped=invoke(mapper,source as ok)
    return writer_result_ok(mapped)
}
def ce_bind_return(builder:WriterResultBuilder; source:tuple<value:CeUnit;log:string>;
                   mapper:block<(value:CeUnit):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    let mapped=invoke(mapper,CeUnit())
    return writer_result_ok(mapped,source.log)
}
