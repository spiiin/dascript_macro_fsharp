options gen2
options max_infer_passes=2048
require ../benchmarks/extended_workloads.das

def check_workloads(size:int) {
    for(name in fixed_array("map_control","scan","distinct","tap","take","skip","take_while","skip_while","pairwise","long_chain","resubscribe","zip_queue","concat_queue","concat_sync","concat_reuse","observe_queue","delay_queue")) {
        verify(extended_workload(name,true,size,2)==extended_workload(name,false,size,2))
    }
}

[export]
def main() {
    check_workloads(8)
    let baseline=heap_bytes_allocated()
    check_workloads(2)
    check_workloads(33)
    for(name in fixed_array("zip_queue","concat_queue","observe_queue","delay_queue")) {extended_queue_sample(name,33,-1)}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX extended workload checks OK\n")
}
