options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
[export]
def main() {
    var inscope task <- deferred(SequenceBuilder()) { yield 1; yield 2 }
    for (i in range(2)) {
        var inscope seq <- run_deferred(task)
        var sum=0
        for (value in seq) { sum+=value }
        assert(sum==3)
    }
    print("deferred iterator checks OK\n")
}
