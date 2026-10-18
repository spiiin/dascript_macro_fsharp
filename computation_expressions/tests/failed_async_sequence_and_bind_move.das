options gen2
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
[export]
def main() {
    var inscope source <- computation(AsyncSequenceBuilder()) {
        let pair=task_after_polls_move(0,[1]) |> and_bind(task_after_polls_move(0,[2])) |> bind
        yield pair.first[0]
    }
}
