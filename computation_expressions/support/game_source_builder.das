options gen2
module game_source_builder public
require ../lib/computation_builders.das public

struct GameSourceBuilder { minimumHealth:int=1 }
def ce_protocol(builder:GameSourceBuilder) { return CeValueProtocol() }
def ce_unwrap(builder:GameSourceBuilder; source:variant<ok:auto(T);error:string>) : T { return source as ok }
def ce_return(builder:GameSourceBuilder; value:auto) { return ce_return(ResultBuilder(),value) }
def ce_return_from(builder:GameSourceBuilder; source:variant<ok:auto(T);error:string>) { return source }
def ce_zero(builder:GameSourceBuilder) { return ce_zero(ResultBuilder()) }
def ce_bind(builder:GameSourceBuilder; source:variant<ok:auto(T);error:string>; next:block<(value:T):auto(R)>) : R {
    return ce_bind(ResultBuilder(),source,next)
}
def ce_combine(builder:GameSourceBuilder; first:variant<ok:CeUnit;error:string>; next:block<():auto(R)>) : R {
    return ce_combine(ResultBuilder(),first,next)
}
def ce_loop_failed(builder:GameSourceBuilder; step:variant<ok:CeUnit;error:string>) : bool { return ce_loop_failed(ResultBuilder(),step) }
def ce_loop_append(builder:GameSourceBuilder; first,step:variant<ok:CeUnit;error:string>) { return ce_loop_append(ResultBuilder(),first,step) }
def ce_merge_sources(builder:GameSourceBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>) {
    return ce_merge_sources(ResultBuilder(),left,right)
}
def ce_bind_return(builder:GameSourceBuilder; source:variant<ok:auto(T);error:string>; mapper:block<(value:T):auto(U)>) {
    return ce_bind_return(ResultBuilder(),source,mapper)
}
def ce_bind2_return(builder:GameSourceBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) {
    return ce_bind2_return(ResultBuilder(),left,right,mapper)
}
def ce_bind2(builder:GameSourceBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
             next:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    return ce_bind2(ResultBuilder(),left,right,next)
}

struct HealthCheck {health:int}
struct TargetRange {first:int; count:int}
def ce_source(builder:GameSourceBuilder; request:HealthCheck) {
    if (request.health<builder.minimumHealth) {return result_error("not enough health",type<int>)}
    return result_ok(request.health)
}
def ce_source(builder:GameSourceBuilder; request:TargetRange) {
    return range(request.first,request.first+request.count)
}
