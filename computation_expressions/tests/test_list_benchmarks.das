options gen2
require ../benchmarks/list_benchmark_workloads.das
require daslib/rtti
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for(seed in range(64)) {
        verify(bench_list_ce(seed)==bench_list_manual(seed))
        verify(bench_list_variable_ce(seed)==bench_list_variable_manual(seed))
        verify(bench_list_owned_ce(seed)==bench_list_owned_manual(seed))
    }
    let current=heap_bytes_allocated();assert(current==baseline)
    print("List benchmark equivalence OK\n")
}
