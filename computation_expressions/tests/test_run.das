options gen2
require ../lib/computation.das
require ../support/report_builder.das
var events=""
var runs=0
var creations=0
var closes=0
struct Resource {}
def ce_dispose(var resource:Resource) { closes++; events+="close;" }
struct Probe {}
def make_probe() { creations++; return Probe() }
def ce_protocol(builder:Probe) { return CeValueProtocol() }
def ce_return(builder:Probe; value:auto) { return result_ok(value) }
def ce_zero(builder:Probe) { return result_ok(CeUnit()) }
def ce_bind(builder:Probe; source:variant<ok:auto(T);error:string>; next:block<(value:T):auto(R)>) : R {
    return ce_bind(ResultBuilder(),source,next)
}
def ce_unwrap(builder:Probe; source:variant<ok:auto(T);error:string>) : T { return source as ok }
def ce_run(builder:Probe; outcome:variant<ok:auto(T);error:string>) {
    runs++; events+="run;"
    return (success=outcome is ok,outcome=outcome)
}
struct ArrayOutput {}
def ce_protocol(builder:ArrayOutput) { return CeValueProtocol() }
def ce_return(builder:ArrayOutput; value:int) { return value }
def ce_run(builder:ArrayOutput; value:int) { var inscope a:array<int>; a |> push(value); return <- a }
struct Summary { fail:bool }
def ce_protocol(builder:Summary) { return CeCollectProtocol() }
def ce_return(builder:Summary; value:int) { return <- ce_return(ListBuilder(),value) }
def ce_zero(builder:Summary) { return <- ce_zero(ListBuilder()) }
def ce_delay(builder:Summary; body:block<():array<int>>) { return <- invoke(body) }
def ce_combine(builder:Summary; first:array<int>; next:block<():array<int>>) { return <- ce_combine(ListBuilder(),first,next) }
def ce_collect_append(builder:Summary; var values:array<int>; step:array<int>) { ce_list_append(values,step) }
def ce_collect_rethrow(builder:Summary; var values:array<int>) { ce_list_rethrow(values) }
struct Moved { fail:bool }
def ce_protocol(builder:Moved) { return CeCollectProtocol() }
def ce_return(builder:Moved; value:int) { return <- ce_return(ListBuilder(),value) }
def ce_zero(builder:Moved) { return <- ce_zero(ListBuilder()) }
def ce_delay(builder:Moved; body:block<():array<int>>) { return <- invoke(body) }
def ce_combine(builder:Moved; first:array<int>; next:block<():array<int>>) { return <- ce_combine(ListBuilder(),first,next) }
def ce_collect_append(builder:Moved; var values:array<int>; step:array<int>) { ce_list_append(values,step) }
def ce_collect_rethrow(builder:Moved; var values:array<int>) { ce_list_rethrow(values) }
def ce_run(builder:Summary; values:array<int>) : int {
    runs++
    if (builder.fail) { panic("run failed") }
    var total=0
    for (value in values) { total+=value }
    return total
}
def ce_run(builder:Moved; var values:array<int>) : array<int> {
    runs++
    values |> push(99)
    if (builder.fail) { panic("run failed") }
    return <- values
}
struct RunSequence { fail:bool }
def ce_protocol(builder:RunSequence) { return ce_sequence_protocol(type<int>) }
def ce_sequence_run(builder:RunSequence; var source:iterator<int>) { return <- ce_sequence_protect(source) }
def ce_run(builder:RunSequence; var source:iterator<int>) : int {
    runs++
    var value=0
    var total=0
    while (next(source,value)) {
        total+=value
        if (builder.fail) { panic("run failed") }
    }
    return total
}
[export]
def main() {
    let a=computation(make_probe()) {
        let resource=Resource() |> use_resource
        events+="body;"
        let x=result_ok(2) |> bind
        return x+3
    }
    assert(a.success && a.outcome as ok==5 && events=="body;close;run;" && runs==1 && creations==1)
    let b=computation(Probe()) { let x=result_error("bad",type<int>) |> bind; return x }
    assert(!b.success && runs==2)
    var caught=false
    try {
        let ignored=computation(Probe()) { let resource=Resource() |> use_resource; panic("body failed"); return 1 }
    } recover { caught=true }
    assert(caught && runs==2 && closes==2)
    let nested=computation(Probe()) { let inner=computation(Probe()) { return 9 }; return inner.outcome as ok }
    assert(nested.outcome as ok==9 && runs==4)
    let report=computation(ReportBuilder(title="loop")) {
        for (i in range(3)) { result_ok(CeUnit()) |> bind }
        return (name="Mage",level=3)
    }
    assert(report is completed && (report as completed).value.level==3)
    let baseline=heap_bytes_allocated()
    for (iteration in range(10)) {
        {
            var inscope arrayResult <- computation(ArrayOutput()) { return 7 }
            assert(length(arrayResult)==1 && arrayResult[0]==7)
        }
        let total=computation(Summary()) { for(i in range(4)) { yield i } }
        assert(total==6)
        {
            var inscope moved <- computation(Moved()) { yield 1; yield 2 }
            assert(length(moved)==3 && moved[0]==1 && moved[2]==99)
        }
        var failed=false
        try { let ignored=computation(Summary(fail=true)) { yield 1; yield 2 } } recover { failed=true }
        assert(failed)
        failed=false
        try { var inscope ignored <- computation(Moved(fail=true)) { yield 1; yield 2 } } recover { failed=true }
        assert(failed)
        let sequenceTotal=computation(RunSequence()) { let resource=Resource() |> use_resource; yield 3; yield 4 }
        assert(sequenceTotal==7)
        failed=false
        try { let ignored=computation(RunSequence(fail=true)) { let resource=Resource() |> use_resource; yield 3; yield 4 } } recover { failed=true }
        assert(failed)
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(closes==22 && runs==64)
    print("run protocol checks OK\n")
}
