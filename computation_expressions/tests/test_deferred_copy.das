options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
[export]
def main() {
    var inscope task <- deferred(ResultBuilder()) { return 1 }
    var copy=task
}
