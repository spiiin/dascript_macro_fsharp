options gen2
require ../lib/async_sequence_builder.das
require ../lib/computation_macro.das
[export]
def main() {
    var inscope stream <- computation(AsyncSequenceBuilder(type<array<int>>)) {
        var items <- [1,2]
        yield items
    }
}
