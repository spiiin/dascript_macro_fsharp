options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
[export]
def main() {
    var inscope task <- deferred(ResultBuilder(),7) $(snapshot:string) { return snapshot }
}
