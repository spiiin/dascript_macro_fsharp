options gen2
require ../lib/computation.das
require ../support/game_source_builder.das
require ../lib/deferred_computation.das
require daslib/rtti
var factories=0
var conversions=0
var order=""
struct Token {id:int;value:int;fail:bool=false}
def token(id,value:int;fail:bool=false) {factories++;return Token(id=id,value=value,fail=fail)}
def ce_source(builder:ResultBuilder; value:Token) {
    conversions++;order+="{value.id}"
    return value.fail ? result_error("stop",type<int>) : result_ok(value.value)
}
def ce_source(builder:OptionBuilder; value:Token) {
    conversions++;order+="{value.id}"
    return value.fail ? none(type<int>) : some(value.value)
}
struct Batch {first:int}
def ce_source(builder:tuple<kind:ListContext;element:int>; batch:Batch) {
    conversions++
    return <- [batch.first,batch.first+1]
}
def ce_source(builder:tuple<kind:SequenceContext;element:int>; batch:Batch) {
    conversions++
    return range(batch.first,batch.first+2)
}
def ce_source(builder:GameSourceBuilder; batch:Batch) {
    conversions++
    return <- [batch.first,batch.first+1]
}
def ce_unwrap(builder:GameSourceBuilder; source:array<int>) {return source[0]}
def ce_bind(builder:GameSourceBuilder; source:array<int>; next:block<(value:int):auto(R)>) : R {
    return invoke(next,source[0])
}
struct MutableView {values:array<int>?}
def ce_source(builder:ResultBuilder; source:MutableView) : array<int>& {
    unsafe {return *source.values}
}
def reset() {factories=0;conversions=0;order=""}
def basic() {
    reset()
    let value=computation(ResultBuilder()) {let n=token(1,10) |> bind;return n+1}
    assert(value as ok==11 && factories==1 && conversions==1 && order=="1")
    reset()
    let forwarded=computation(ResultBuilder()) {return token(1,15) |> return_from}
    assert(forwarded as ok==15 && conversions==1 && factories==1)
    reset()
    let pair=computation(ResultBuilder()) {
        let both=token(1,10) |> and_bind(token(2,20)) |> bind
        return both.first+both.second
    }
    assert(pair as ok==30 && factories==2 && conversions==2 && order=="12")
    reset()
    let failure=computation(OptionBuilder()) {
        token(1,10,true) |> bind
        token(2,20) |> bind
        return 42
    }
    assert(failure is none && factories==1 && conversions==1)
}
def collection() {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope output <- computation(ListBuilder()) {
            let n=Batch(first=10) |> bind
            yield n
        }
        assert(length(output)==2 && output[0]==10 && output[1]==11 && conversions==1)
    }
    {
        var inscope forwarded <- computation(ListBuilder()) {Batch(first=20) |> yield_from}
        assert(length(forwarded)==2 && forwarded[0]==20)
        var inscope returned <- computation(ListBuilder()) {return Batch(first=30) |> return_from}
        assert(length(returned)==2 && returned[0]==30)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
    var caught=false
    try {
        var inscope output <- computation(ListBuilder()) {
            let n=Batch(first=10) |> bind
            panic("body")
            yield n
        }
    } recover {caught=true}
    let failedBytes=heap_bytes_allocated()
    assert(caught && baseline==failedBytes)
}
def value_owned() {
    let baseline=heap_bytes_allocated()
    let result=computation(GameSourceBuilder()) {let n=Batch(first=7) |> bind;return n+1}
    assert(result as ok==8)
    var caught=false
    try {
        let failed=computation(GameSourceBuilder()) {
            let n=Batch(first=7) |> bind
            panic("value body")
            return n
        }
    } recover {caught=true}
    let current=heap_bytes_allocated()
    assert(caught && baseline==current)
}
def loops() {
    var total=0
    let outcome=computation(GameSourceBuilder()) {
        for(a,b in TargetRange(first=10,count=3),TargetRange(first=1,count=2)) {total+=a+b}
    }
    assert(outcome is ok && total==24)
    reset()
    {
        var inscope output <- computation(ListBuilder()) {
            for(n in Batch(first=3)) {yield n*2}
        }
        assert(conversions==1 && length(output)==2 && output[0]==6 && output[1]==8)
    }
    // With no Source overload, mutable arrays remain borrowed references.
    var inscope input <- [1,2]
    let result=computation(ResultBuilder()) {for(n in input) {n+=10}}
    assert(input[0]==11 && input[1]==12)
    input |> push(3)
    unsafe {
        let view=MutableView(values=addr(input))
        let changed=computation(ResultBuilder()) {for(n in view) {n++}}
    }
    assert(input[0]==12 && input[1]==13 && input[2]==4)
    input |> push(5)
}
def lazy() {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- computation(SequenceBuilder()) {
            let n=Batch(first=10) |> bind
            for(m in Batch(first=20)) {yield n+m}
        }
        assert(conversions==0)
        for(n in stream) {assert(n==30);break}
        assert(conversions==2)
        var inscope other <- computation(SequenceBuilder()) {Batch(first=5) |> yield_from}
        for(n in other) {assert(n==5);break}
        assert(conversions==3)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
    reset()
    var inscope task <- deferred(ResultBuilder(),10) $(value) {
        let n=token(1,value) |> bind
        return n+1
    }
    assert(conversions==0)
    let first=run_deferred(task)
    let second=run_deferred(task)
    assert(first as ok==11 && second as ok==11 && conversions==2 && factories==2)
}
[export]
def main() {
    basic()
    for(round in range(4)) {collection();value_owned();loops();lazy()}
    print("source protocol checks OK\n")
}
