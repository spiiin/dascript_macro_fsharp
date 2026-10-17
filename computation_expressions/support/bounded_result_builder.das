options gen2
module bounded_result_builder public
require ../lib/computation_builders.das public

// A separate module: the macro knows neither this type nor its loop policy.
// The budget applies independently to each loop, including nested loops.
struct BoundedResultBuilder { limit:int = 100 }
def ce_protocol(builder:BoundedResultBuilder) { return CeValueProtocol() }
def ce_zero(builder:BoundedResultBuilder) { return ce_zero(ResultBuilder()) }
def ce_return(builder:BoundedResultBuilder; value:auto) { return ce_return(ResultBuilder(),value) }
def ce_unwrap(builder:BoundedResultBuilder; value:variant<ok:auto(T);error:string>) : T { return value as ok }
def ce_bind(builder:BoundedResultBuilder; value:variant<ok:auto(T);error:string>; next:block<(item:T):auto(R)>) : R {
    return ce_bind(ResultBuilder(),value,next)
}
def ce_combine(builder:BoundedResultBuilder; first:variant<ok:CeUnit;error:string>; next:block<():auto(R)>) : R {
    return ce_combine(ResultBuilder(),first,next)
}

// No ce_loop_append/ce_loop_failed overloads: these operations fully own loops.
def ce_for(builder:BoundedResultBuilder; source:range; body:auto) {
    var count=0
    var result=ce_zero(builder)
    for (item in source) {
        if (count>=builder.limit) { return variant<ok:CeUnit;error:string>(error="for budget exhausted") }
        count++
        result=invoke(body,item)
        if (result is error) { return result }
    }
    return result
}
def ce_while(builder:BoundedResultBuilder; condition:block<():bool>; body:block<():variant<ok:CeUnit;error:string>>) {
    var count=0
    var result=ce_zero(builder)
    while (invoke(condition)) {
        if (count>=builder.limit) { return variant<ok:CeUnit;error:string>(error="while budget exhausted") }
        count++
        result=invoke(body)
        if (result is error) { return result }
    }
    return result
}

// One budget unit per simultaneous iteration, regardless of the source count.
def ce_for_zip(builder:BoundedResultBuilder; arity:int;
               traverse:block<(visit:block<(body:block<():variant<ok:CeUnit;error:string>>):bool>):void>) {
    var count=0
    var result=ce_zero(builder)
    invoke(traverse, $(body:block<():variant<ok:CeUnit;error:string>>) {
        if (count>=builder.limit) {
            result=variant<ok:CeUnit;error:string>(error="zip for budget exhausted")
            return false
        }
        count++
        result=invoke(body)
        return result is ok
    })
    return result
}
