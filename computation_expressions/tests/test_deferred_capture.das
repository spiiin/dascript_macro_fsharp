options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
[export]
def main() {
    let local=7
    var inscope task <- deferred(ResultBuilder()) { return local }
}
