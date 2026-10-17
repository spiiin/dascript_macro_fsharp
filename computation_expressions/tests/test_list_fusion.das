options gen2
require ../lib/computation.das
require ../benchmarks/list_benchmark_workloads.das
require daslib/rtti
var trace=""
var live=0
var right=fixed_array(3,4)
struct Owned {
    payload:array<int>
    def finalize {
        if(length(payload)>0) {trace+="D{payload[0]};";live--}
        else {trace+="E;"}
        delete payload
    }
}
def items(first,count:int) {
    var inscope values:array<Owned>
    for(i in range(count)) {
        var inscope item:Owned
        item.payload |> push(first+i);live++
        values |> emplace(item)
    }
    return <- values
}
def transfer(var item:Owned; fail:int) {
    trace+="M{item.payload[0]};"
    if(item.payload[0]==fail) {panic("map failed")}
    return <- item
}
def owned_case(fast,nested:bool; fail:int) {
    let baseline=heap_bytes_allocated()
    var caught=false
    {
        var inscope source <- items(1,3)
        var inscope result:array<Owned>
        try {
            if(nested) {
                if(fast) {
                    result <- computation(ListBuilder(type<Owned>)) {
                        var a & = source |> bind
                        var b & = items(a.payload[0]*10,2) |> bind
                        return <- transfer(b,fail)
                    }
                } else {
                    result <- computation(ListBuilder(type<Owned>)) {
                        var a & = source |> bind
                        var b & = items(a.payload[0]*10,2) |> bind
                        let barrier=0
                        return <- transfer(b,fail)
                    }
                }
            } else {
                if(fast) {
                    result <- computation(ListBuilder(type<Owned>)) {
                        var a & = source |> bind
                        return <- transfer(a,fail)
                    }
                } else {
                    result <- computation(ListBuilder(type<Owned>)) {
                        var a & = source |> bind
                        let barrier=0
                        return <- transfer(a,fail)
                    }
                }
            }
        } recover {caught=true}
        assert(caught==(fail>=0) && length(source)==0)
        if(!caught) {assert(length(result)==(nested ? 6 : 3))}
    }
    assert(live==0)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def second(a:int) {trace+="S{a};";return right}
def mapped(a,b:int; fail:bool) {
    trace+="V{a},{b};";right[0]++
    if(fail && a==2) {panic("copy map failed")}
    return a*10+b
}
def copy_case(fast,fail,emptySource:bool) {
    let baseline=heap_bytes_allocated()
    var caught=false
    {
        var inscope left:array<int>
        if(!emptySource) {left |> push(1);left |> push(2)}
        var inscope output:array<int>
        try {
            if(fast) {
                output <- computation(ListBuilder()) {
                    let a=left |> bind
                    let b=second(a) |> bind
                    return mapped(a,b,fail)
                }
            } else {
                output <- computation(ListBuilder()) {
                    let a=left |> bind
                    let barrier=0
                    let b=second(a) |> bind
                    return mapped(a,b,fail)
                }
            }
        } recover {caught=true}
        assert(caught==(fail && !emptySource))
        if(!caught) {trace+="O{output};"}
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

struct Wrapped {value:Owned}
def plain_transfer(var item:BenchOwned; fail:int) {
    if(item.payload[0]==fail) {panic("plain owner failed")}
    return <- item
}
def plain_failure() {
    let baseline=heap_bytes_allocated()
    for(fail in range(1,5)) {
        var inscope source <- bench_owned(4)
        var caught=false
        try {
            var inscope result <- computation(ListBuilder(type<BenchOwned>)) {
                var item & = source |> bind
                return <- plain_transfer(item,fail)
            }
        } recover {caught=true}
        assert(caught && length(source)==0)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
[export]
def main() {
    assert(typeinfo ce_has_collect_sink(ce_collect_sink(ListBuilder(type<BenchOwned>))))
    assert(!(typeinfo ce_has_collect_sink(ce_collect_sink(ListBuilder(type<Owned>)))))
    assert(!(typeinfo ce_has_collect_sink(ce_collect_sink(ListBuilder(type<Wrapped>)))))
    plain_failure()
    {
        var inscope triple <- computation(ListBuilder()) {
            let a=fixed_array(1,2) |> bind
            fixed_array(0,0) |> bind
            let b=fixed_array(3,4) |> bind
            return a*10+b
        }
        assert(length(triple)==8 && triple[0]==13 && triple[7]==24)
    }

    for(fail in fixed_array(false,true)) {
        for(emptySource in fixed_array(false,true)) {
            trace="";right=fixed_array(3,4);copy_case(false,fail,emptySource)
            let expected=trace
            trace="";right=fixed_array(3,4);copy_case(true,fail,emptySource)
            assert(trace==expected)
        }
    }
    for(nested in fixed_array(false,true)) {
        for(fail in fixed_array(-1,nested ? 21 : 2)) {
            trace="";owned_case(false,nested,fail);let expected=trace
            trace="";owned_case(true,nested,fail);assert(trace==expected)
        }
    }
    print("List fusion effects and ownership OK\n")
}
