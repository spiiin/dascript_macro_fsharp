options gen2
require ../lib/computation.das

var sources = 0
var rightCalls = 0
var continued = 0
var disposed = 0
struct Resource {}
def ce_dispose(var resource:Resource) { disposed++ }
def source(n:int) {
    sources++
    var inscope result : array<int>
    result |> push(n)
    result |> push(n+1)
    return <- result
}
def failed_source() : array<int> {
    rightCalls++
    panic("right source failed")
    var inscope unused : array<int>
    return <- unused
}
[export]
def main() {
    let baseline = heap_bytes_allocated()
    {
        var inscope left <- [1,2]
        var inscope right <- [10,20]
        var inscope values <- computation(ListBuilder()) {
            let p = left |> and_bind(right) |> bind
            return p.first + p.second
        }
        assert(length(values)==4 && values[0]==11 && values[1]==21 && values[2]==12 && values[3]==22)
        assert(length(left)==2 && length(right)==2 && left[0]==1 && right[0]==10)
        var inscope fixedValues <- computation(ListBuilder(type<string>)) {
            let p = fixed_array(1,2) |> and_bind(fixed_array("a","b")) |> bind
            return "{p.first}{p.second}"
        }
        assert(length(fixedValues)==4 && fixedValues[0]=="1a" && fixedValues[3]=="2b")
        var inscope mixed <- computation(ListBuilder()) {
            let p = left |> and_bind(fixed_array(3,4)) |> bind
            return p.first+p.second
        }
        var inscope mixed2 <- computation(ListBuilder()) {
            let p = fixed_array(3,4) |> and_bind(right) |> bind
            return p.first+p.second
        }
        assert(length(mixed)==4 && length(mixed2)==4)
        var inscope emptySource : array<int>
        var inscope emptyValues <- computation(ListBuilder()) {
            emptySource |> and_bind(source(1)) |> bind
            continued++
            return 1
        }
        assert(length(emptyValues)==0 && sources==1 && continued==0)
        var inscope emptyRight <- computation(ListBuilder()) {
            left |> and_bind(emptySource) |> bind
            continued++
            return 1
        }
        assert(length(emptyRight)==0 && continued==0)
    }
    {
        var inscope borrowed <- [1,2]
        var caught = false
        try {
            var inscope values <- computation(ListBuilder()) {
                borrowed |> and_bind(borrowed) |> bind
                panic("borrowed continuation")
                return 1
            }
        } recover { caught=true }
        assert(caught && length(borrowed)==2)
        borrowed |> push(3)
        assert(length(borrowed)==3)
        var inscope values <- computation(ListBuilder()) {
            fixed_array(1,2) |> and_bind(fixed_array(3,4)) |> bind
            return 7
        }
        assert(length(values)==4 && values[0]==7 && values[3]==7)
    }
    let afterBorrowed = heap_bytes_allocated()
    assert(afterBorrowed == baseline)
    for (iteration in range(20)) {
        {
            var inscope values <- computation(ListBuilder()) {
                let p = source(1) |> and_bind(source(10)) |> and_bind(source(100)) |> bind
                return p.first.first+p.first.second+p.second
            }
            assert(length(values)==8 && values[0]==111 && values[7]==114)
        }
        var caught = false
        try {
            var inscope values <- computation(ListBuilder()) {
                let p = source(1) |> and_bind(source(10)) |> bind
                let resource = Resource() |> use_resource
                if (p.second==11) { panic("continuation failed") }
                return p.first+p.second
            }
        } recover { caught=true }
        assert(caught)
        caught=false
        try {
            var inscope values <- computation(ListBuilder()) {
                let p = source(1) |> and_bind(failed_source()) |> bind
                return p.first+p.second
            }
        } recover { caught=true }
        assert(caught)
        let after = heap_bytes_allocated()
        assert(after == baseline)
    }
    assert(sources==121 && rightCalls==20 && disposed==40)
    print("and_bind list lifetime checks OK\n")
}

