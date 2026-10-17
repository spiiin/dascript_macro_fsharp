options gen2
require ../lib/computation.das
require daslib/rtti
require daslib/strings_boost
var opened=0
var closed=0
var bodies=0
var after=0
struct Resource {}
def ce_dispose(var value:Resource) {closed++}
def acquire() {opened++; return Resource()}
def source(failAt:int) {
    return <- computation(SequenceBuilder()) {
        let resource=acquire() |> use_resource
        for (i in range(5)) {
            if (i==failAt) {panic("producer")}
            yield i
        }
    }
}
def reset() {opened=0; closed=0; bodies=0; after=0}
def check_failure(zip:bool; failAt:int; consumer:bool) {
    reset()
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        if (zip) {
            var inscope values <- computation(ListBuilder()) {
                for (a,b in source(failAt),source(-1)) {
                    let amount=fixed_array(a+b) |> bind
                    bodies++
                    if (consumer && a==2) {panic("consumer")}
                    yield amount
                }
                after++
            }
        } else {
            var inscope values <- computation(ListBuilder()) {
                for (a in source(failAt)) {
                    let amount=fixed_array(a) |> bind
                    bodies++
                    if (consumer && a==2) {panic("consumer")}
                    yield amount
                }
                after++
            }
        }
    } recover {
        caught=true
        assert(starts_with(this_context().last_exception,consumer ? "consumer" : "producer"))
    }
    assert(caught && after==0 && opened==closed)
    assert(bodies==(consumer ? 3 : failAt))
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def temporary() {return <- [10,20,30]}
def array_failure() {
    let baseline=heap_bytes_allocated()
    {
        var inscope values <- temporary()
        var caught=false
        try {
            var inscope output <- computation(ListBuilder()) {
                for (a,b in values,temporary()) {
                    a++
                    if (a==21) {panic("array body")}
                    yield a+b
                }
            }
        } recover {caught=true; assert(starts_with(this_context().last_exception,"array body"))}
        assert(caught && values[0]==11 && values[1]==21 && values[2]==30)
        values |> push(40)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
// An external Value builder with legacy loop operations and no For hooks.
struct Legacy {}
def ce_protocol(builder:Legacy) {return CeValueProtocol()}
def ce_zero(builder:Legacy) {return 0}
def ce_return(builder:Legacy; value:int) {return value}
def ce_combine(builder:Legacy; first:int; next:block<():int>) {return invoke(next)}
def ce_loop_append(builder:Legacy; first,step:int) {return first+step}
def ce_loop_failed(builder:Legacy; value:int) {return value>=3}
def legacy_failure() {
    reset()
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        let value=computation(Legacy()) {
            for (item in source(-1)) {
                bodies++
                if (item==2) {panic("legacy")}
            }
            after++
        }
    } recover {caught=true; assert(starts_with(this_context().last_exception,"legacy"))}
    assert(caught && opened==1 && closed==1 && bodies==3 && after==0)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def legacy_stop() {
    reset()
    let baseline=heap_bytes_allocated()
    let result=computation(Legacy()) {
        for (item in source(-1)) {
            bodies++
            return 1
        }
    }
    assert(result==3 && bodies==3 && opened==1 && closed==1)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
// Legacy append may accept a step type different from its accumulator.
struct Mixed {}
def ce_protocol(builder:Mixed) {return CeValueProtocol()}
def ce_zero(builder:Mixed) {return 0}
def ce_return(builder:Mixed; value:bool) {return value}
def ce_loop_append(builder:Mixed; total:int; step:bool) {return total+(step ? 1 : 0)}
def ce_loop_failed(builder:Mixed; total:int) {return false}
def copy_values(values:array<int>) {
    return <- computation(ListBuilder()) {for (value in values) {yield value}}
}
def borrowed_parameter() {
    let baseline=heap_bytes_allocated()
    {
        var inscope input <- [1,2]
        var inscope output <- copy_values(input)
        assert(length(output)==2 && output[1]==2)
        input |> push(3)
        assert(length(input)==3)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
[export]
def main() {
    let mixed=computation(Mixed()) {for (value in range(5)) {return value%2==0}}
    assert(mixed==3)
    for (round in range(5)) {
        check_failure(false,0,false)
        check_failure(false,2,false)
        check_failure(false,-1,true)
        check_failure(true,0,false)
        check_failure(true,2,false)
        check_failure(true,-1,true)
        array_failure()
        legacy_failure()
        legacy_stop()
        borrowed_parameter()
    }
    reset()
    var inscope recovered <- computation(ListBuilder()) {
        try_with($ {
            for (a in source(2)) {yield a}
        }, $(message:string) {
            assert(closed==1 && starts_with(message,"producer"))
            yield 42
        })
    }
    assert(length(recovered)==1 && recovered[0]==42)
    print("fallback cleanup checks OK\n")
}
