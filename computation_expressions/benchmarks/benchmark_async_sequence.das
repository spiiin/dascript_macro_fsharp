options gen2
options max_infer_passes=512
require ./async_sequence_workloads.das
require daslib/rtti
require strings

def batch(name:string;manual:bool;elements,batches,work,pending:int) : int64 {
    var checksum=0l
    for(i in range(batches)) {checksum+=async_bench_run(name,manual,elements,i%17,work,pending)}
    return checksum
}
def sample(name:string;manual:bool;repetition,elements,batches,work,pending:int) : int64 {
    let before=heap_bytes_allocated()
    let allocations=heap_allocation_count()
    let bytes=heap_allocation_stats()[0]
    let start=ref_time_ticks()
    let checksum=batch(name,manual,elements,batches,work,pending)
    let elapsed=int64(get_time_nsec(start))
    let retained=heap_bytes_allocated()-before
    let calls=heap_allocation_count()-allocations
    let allocated=heap_allocation_stats()[0]-bytes
    verify(retained==0)
    let implementation=manual ? "manual" : "ce"
    print("ASYNC,{name},{implementation},{repetition},{elements},{batches},{work},{pending},{elapsed},{checksum},{calls},{allocated},{retained}\n")
    return checksum
}
[export]
def main() {
    var elements=512
    var batches=4
    var samples=7
    var workSize=32
    let args <- get_command_line_arguments()
    for(i in range(length(args)-1)) {
        if(args[i]=="--elements") {elements=to_int(args[i+1])}
        elif(args[i]=="--batches") {batches=to_int(args[i+1])}
        elif(args[i]=="--samples") {samples=to_int(args[i+1])}
        elif(args[i]=="--work") {workSize=to_int(args[i+1])}
    }
    verify(elements>0 && batches>0 && samples>0 && workSize>0)
    for(work in fixed_array(0,workSize)) {
        for(pending in fixed_array(0,1)) {
            for(name in fixed_array("next","for","zip","and_bind","move")) {
                verify(batch(name,false,32,2,work,pending)==batch(name,true,32,2,work,pending))
                for(repetition in range(samples)) {
                    var ce=0l
                    var manual=0l
                    if(repetition%2==0) {
                        ce=sample(name,false,repetition,elements,batches,work,pending)
                        manual=sample(name,true,repetition,elements,batches,work,pending)
                    } else {
                        manual=sample(name,true,repetition,elements,batches,work,pending)
                        ce=sample(name,false,repetition,elements,batches,work,pending)
                    }
                    verify(ce==manual)
                }
            }
        }
    }
    print("Async sequence benchmarks OK\n")
}
