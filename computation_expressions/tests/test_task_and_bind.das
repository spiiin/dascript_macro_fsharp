options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
[export]
def main() {
    var inscope task <- computation(TaskBuilder(type<int>)) {
        let pair=task_after_polls(0,1) |> and_bind(task_after_polls(0,2)) |> bind
        return pair.first+pair.second
    }
}
