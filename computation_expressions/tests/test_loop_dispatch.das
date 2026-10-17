options gen2
require ../lib/computation_macro.das
require ../lib/list_builder.das
struct ForOnly {}
struct WhileOnly {}
struct Legacy {}
var forCalls=0
var whileCalls=0
var evaluations=0
var visits=0

def ce_protocol(builder:tuple<kind:auto>) { return CeValueProtocol() }
def ce_zero(builder:tuple<kind:auto>) { return 0 }
def ce_return(builder:tuple<kind:auto>; value:int) { return value }
def ce_combine(builder:tuple<kind:auto>; first:int; next:block<():int>) { return invoke(next) }
def ce_loop_append(builder:tuple<kind:auto>; first,step:int) { return first+step }
def ce_loop_failed(builder:tuple<kind:auto>; value:int) { return false }
def ce_for(builder:tuple<kind:ForOnly>; source:range; body:auto) { forCalls++; return 0 }
def ce_while(builder:tuple<kind:WhileOnly>; condition:block<():bool>; body:block<():int>) { whileCalls++; return 0 }
def source() { evaluations++; return range(3) }
def condition() { evaluations++; return visits<3 }

// A domain source need not be natively iterable when its element type is given.
struct CountSource { count:int }
def ce_for_element(source:CountSource) : int { return 0 }
def ce_for(builder:tuple<kind:ForOnly>; source:CountSource; body:auto) {
    forCalls++
    return invoke(body,source.count)
}

// Custom Collect hooks return owned arrays; neither legacy append operation exists.
struct CollectProbe {}
def ce_protocol(builder:CollectProbe) { return CeCollectProtocol() }
def ce_zero(builder:CollectProbe) { return <- ce_zero(ListBuilder()) }
def ce_return(builder:CollectProbe; value:int) { return <- ce_return(ListBuilder(),value) }
def ce_delay(builder:CollectProbe; body:block<():array<int>>) { return <- invoke(body) }
def ce_combine(builder:CollectProbe; first:array<int>; next:block<():array<int>>) { return <- ce_combine(ListBuilder(),first,next) }
def ce_for(builder:CollectProbe; source:range; body:block<(value:int):array<int>>) {
    forCalls++
    var inscope result:array<int>
    for (i in source) {
        var inscope part <- invoke(body,i)
        for (v in part) { result |> push(v) }
    }
    return <- result
}
def ce_while(builder:CollectProbe; condition:block<():bool>; body:block<():array<int>>) {
    whileCalls++
    var inscope result:array<int>
    while (invoke(condition)) {
        var inscope part <- invoke(body)
        for (v in part) { result |> push(v) }
    }
    return <- result
}
[export]
def main() {
    let a=computation((kind=ForOnly())) {
        for (i in source()) { visits++ }
        while (visits<2) {visits++}
        return visits
    }
    assert(a==2 && evaluations==1 && forCalls==1 && whileCalls==0)
    visits=0
    let b=computation((kind=WhileOnly())) {
        for (i in source()) {visits++}
        while (condition()) {visits++}
        return visits
    }
    assert(b==3 && evaluations==2 && forCalls==1 && whileCalls==1)
    visits=0
    let c=computation((kind=Legacy())) {
        for (i in source()) {visits++}
        while (visits<5) {visits++}
        return visits
    }
    assert(c==5 && evaluations==3 && forCalls==1 && whileCalls==1)
    // Native zip loops use fallback even if a single-source hook is present.
    visits=0
    let zip=computation((kind=ForOnly())) {
        for (i,j in range(3),range(2)) {visits+=i+j}
        return visits
    }
    assert(zip==2 && forCalls==1)
    let domain=computation((kind=ForOnly())) {
        for (n in CountSource(count=7)) {visits+=n}
        return visits
    }
    assert(domain==9 && forCalls==2)
    let baseline=heap_bytes_allocated()
    {
        var n=0
        var inscope result <- computation(CollectProbe()) {
            for (i in range(3)) {yield i*2}
            while (n<2) {n++; yield n*10}
        }
        assert(length(result)==5 && result[0]==0 && result[2]==4 && result[3]==10 && result[4]==20)
        assert(forCalls==3 && whileCalls==2)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
    print("loop dispatch checks OK\n")
}
