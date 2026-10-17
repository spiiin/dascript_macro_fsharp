options gen2
require ../lib/computation.das
require ../lib/validation_builder.das
require ../support/protocol_collect_fixture.das

var mappedCount=0
var sourceCount=0
var closed=0
struct Resource {}
def ce_dispose(var resource:Resource) { closed++ }
def map_value(n:int) { mappedCount++; return n*2 }
def numbers() { sourceCount++; return <- [1,2,3] }
def fail_map(n:int) { if (n==2) { panic("mapper failed") }; return n }
[export]
def main() {
    let failed=computation(ResultBuilder()) { let x=result_error("bad",type<int>) |> bind; return map_value(x) }
    let absent=computation(OptionBuilder()) { let x=none(type<int>) |> bind; return map_value(x) }
    let invalid=computation(ValidationBuilder()) { let x=validation_error("bad",type<int>) |> bind; return map_value(x) }
    assert(failed is error && absent is none && invalid is invalid && mappedCount==0)
    let ok=computation(ResultBuilder()) { let x=result_ok(3) |> bind; return map_value(x) }
    assert(ok is ok && (ok as ok)==6 && mappedCount==1)
    let baseline=heap_bytes_allocated()
    for (iteration in range(20)) {
        {
            var inscope values <- computation(ListBuilder()) { let n=numbers() |> bind; return map_value(n) }
            assert(length(values)==3 && values[0]==2 && values[2]==6)
        }
        var caught=false
        try {
            var inscope values <- computation(ListBuilder()) {
                let resource=Resource() |> use_resource
                let n=numbers() |> bind
                return fail_map(n)
            }
        } recover { caught=true }
        assert(caught)
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(sourceCount==40 && closed==20 && mappedCount==61)
    {
        var inscope borrowed <- [1,2,3]
        var inscope values <- computation(ListBuilder()) { let n=borrowed |> bind; return n+1 }
        assert(length(borrowed)==3 && length(values)==3)
        var inscope legacy <- computation(ExternalCollectionBuilder()) { let n=borrowed |> bind; return n+2 }
        assert(length(legacy)==3 && legacy[0]==3 && length(borrowed)==3)
    }
    let after=heap_bytes_allocated()
    assert(after==baseline)
    print("bind_return behavior and lifetime checks OK\n")
}
