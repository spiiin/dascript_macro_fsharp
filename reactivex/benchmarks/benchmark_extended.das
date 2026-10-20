options gen2
options max_infer_passes=2048
require ./extended_workloads.das

[export]
def main() {
    for(name in fixed_array("map_control","scan","distinct","tap","take","skip","take_while","skip_while","pairwise","long_chain","resubscribe","zip_queue","concat_queue","concat_sync","concat_reuse","observe_queue","delay_queue")) {
        verify(extended_workload(name,true,8,2)==extended_workload(name,false,8,2))
        for(size in fixed_array(32,256,1024)) {
            for(repetition in range(5)) {
                var manual=0l;var reactive=0l
                if(repetition%2==0) {
                    manual=extended_sample(name,true,size,repetition)
                    reactive=extended_sample(name,false,size,repetition)
                } else {
                    reactive=extended_sample(name,false,size,repetition)
                    manual=extended_sample(name,true,size,repetition)
                }
                verify(manual==reactive)
            }
        }
    }
    for(name in fixed_array("zip_queue","concat_queue","observe_queue","delay_queue")) {
        extended_queue_sample(name,8,-1)
        for(size in fixed_array(32,256,1024)) {
            for(repetition in range(5)) {extended_queue_sample(name,size,repetition)}
        }
    }
    print("ReactiveX extended benchmarks OK\n")
}
