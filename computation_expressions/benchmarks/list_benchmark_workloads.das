options gen2
module list_benchmark_workloads public
require benchmark_workloads public
struct BenchOwned {payload:array<int>}
def bench_numbers(n:int) {
    var inscope values:array<int>
    for(i in range(n)) {values |> push(i+1)}
    return <- values
}
def bench_owned(n:int) {
    var inscope values:array<BenchOwned>
    for(i in range(n)) {
        var inscope item:BenchOwned
        item.payload |> push(i+1)
        values |> emplace(item)
    }
    return <- values
}
def bench_list_sum(values:array<int>) : int64 {
    var result=0l
    for(i in range(length(values))) {result+=int64(i+1)*int64(values[i])}
    return result
}
def bench_list_variable_ce(seed:int) : int64 {
    var inscope left <- bench_numbers(seed%9)
    var inscope right <- bench_numbers(seed%13)
    var inscope values <- computation(ListBuilder()) {
        let a=left |> bind
        let b=right |> bind
        return a*b+seed
    }
    return bench_list_sum(values)
}
def bench_list_variable_manual(seed:int) : int64 {
    var inscope left <- bench_numbers(seed%9)
    var inscope right <- bench_numbers(seed%13)
    var inscope values:array<int>
    for(a in left) {for(b in right) {values |> push(a*b+seed)}}
    return bench_list_sum(values)
}
def bench_owned_sum(values:array<BenchOwned>) : int64 {
    var result=0l
    for(i in range(length(values))) {result+=int64(i+1)*int64(values[i].payload[0])}
    return result
}
def bench_list_owned_ce(seed:int) : int64 {
    var inscope source <- bench_owned(seed%15+1)
    var inscope values <- computation(ListBuilder(type<BenchOwned>)) {
        var item & = source |> bind
        return <- item
    }
    assert(length(source)==0)
    return bench_owned_sum(values)
}
def bench_list_owned_manual(seed:int) : int64 {
    var inscope source <- bench_owned(seed%15+1)
    var inscope owner <- source
    var inscope values:array<BenchOwned>
    for(i in range(length(owner))) {values |> emplace(owner[i])}
    assert(length(source)==0)
    return bench_owned_sum(values)
}
