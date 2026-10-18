options gen2
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
def batches() {return <- computation(AsyncSequenceBuilder(type<array<int>>)) {yield <- [1,2]}}
[export]
def main() {
    var inscope consumer <- computation(TaskBuilder(type<int>)) {
        var stream & = batches() |> use_resource
        let item=async_sequence_next(stream) |> bind
        return 0
    }
}
