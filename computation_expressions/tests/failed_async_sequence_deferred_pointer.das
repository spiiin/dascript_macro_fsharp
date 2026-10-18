options gen2
require ../lib/deferred_computation.das
require ../lib/async_sequence_builder.das
[export]
def main() {
    var number=1
    unsafe {
        var inscope saved <- deferred(AsyncSequenceBuilder(),addr(number)) $(snapshot) {yield 1}
    }
}
