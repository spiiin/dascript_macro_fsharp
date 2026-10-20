options gen2
require ../lib/computation.das
require daslib/rtti
var trace=""
var opened=0
var closed=0
struct Ticket {id:int}
def acquire(id:int) {opened++; trace+="open{id};"; return Ticket(id=id)}
def ce_dispose(var ticket:Ticket) {closed++; trace+="close{ticket.id};"}
def source(seed:int) {trace+="m;"; if(seed<0){return result_error("negative",type<int>)};return result_ok(seed)}
def f(seed:int) {trace+="f;"; if(seed==2){return result_error("two",type<int>)};return result_ok(seed+1)}
def g(seed:int) {trace+="g;"; return result_ok(seed*3)}
def map_pair(x,y:int) {trace+="{x}:{y};";return x+y}
def equivalent(a,b:$Result<int;string>) {
    assert((a is ok)==(b is ok))
    if(a is ok){assert((a as ok)==(b as ok))}else{assert((a as err)==(b as err))}
}
def grouped(seed:int) {
    return computation(ResultBuilder()) {
        let first=computation(ResultBuilder()) {let n=source(seed) |> bind; return f(n) |> return_from} |> bind
        return g(first) |> return_from
    }
}
def nested(seed:int) {
    return computation(ResultBuilder()) {
        let n=source(seed) |> bind
        return computation(ResultBuilder()) {let next=f(n) |> bind;return g(next) |> return_from} |> return_from
    }
}
def resource_map(seed:int; fused:bool) {
    return computation(ResultBuilder()) {
        let ticket=acquire(seed) |> use_resource
        if(fused) {
            let n=source(seed) |> bind
            return n+ticket.id
        } else {
            let n=source(seed) |> bind
            // A statement between bind and return forces ordinary continuation.
            let total=n+ticket.id
            return total
        }
    }
}
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for(seed in fixed_array(-1,0,1,2,3,17)) {
        // Left identity: return a >>= f == f(a), including its effects.
        trace=""
        let left=computation(ResultBuilder()) {let n=result_ok(seed) |> bind;return f(n) |> return_from}
        let leftTrace=trace
        trace=""
        let direct=f(seed)
        equivalent(left,direct);assert(trace==leftTrace)
        // Right identity, through the optimized BindReturn path.
        trace=""
        let right=computation(ResultBuilder()) {let n=source(seed) |> bind;return n}
        let rightTrace=trace
        trace="";let original=source(seed)
        equivalent(right,original);assert(trace==rightTrace)
        // Associativity: don't precompute either side's effectful sources.
        trace="";let a=grouped(seed);let aTrace=trace
        trace="";let b=nested(seed)
        equivalent(a,b);assert(trace==aTrace)
        // BindReturn vs ordinary Bind/Return with resource lifetime.
        trace="";let fast=resource_map(seed,true);let fastTrace=trace
        trace="";let slow=resource_map(seed,false)
        equivalent(fast,slow);assert(trace==fastTrace && opened==closed)
    }
    // List: associativity and both identities preserve order and ownership.
    {
        var inscope original <- [1,2,3]
        var inscope identity <- computation(ListBuilder()) {let x=original |> bind;return x}
        assert(length(identity)==length(original))
        for(a,b in identity,original){assert(a==b)}
        trace=""
        var inscope fused <- computation(ListBuilder()) {
            let x=original |> bind
            let y=fixed_array(10,20) |> bind
            return map_pair(x,y)
        }
        let expectedTrace=trace
        trace=""
        var inscope groupedList <- computation(ListBuilder()) {
            let x=original |> bind
            return computation(ListBuilder()) {
                let y=fixed_array(10,20) |> bind
                return map_pair(x,y)
            } |> return_from
        }
        assert(trace==expectedTrace && length(fused)==length(groupedList))
        for(a,b in fused,groupedList){assert(a==b)}
        var inscope singleton <- computation(ListBuilder()) {let x=fixed_array(7) |> bind;return x+1}
        assert(length(singleton)==1 && singleton[0]==8)
    }
    let after=heap_bytes_allocated()
    assert(after==baseline && opened==closed)
    print("Composition laws OK\n")
}
