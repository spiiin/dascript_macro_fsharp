options gen2
require ../benchmarks/benchmark_workloads.das
require daslib/rtti
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for (seed in range(64)) {
        verify(bench_result_ce(seed)==bench_result_manual(seed))
        verify(bench_state_ce(seed)==bench_state_manual(seed))
        verify(bench_list_ce(seed)==bench_list_manual(seed))
        verify(bench_sequence_ce(seed)==bench_sequence_manual(seed))
    }
    for (seed in range(64)) {
        for (steps in fixed_array(0,1,2,7,32,97,256)) {
            verify(state_variable_ce(seed,steps)==state_variable_manual(seed,steps))
            verify(state_variable_while_ce(seed,steps)==state_variable_manual(seed,steps))
        }
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
    print("benchmark workload equivalence checks OK\n")
}
