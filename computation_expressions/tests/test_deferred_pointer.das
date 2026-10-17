options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
struct Borrowed { pointer:int? }
[export]
def main() {
    var value=7
    var data=Borrowed(pointer=unsafe(addr(value)))
    var inscope task <- deferred(ResultBuilder(),data) $(snapshot) { return 1 }
}
