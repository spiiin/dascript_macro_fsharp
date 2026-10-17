options gen2
require ../lib/computation_macro.das
require ../lib/list_builder.das
require daslib/rtti
var calls=0
var lastArity=0
var sources=0
var visits=0
struct ZipOnly {limit:int=2}
def ce_protocol(builder:ZipOnly) {return CeValueProtocol()}
def ce_zero(builder:ZipOnly) {return 0}
def ce_return(builder:ZipOnly; value:int) {return value}
def ce_combine(builder:ZipOnly; first:int; next:block<():int>) {return invoke(next)}
// No native fallback operations. These loops must dispatch through the hook.
def ce_for_zip(builder:ZipOnly; arity:int;
               traverse:block<(visit:block<(body:block<():int>):bool>):void>) {
    calls++; lastArity=arity
    var count=0
    if (builder.limit<=0) {return count}
    invoke(traverse, $(body:block<():int>) {
        let value=invoke(body)
        count++
        return count<builder.limit
    })
    return count
}
def source() {sources++; return range(5)}

struct ZipCollect {}
def ce_protocol(builder:ZipCollect) {return CeCollectProtocol()}
def ce_zero(builder:ZipCollect) {return <- ce_zero(ListBuilder())}
def ce_return(builder:ZipCollect; value:int) {return <- ce_return(ListBuilder(),value)}
def ce_delay(builder:ZipCollect; body:block<():array<int>>) {return <- invoke(body)}
def ce_combine(builder:ZipCollect; first:array<int>; next:block<():array<int>>) {return <- ce_combine(ListBuilder(),first,next)}
def ce_for_zip(builder:ZipCollect; arity:int;
               traverse:block<(visit:block<(body:block<():array<int>>):bool>):void>) {
    calls++; lastArity=arity
    var inscope result:array<int>
    try {
        invoke(traverse, $(body:block<():array<int>>) {
            var inscope step <- invoke(body)
            for (v in step) {result |> push(v)}
            return true
        })
    } recover {
        let message="{this_context().last_exception}"
        delete result
        panic(message)
    }
    return <- result
}
[export]
def main() {
    let stopped=computation(ZipOnly()) {
        for (a,b,c,d in source(),source(),source(),source()) {visits++}
        return visits
    }
    assert(stopped==2 && calls==1 && lastArity==4 && sources==4)
    let suppressed=computation(ZipOnly(limit=0)) {
        for (a,b in source(),source()) {visits++}
    }
    assert(suppressed==0 && calls==2 && lastArity==2 && sources==4 && visits==2)
    let baseline=heap_bytes_allocated()
    {
        var inscope values <- computation(ZipCollect()) {
            for (a,b,c in range(4),range(2),range(5)) {yield a+b+c}
            yield 100
        }
        assert(calls==3 && lastArity==3 && length(values)==3 && values[0]==0 && values[1]==3 && values[2]==100)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
    // Built-in List has no zip hook and uses the protected cursor fallback.
    {
        var inscope values <- computation(ListBuilder()) {
            for (a,b in range(4),range(2)) {yield a+b}
        }
        assert(length(values)==2 && values[0]==0 && values[1]==2)
    }
    print("zip dispatch checks OK\n")
}
