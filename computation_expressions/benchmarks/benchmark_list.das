options gen2
require list_benchmark_workloads
require daslib/rtti
require strings

def batch(iterations:int; work:block<(seed:int):int64>) : int64 {
    var checksum=0l
    for (i in range(iterations)) {checksum+=invoke(work,i%64)}
    return checksum
}
def sample(name,implementation:string; repetition,iterations:int; work:block<(seed:int):int64>) : int64 {
    let before=heap_bytes_allocated()
    let start=ref_time_ticks()
    let checksum=batch(iterations,work)
    let elapsed=int64(get_time_nsec(start))
    let after=heap_bytes_allocated()
    assert(before==after)
    print("BENCH,{name},{implementation},{repetition},{iterations},{elapsed},{checksum},{before},{after}\n")
    return checksum
}
def compare(name:string; iterations,samples:int; ce,manual:block<(seed:int):int64>) {
    let warmCe=batch(1000,ce)
    let warmManual=batch(1000,manual)
    assert(warmCe==warmManual)
    for (repetition in range(samples)) {
        var a=0l
        var b=0l
        if (repetition%2==0) {
            a=sample(name,"ce",repetition,iterations,ce)
            b=sample(name,"manual",repetition,iterations,manual)
        } else {
            b=sample(name,"manual",repetition,iterations,manual)
            a=sample(name,"ce",repetition,iterations,ce)
        }
        assert(a==b)
    }
}
[export]
def main() {
    var iterations=10000
    var samples=7
    let args <- get_command_line_arguments()
    for (i in range(length(args))) {
        if (args[i]=="--iterations" || args[i]=="--samples") {
            assert(i+1<length(args))
            let count=to_int(args[i+1])
            if (args[i]=="--iterations") {iterations=count} else {samples=count}
        }
    }
    assert(iterations>0 && samples>0)
    compare("list_product",iterations,samples,$(seed:int) {return bench_list_ce(seed)},$(seed:int) {return bench_list_manual(seed)})
    compare("list_variable",iterations,samples,$(seed:int) {return bench_list_variable_ce(seed)},$(seed:int) {return bench_list_variable_manual(seed)})
    compare("list_owned",iterations,samples,$(seed:int) {return bench_list_owned_ce(seed)},$(seed:int) {return bench_list_owned_manual(seed)})
    print("CE benchmarks OK\n")
}
