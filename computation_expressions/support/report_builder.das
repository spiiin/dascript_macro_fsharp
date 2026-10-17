options gen2
module report_builder public
require ../lib/computation_builders.das public

struct ReportBuilder { title:string }
def ce_protocol(builder:ReportBuilder) { return CeValueProtocol() }
def ce_unwrap(builder:ReportBuilder; source:variant<ok:auto(T);error:string>) : T { return source as ok }
def ce_return(builder:ReportBuilder; value:auto) { return ce_return(ResultBuilder(),value) }
def ce_return_from(builder:ReportBuilder; source:variant<ok:auto(T);error:string>) { return source }
def ce_zero(builder:ReportBuilder) { return ce_zero(ResultBuilder()) }
def ce_bind(builder:ReportBuilder; source:variant<ok:auto(T);error:string>; next:block<(value:T):auto(R)>) : R {
    return ce_bind(ResultBuilder(),source,next)
}
def ce_combine(builder:ReportBuilder; first:variant<ok:CeUnit;error:string>; next:block<():auto(R)>) : R {
    return ce_combine(ResultBuilder(),first,next)
}
def ce_loop_failed(builder:ReportBuilder; step:variant<ok:CeUnit;error:string>) : bool { return ce_loop_failed(ResultBuilder(),step) }
def ce_loop_append(builder:ReportBuilder; first,step:variant<ok:CeUnit;error:string>) { return ce_loop_append(ResultBuilder(),first,step) }
def ce_merge_sources(builder:ReportBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>) {
    return ce_merge_sources(ResultBuilder(),left,right)
}
def ce_bind_return(builder:ReportBuilder; source:variant<ok:auto(T);error:string>; mapper:block<(value:T):auto(U)>) {
    return ce_bind_return(ResultBuilder(),source,mapper)
}
def ce_bind2_return(builder:ReportBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) {
    return ce_bind2_return(ResultBuilder(),left,right,mapper)
}
def ce_bind2(builder:ReportBuilder; left:variant<ok:auto(A);error:string>; right:variant<ok:auto(B);error:string>;
             next:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    return ce_bind2(ResultBuilder(),left,right,next)
}
// Only the outer CE boundary converts the internal Result into a public report.
def ce_run(builder:ReportBuilder; outcome:variant<ok:auto(T);error:string>) : variant<completed:tuple<title:string;value:T -const -&>;failed:tuple<title:string;message:string>> {
    if (outcome is error) { return variant<completed:tuple<title:string;value:T -const -&>;failed:tuple<title:string;message:string>>(failed=(title=builder.title,message=outcome as error)) }
    return variant<completed:tuple<title:string;value:T -const -&>;failed:tuple<title:string;message:string>>(completed=(title=builder.title,value=outcome as ok))
}
