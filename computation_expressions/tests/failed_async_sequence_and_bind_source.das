options gen2
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
[export]
def main() {
    var inscope source <- computation(AsyncSequenceBuilder()) {
        let pair=task_after_polls(0,1) |> and_bind(2) |> bind
        yield 0
    }
}
