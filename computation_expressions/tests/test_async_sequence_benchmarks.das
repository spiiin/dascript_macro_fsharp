options gen2
options max_infer_passes=512
require ../benchmarks/async_sequence_workloads.das
require daslib/rtti
[export]
def main() {
    for(name in fixed_array("next","for","zip","and_bind","move")) {
        verify(async_bench_run(name,false,3,0,3,1)==async_bench_run(name,true,3,0,3,1))
    }
    let before=heap_bytes_allocated()
    for(name in fixed_array("next","for","zip","and_bind","move")) {
        for(count in fixed_array(0,1,2,9)) {
            for(work in fixed_array(0,3,32)) {
                for(pending in fixed_array(0,1,2)) {
                    for(seed in range(3)) {
                        let ce=async_bench_run(name,false,count,seed,work,pending)
                        let manual=async_bench_run(name,true,count,seed,work,pending)
                        var expected=0l
                        for(i in range(count)) {
                            let value=(name=="zip" || name=="and_bind") ? (i+seed) ^ (i+seed+17) : i+seed
                            expected+=int64(async_bench_mix(value,work))
                        }
                        verify(ce==expected && manual==expected)
                    }
                }
            }
        }
    }
    verify(heap_bytes_allocated()==before)
    print("Async sequence benchmark checks OK\n")
}
